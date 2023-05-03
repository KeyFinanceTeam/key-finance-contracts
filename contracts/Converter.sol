// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./interfaces/IConverter.sol";
import "./interfaces/IRewardTracker.sol";
import "./interfaces/ITransferReceiver.sol";
import "./interfaces/IERC20.sol";
import "./common/Adminable.sol";
import "./common/ConfigUser.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./common/Pausable.sol";
import "./TransferReceiver.sol";

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
contract Converter is IConverter, ConfigUser, ReentrancyGuard, Pausable {

    // constants
    uint16 public constant FEE_RATE_BASE = 10000; // The denominator value used when calculating the original value of the feeRate (0.01% = 1)

    // external contracts
    address public immutable esGmx;
    IRewardRouter public immutable rewardRouter;
    address public immutable stakedGmxTracker;
    address public immutable feeGmxTracker;
    address public immutable stakedGlp;

    // key protocol contracts & addresses
    address public immutable GMXkey;
    address public immutable MPkey;
    address public immutable rewards;
    address public treasury;

    // state variables    
    mapping(address => address) public receivers;
    mapping(address => uint16) public feeRate; // 0.01% = 1
    uint128 public minGmxAmount;
    uint32 public qualifiedRatio; // 0.01% = 1 & can be over 100%
    mapping(address => bool) public isForMpKey;
    mapping(address => uint256) public receiverActiveAt;

    constructor(
        address _admin,
        address _config,
        address _GMXkey,
        address _MPkey,
        IRewardRouter _rewardRouter,
        address _stakedGlp,
        address _rewards,
        address _treasury,
        uint16 _gmxKeyFeeRate,
        uint16 _mpKeyFeeRate
    ) Pausable(_admin) ConfigUser(_config) {
        require(_GMXkey != address(0), "Converter: GMXkey is the zero address");
        require(_MPkey != address(0), "Converter: MPkey is the zero address");
        require(address(_rewardRouter) != address(0), "Converter: rewardRouter is the zero address");
        require(_stakedGlp != address(0), "Converter: stakedGlp is the zero address");
        require(_rewards != address(0), "Converter: rewards is the zero address");
        require(_treasury != address(0), "Converter: treasury is the zero address");
        require(_gmxKeyFeeRate <= FEE_RATE_BASE, "Converter: GMXkey fee ratio should be less than or equal to 10000");
        require(_mpKeyFeeRate <= FEE_RATE_BASE, "Converter: MPkey fee ratio should be less than or equal to 10000");
        GMXkey = _GMXkey;
        MPkey = _MPkey;
        esGmx = _rewardRouter.esGmx();
        require(esGmx != address(0), "Converter: esGmx is the zero address");
        rewardRouter = _rewardRouter;
        stakedGmxTracker = _rewardRouter.stakedGmxTracker();
        require(stakedGmxTracker != address(0), "Converter: stakedGmxTracker is the zero address");
        feeGmxTracker = _rewardRouter.feeGmxTracker();
        require(feeGmxTracker != address(0), "Converter: feeGmxTracker is the zero address");
        stakedGlp = _stakedGlp;
        rewards = _rewards;
        treasury = _treasury;
        feeRate[_GMXkey] = _gmxKeyFeeRate;
        feeRate[_MPkey] = _mpKeyFeeRate;
    }

    // - config functions - //

    // set treasury address
    function setTreasury(address _treasury) external onlyAdmin {
        require(_treasury != address(0), "Converter: treasury is the zero address");
        treasury = _treasury;
    }

    /**
     * Register the receiver contract to be used for the upgrade
     * @param newReceiver newly deployed receiver contract
     */
    function registerReceiver(address newReceiver, uint256 activeAt) external onlyAdmin {
        require(newReceiver != address(0), "Converter: newReceiver is the zero address");
        require(activeAt >= IConfig(config).getUpgradeableAt(), "Converter: activeAt should be later than upgradeable time");
        receiverActiveAt[newReceiver] = activeAt;
        emit ReceiverRegistered(newReceiver, activeAt);
    }

    /**
     * Set how much fee will be charged for the GMXkey and MPkey to be received during the Convert process.
     * @param _token A fee is charged for the type of token received as this argument. Both GMXkey and MPkey are possible.
     * @param _feeRate Set how much fee will be charged. It is set in units of 0.01%. 10,000 = 100%
     */
    function setFeeRate(address _token, uint16 _feeRate) external onlyAdmin {
        require(_token == GMXkey || _token == MPkey, "Converter: token should be GMXkey or MPkey");
        require(_feeRate <= FEE_RATE_BASE, "Converter: fee ratio should be less than or equal to 10000");
        feeRate[_token] = _feeRate;
    }

    /**
     * Set whether an account attempting to Convert can do so when the ratio of MP (Multiplier Points) to the staked GMX+esGMX amount in the GMX protocol is above a certain level.
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
     * From the account that wants to liquidate GMX, esGMX, and MP, this function deploys an ITransferReceiver(receiver) contract that can receive GMX, esGMX, and MP.
     * An account that has already called this function once cannot deploy it again through this function. 
     * If you want to Convert tokens held in an account that has already gone through the process once, you can create another account, 
     * transfer the tokens there first, and then call this function to proceed with the Convert.
     */
    function createTransferReceiver() external nonReentrant whenNotPaused {
        require(receivers[msg.sender] == address(0), "Converter: receiver already created");

        TransferReceiver newReceiver = new TransferReceiver(
            admin,
            config,
            address(this),
            rewardRouter,
            stakedGlp,
            rewards,
            GMXkey,
            MPkey
        );
        receivers[msg.sender] = address(newReceiver);
        receiverActiveAt[address(newReceiver)] = 1;

        emit ReceiverCreated(msg.sender, address(newReceiver));
    }

    /**
     * Approve the admin to use the msg.sender's staked tokens, which are to be converted as MPkey only
     * @param approved boolean value to approve or disapprove
     */
    function approveMpKeyConversion(bool approved) external {
        isForMpKey[msg.sender] = approved;
    }

    /**
     * Liquidates the received GMX, esGMX, and MP into GMXkey and MPkey, respectively, by calling the acceptTransfer function of the RewardRouter thru TransferReceiver.
     * At this time, fee is collected at the specified rate and sent to the treasury.
     */
    function completeConversion() external nonReentrant whenNotPaused {
        // At the time of calling this function, the sender's vesting tokens must be zero; 
        // otherwise, the rewardRouter.acceptTransfer function call will fail.

        require(!isForMpKey[msg.sender], "Converter: approved to mint MPkey");

        // Make the receiver contract call the RewardRouter.acceptTransfer function and handle the side-effects related to esGMX/GLP.
        address _receiver = receivers[msg.sender];
        require(_receiver != address(0), "Converter: receiver is not created yet");
        ITransferReceiver(_receiver).acceptTransfer(msg.sender, false);

        // Mint GMXkey and MPkey in amounts corresponding to the received GMX & esGMX and MP, respectively.
        uint256 gmxAmountReceived = IRewardTracker(stakedGmxTracker).stakedAmounts(_receiver);
        uint256 mpAmountReceived = IRewardTracker(feeGmxTracker).stakedAmounts(_receiver) - gmxAmountReceived;

        require(gmxAmountReceived >= minGmxAmount, "Converter: not enough GMX staked to convert");

        // Check the ratio of pan-GMX tokens & Multiplier Point is higher than standard
        require(mpAmountReceived * FEE_RATE_BASE / gmxAmountReceived >= qualifiedRatio,
            "Converter: gmx/mp ratio is not qualified");

        _mintAndTransferFee(msg.sender, GMXkey, gmxAmountReceived);
        _mintAndTransferFee(msg.sender, MPkey, mpAmountReceived);

        receiverActiveAt[_receiver] = block.timestamp;

        emit ConvertCompleted(msg.sender, _receiver, gmxAmountReceived, mpAmountReceived);
    }

    /**
     * This function is designed to mint and provide some MPkey to the DEX pool.
     * It is acceptable to mint MPkey by locking up GMX, as it is inferior to GMXkey, which is minted by locking up GMX.
     */
    function completeConversionToMpKey(address sender) external onlyAdmin nonReentrant {
        // At the time of calling this function, the sender's vesting tokens must be zero; 
        // otherwise, the rewardRouter.acceptTransfer function call will fail.

        require(isForMpKey[sender], "Converter: not approved to mint MPkey");

        // Make the receiver contract call the RewardRouter.acceptTransfer function and handle the side-effects related to esGMX/GLP.
        address _receiver = receivers[sender];
        require(_receiver != address(0), "Converter: receiver is not created yet");
        ITransferReceiver(_receiver).acceptTransfer(sender, true);

        // Mint MPkey in amounts corresponding to the received GMX, esGMX and MP.
        uint256 amountReceived = IRewardTracker(feeGmxTracker).stakedAmounts(_receiver);
        _mintAndTransferFee(sender, MPkey, amountReceived);

        receiverActiveAt[_receiver] = block.timestamp;

        emit ConvertForMpCompleted(sender, _receiver, amountReceived);
    }

    // - external view functions - //

    /**
     * Returns whether the receiver has completed the conversion process.
     * @param _receiver receiver contract address
     * @return true if the receiver contract is currently in use, meaning it has staked tokens and claimable rewards.
     */
    function isActiveReceiver(address _receiver) external view returns (bool) {
        uint256 activeAt = receiverActiveAt[_receiver];
        return activeAt > 1 && activeAt <= block.timestamp;
    }

    // - no external functions called by other key protocol contracts - //

    // - internal functions - //

    /**
     * Mint tokens in the requested amount and charge a fee corresponding to the feeRate.
     * @param _token the target token for minting and charging fees.
     * @param amountReceived the amount of the target token for minting and charging fees.
     */
    function _mintAndTransferFee(address to, address _token, uint256 amountReceived) internal {
        // Mint _token as much as the amount of the corresponding token received.
        uint256 fee = amountReceived * feeRate[_token] / FEE_RATE_BASE;
        IERC20(_token).mint(to, amountReceived - fee);
        // Transfer a portion of it to the treasury.
        IERC20(_token).mint(treasury, fee);
    }
}