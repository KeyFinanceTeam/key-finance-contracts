// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./interfaces/IConfig.sol";
import "./interfaces/IConverter.sol";
import "./interfaces/IRewardTracker.sol";
import "./interfaces/ITransferReceiver.sol";
import "./interfaces/IConvertingFeeCalculator.sol";
import "./interfaces/IERC20.sol";
import "./common/ConfigUser.sol";
import "./common/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title Converter
 * @author Key Finance
 * @notice 
 * 
 * The main purpose of this contract is to liquidate GMX, esGMX, and the corresponding Multiplier Points (hereinafter referred to as MP) that are staked in the GMX protocol. 
 * This is also called as 'Convert', and when it is completed, GMX tokens (GMX, esGMX) are converted to GMXkey, and MP is converted to MPkey.
 * 
 * The method of liquidating GMX, esGMX, and MP using this contract is as follows:
 * 
 * Prerequisite: There should be no tokens deposited in both the GMX vesting vault and GLP vesting vault on the GMX protocol.
 * 
 * 1. From the account that wants to liquidate GMX, esGMX, and MP, call createTransferReceiver() to deploy an ITransferReceiver(receiver) contract that can receive GMX, esGMX, and MP.
 * 2. From the account that wants to liquidate GMX, esGMX, and MP, call the signalTransfer(receiver) function in the GMX RewardRouter contract.
 * 3. From the account that wants to liquidate GMX, esGMX, and MP, call the completeConversion function to liquidate GMX, esGMX, and MP. 
 *    At this time, the acceptTransfer(sender) function of the RewardRouter is called. Consequently, the received tokens, GMX and esGMX, are liquidated to GMXkey, and MP is liquidated to MPkey.
 * 
 * This contract contains the necessary functions for the above process.
 * Additionally, it provides an admin function for creating MPkey from GMX/esGMX, which is necessary for setting up the DEX pool initially.
 */
contract Converter is IConverter, IReserved, ConfigUser, ReentrancyGuard, Pausable {

    // constants
    uint16 public constant TEN_THOUSANDS = 10000;

    // external contracts
    address public immutable gmx;
    address public immutable esGmx;
    address public immutable bnGmx;
    IRewardRouter public immutable rewardRouter;
    address public immutable stakedGmxTracker;
    address public immutable feeGmxTracker;
    address public immutable stakedGlp;

    // key protocol contracts & addresses
    address public immutable GMXkey;
    address public immutable esGMXkey;
    address public immutable MPkey;
    address public immutable rewards;
    address public treasury;
    address public operator;
    address public transferReceiver;
    address public feeCalculator;

    // state variables
    mapping(address => address) public receivers;
    uint128 public minGmxAmount;
    uint32 public qualifiedRatio; // 0.01% = 1 & can be over 100%
    mapping(address => bool) public isForMpKey;
    address[] public registeredReceivers;
    mapping(address => bool) public isValidReceiver;
    mapping(address => mapping(address => uint256)) public convertedAmount;
    Reserved public feeCalculatorReserved;

    constructor(
        address _admin,
        address _config,
        address _GMXkey,
        address _esGMXkey,
        address _MPkey,
        IRewardRouter _rewardRouter,
        address _stakedGlp,
        address _rewards,
        address _treasury,
        address _transferReceiver,
        address _feeCalculator
    ) Pausable(_admin) ConfigUser(_config) {
        require(_GMXkey != address(0), "Converter: GMXkey is the zero address");
        require(_esGMXkey != address(0), "Converter: esGMXkey is the zero address");
        require(_MPkey != address(0), "Converter: MPkey is the zero address");
        require(address(_rewardRouter) != address(0), "Converter: rewardRouter is the zero address");
        require(_stakedGlp != address(0), "Converter: stakedGlp is the zero address");
        require(_rewards != address(0), "Converter: rewards is the zero address");
        require(_treasury != address(0), "Converter: treasury is the zero address");
        require(_transferReceiver != address(0), "Converter: transferReceiver is the zero address");
        require(_feeCalculator != address(0), "Converter: feeCalculator is the zero address");
        GMXkey = _GMXkey;
        esGMXkey = _esGMXkey;
        MPkey = _MPkey;
        gmx = _rewardRouter.gmx();
        esGmx = _rewardRouter.esGmx();
        bnGmx = _rewardRouter.bnGmx();
        require(esGmx != address(0), "Converter: esGmx is the zero address");
        rewardRouter = _rewardRouter;
        stakedGmxTracker = _rewardRouter.stakedGmxTracker();
        require(stakedGmxTracker != address(0), "Converter: stakedGmxTracker is the zero address");
        feeGmxTracker = _rewardRouter.feeGmxTracker();
        require(feeGmxTracker != address(0), "Converter: feeGmxTracker is the zero address");
        stakedGlp = _stakedGlp;
        rewards = _rewards;
        treasury = _treasury;
        transferReceiver = _transferReceiver;
        feeCalculator = _feeCalculator;
        operator = _admin;
    }

    // - config functions - //

    // Sets treasury address
    function setTreasury(address _treasury) external onlyAdmin {
        require(_treasury != address(0), "Converter: treasury is the zero address");
        treasury = _treasury;
    }

    // Sets operator address
    function setOperator(address _operator) external onlyAdmin {
        require(_operator != address(0), "Converter: operator is the zero address");
        operator = _operator;
    }

    // Sets transferReceiver address
    function setTransferReceiver(address _transferReceiver) external onlyAdmin {
        require(_transferReceiver != address(0), "Converter: transferReceiver is the zero address");
        transferReceiver = _transferReceiver;
    }

    /**
     * @notice Reserves to set feeCalculator contract.
     * @param _feeCalculator contract address
     * @param _at _feeCalculator can be set after this time
     *
     */
    function reserveFeeCalculator(address _feeCalculator, uint256 _at) external onlyAdmin {
        require(_feeCalculator != address(0), "Converter: feeCalculator is the zero address");
        require(_at >= IConfig(config).getUpgradeableAt(), "Converter: at should be later");
        feeCalculatorReserved = Reserved(_feeCalculator, _at);
        emit ConvertingFeeCalculatorReserved(_feeCalculator, _at);
    }

    // Sets reserved FeeCalculator contract.
    function setFeeCalculator() external onlyAdmin {
        require(feeCalculatorReserved.at != 0 && feeCalculatorReserved.at <= block.timestamp, "Converter: feeCalculator is not yet available");
        feeCalculator = feeCalculatorReserved.to;
    }

    /**
     * @notice Sets whether an account attempting to Convert can do so when the ratio of MP (Multiplier Points) to the staked GMX+esGMX amount in the GMX protocol is above a certain level.
     * If there are esGMX already staked in the vesting vault, they are included when comparing with this threshold value.
     * @param _minGmxAmount An account must have staked at least this argument's worth of GMX+esGMX in order to Convert.
     * @param _qualifiedRatio As a result, the account can Convert only if the ratio of MP to the staked GMX+esGMX amount is greater than or equal to the value received by this argument. It is set in units of 0.01%. 10,000 = 100%
     */
    function setQualification(uint128 _minGmxAmount, uint32 _qualifiedRatio) external onlyAdmin {
        minGmxAmount = _minGmxAmount;
        qualifiedRatio = _qualifiedRatio;
    }

    // - external state-changing functions - //

    /**
     * @notice From the account that wants to liquidate GMX, esGMX, and MP, this function deploys an ITransferReceiver(receiver) contract that can receive GMX, esGMX, and MP.
     * An account that has already called this function once cannot deploy it again through this function. 
     * If you want to Convert tokens held in an account that has already gone through the process once, you can create another account, 
     * transfer the tokens there first, and then call this function to proceed with the Convert.
     */
    function createTransferReceiver() external nonReentrant whenNotPaused {
        require(receivers[msg.sender] == address(0), "Converter: receiver already created");

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(transferReceiver),
            abi.encodeWithSelector(ITransferReceiver(transferReceiver).initialize.selector,
                operator,
                config,
                address(this),
                rewardRouter,
                stakedGlp,
                rewards
            )
        );

        receivers[msg.sender] = address(proxy);
        emit ReceiverCreated(msg.sender, address(proxy));
    }

    /**
     * @notice Approves the admin to use the msg.sender's staked tokens, which are to be converted as MPkey only
     * @param _receiver address of the receiver contract
     * @param approved boolean value to approve or disapprove
     */
    function approveMpKeyConversion(address _receiver, bool approved) external onlyAdmin {
        isForMpKey[_receiver] = approved;
    }

    /**
     * @notice Liquidates the received GMX, esGMX, and MP into GMXkey, esGMXkey and MPkey, respectively, by calling the acceptTransfer function of the RewardRouter thru TransferReceiver.
     * At this time, fee is collected at the specified rate and sent to the treasury.
     */
    function completeConversion() external nonReentrant whenNotPaused {
        // At the time of calling this function, the sender's vesting tokens must be zero; 
        // otherwise, the rewardRouter.acceptTransfer function call will fail.

        require(!isForMpKey[msg.sender], "Converter: approved to mint MPkey");

        // Make the receiver contract call the RewardRouter.acceptTransfer function and handle the side-effects related to esGMX/GLP.
        address _receiver = receivers[msg.sender];
        require(_receiver != address(0), "Converter: receiver is not created yet");
        
        _addToRegisteredReceivers(_receiver);
        
        ITransferReceiver(_receiver).acceptTransfer(msg.sender, false);

        // Mint GMXkey and MPkey in amounts corresponding to the received GMX & esGMX and MP, respectively.
        uint256 gmxAmountReceived = IRewardTracker(stakedGmxTracker).depositBalances(_receiver, gmx);
        uint256 esGmxAmountReceived = IRewardTracker(stakedGmxTracker).depositBalances(_receiver, esGmx);
        uint256 mpAmountReceived = IRewardTracker(feeGmxTracker).depositBalances(_receiver, bnGmx);

        require(gmxAmountReceived + esGmxAmountReceived >= minGmxAmount, "Converter: not enough GMX staked to convert");

        // Check the ratio of pan-GMX tokens & Multiplier Point is higher than standard
        require(mpAmountReceived * TEN_THOUSANDS / (gmxAmountReceived + esGmxAmountReceived) >= qualifiedRatio,
            "Converter: gmx/mp ratio is not qualified");

        _mintAndTransferFee(msg.sender, GMXkey, gmxAmountReceived);
        _mintAndTransferFee(msg.sender, esGMXkey, esGmxAmountReceived);
        _mintAndTransferFee(msg.sender, MPkey, mpAmountReceived);

        convertedAmount[msg.sender][GMXkey] = gmxAmountReceived;
        convertedAmount[msg.sender][esGMXkey] = esGmxAmountReceived;
        convertedAmount[msg.sender][MPkey] = mpAmountReceived;

        emit ConvertCompleted(msg.sender, _receiver, gmxAmountReceived, esGmxAmountReceived, mpAmountReceived);
    }

    /**
     * @notice This function is designed to mint and provide some MPkey to the DEX pool.
     * It is acceptable to mint MPkey by locking up GMX, as it is inferior to GMXkey, which is minted by locking up GMX.
     * @param sender The account that wants to mint MPkey
     */
    function completeConversionToMpKey(address sender) external nonReentrant onlyAdmin {
        // At the time of calling this function, the sender's vesting tokens must be zero; 
        // otherwise, the rewardRouter.acceptTransfer function call will fail.

        require(isForMpKey[sender], "Converter: not approved to mint MPkey");

        // Make the receiver contract call the RewardRouter.acceptTransfer function and handle the side-effects related to esGMX/GLP.
        address _receiver = receivers[sender];
        require(_receiver != address(0), "Converter: receiver is not created yet");
        
        _addToRegisteredReceivers(_receiver);
        
        ITransferReceiver(_receiver).acceptTransfer(sender, true);

        // Mint MPkey in amounts corresponding to the received GMX, esGMX and MP.
        uint256 amountReceived = IRewardTracker(feeGmxTracker).stakedAmounts(_receiver);
        _mintAndTransferFee(sender, MPkey, amountReceived);


        emit ConvertForMpCompleted(sender, _receiver, amountReceived);
    }

    // - external view functions - //

    function registeredReceiversLength() external view returns (uint256) {
        return registeredReceivers.length;
    }

    // - no external functions called by other key protocol contracts - //

    // - internal functions - //

    /**
     * Mints tokens in the requested amount and charge a fee
     * @param to the account to receive the minted tokens.
     * @param _token the target token for minting and charging fees.
     * @param amountReceived the amount of the target token for minting and charging fees.
     */
    function _mintAndTransferFee(address to, address _token, uint256 amountReceived) internal {
        // Mint _token as much as the amount of the corresponding token received.
        uint256 fee = IConvertingFeeCalculator(feeCalculator).calculateConvertingFee(to, amountReceived, _token);
        IERC20(_token).mint(to, amountReceived - fee);
        // Transfer a portion of it to the treasury.
        IERC20(_token).mint(treasury, fee);
    }

    function _addToRegisteredReceivers(address _receiver) internal {
        registeredReceivers.push(_receiver);
        isValidReceiver[_receiver] = true;
    }
}