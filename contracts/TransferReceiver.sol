// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./interfaces/ITransferReceiver.sol";
import "./interfaces/IRewardRouter.sol";
import "./interfaces/IRewardTracker.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IRewards.sol";
import "./interfaces/IConfig.sol";
import "./common/SafeERC20.sol";
import "./common/ConfigUserInitializable.sol";
import "./common/PausableInitializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title TransferReceiver
 * @author Key Finance
 * @notice
 * This contract is used to receive tokens (GMX, esGMX) and MP(Multiplier Point) when they are liquidated (during Convert).
 * Due to GMX protocol constraints, an unused account capable of receiving GMX, esGMX, and MP is needed when liquidating them. 
 * This contract serves as that account.
 * A new contract is deployed and used each time a new account uses the Convert feature.
 * 
 * This contract includes functions for initially receiving tokens and for settling rewards generated later.
 */
contract TransferReceiver is ITransferReceiver, Initializable, UUPSUpgradeable, ConfigUserInitializable, ReentrancyGuardUpgradeable, PausableInitializable {
    using SafeERC20 for IERC20;

    uint256 private _version;

    // external contracts
    IRewardRouter public rewardRouter;
    address public stakedGlpTracker;
    address public weth;
    address public esGmx;
    address public stakedGlp;

    // key protocol contracts
    address public converter;
    address public rewards;
    address public transferSender;

    // state variables
    Reserved public transferSenderReserved;
    Reserved public newTransferReceiverReserved;
    bool public accepted;
    bool public isForMpKey;

    constructor() {
        stakedGlpTracker = address(0xdead);
        // prevent any update on the state variables
    }

    function initialize(
        address _admin,
        address _config,
        address _converter,
        IRewardRouter _rewardRouter,
        address _stakedGlp,
        address _rewards
    ) external initializer {
        require(stakedGlpTracker == address(0), "TransferReceiver: already initialized");

        __UUPSUpgradeable_init();
        __ConfigUser_init(_config);
        __Pausable_init(_admin);
        __ReentrancyGuard_init();

        require(_converter != address(0), "TransferReceiver: converter is the zero address");
        require(address(_rewardRouter) != address(0), "TransferReceiver: rewardRouter is the zero address");
        require(_stakedGlp != address(0), "TransferReceiver: stakedGlp is the zero address");
        require(_rewards != address(0), "TransferReceiver: rewards is the zero address");
        converter = _converter;
        rewardRouter = _rewardRouter;
        stakedGlpTracker = _rewardRouter.stakedGlpTracker();
        require(stakedGlpTracker != address(0), "TransferReceiver: stakedGlpTracker is the zero address");
        esGmx = _rewardRouter.esGmx();
        require(esGmx != address(0), "TransferReceiver: esGmx is the zero address");
        stakedGlp = _stakedGlp;
        require(stakedGlp != address(0), "TransferReceiver: stakedGlp is the zero address");
        weth = _rewardRouter.weth();
        require(weth != address(0), "TransferReceiver: stakedGlp is the zero address");
        rewards = _rewards;
        _version = 0;
    }

    modifier onlyTransferSender() {
        require(msg.sender == transferSender, "only transferSender");
        _;
    }

    // - config functions - //

    /**
     * @notice Reserves to set TransferSender contract.
     * @param _transferSender contract address
     * @param _at transferSender can be set after this time
     *
     */
    function reserveTransferSender(address _transferSender, uint256 _at) external onlyAdmin {
        require(_transferSender != address(0), "TransferReceiver: transferSender is the zero address");
        require(_at >= IConfig(config).getUpgradeableAt(), "TransferReceiver: at should be later");
        transferSenderReserved = Reserved(_transferSender, _at);
        emit TransferSenderReserved(_transferSender, _at);
    }

    /**
     * @notice Sets reserved TransferSender contract.
     */
    function setTransferSender() external onlyAdmin {
        require(transferSenderReserved.at != 0 && transferSenderReserved.at <= block.timestamp, "TransferReceiver: transferSender is not yet available");
        transferSender = transferSenderReserved.to;
    }

    /**
     * @notice Reserves TransferReceiver upgrade. Only can be upgraded after a certain time.
     * @param _newTransferReceiver The new TransferReceiver contract to be upgraded.
     * @param _at After this time, _authorizeUpgrade function can be passed.
     */
    function reserveNewTransferReceiver(address _newTransferReceiver, uint256 _at) external onlyAdmin {
        require(accepted, "TransferReceiver: not yet accepted");
        require(_newTransferReceiver != address(0), "TransferReceiver: _newTransferReceiver is the zero address");
        require(_at >= IConfig(config).getUpgradeableAt(), "TransferReceiver: at should be later");
        newTransferReceiverReserved = Reserved(_newTransferReceiver, _at);
        emit NewTransferReceiverReserved(_newTransferReceiver, _at);
    }

    // - external state-changing functions - //

    /**
     * @notice Settles various rewards allocated by the GMX protocol to this contract.
     * Claims rewards in the form of GMX, esGMX, and WETH,
     * calculates and updates related values for the resulting esGMXkey and MPkey staking rewards.
     * Transfers esGMXkey, MPkey, and WETH fees to the calling account.
     * @param feeTo Account to transfer fee to.
     */
    function claimAndUpdateReward(address feeTo) external nonReentrant whenNotPaused {
        uint256 wethBalanceDiff = IERC20(weth).balanceOf(address(this));
        rewardRouter.handleRewards(false, false, true, true, true, true, false);
        wethBalanceDiff = IERC20(weth).balanceOf(address(this)) - wethBalanceDiff;
        if (wethBalanceDiff > 0) IERC20(weth).safeIncreaseAllowance(rewards, wethBalanceDiff);
        IRewards(rewards).updateAllRewardsForTransferReceiverAndTransferFee(feeTo);
    }

    /**
     * @notice Calls signalTransfer to make 'to' account able to accept transfer.
     * @param to Account to transfer tokens to.
     */
    function signalTransfer(address to) external nonReentrant whenNotPaused onlyTransferSender {
        require(accepted, "TransferReceiver: not yet accepted");
        _signalTransfer(to);
    }

    // - external function called by other key protocol contracts - //

    /**
     * @notice Receives tokens and performs processing for tokens that need to be additionally staked or returned.
     * @param sender Account that transferred tokens to this contract.
     * @param _isForMpKey Whether the transferred tokens are for minting MPkey.
     */
    function acceptTransfer(address sender, bool _isForMpKey) external nonReentrant whenNotPaused {
        require(msg.sender == converter, "only converter");

        // Transfers all remaining staked tokens, possibly GMX, esGMX, GLP, etc.
        rewardRouter.acceptTransfer(sender);
        emit TransferAccepted(sender);

        // All esGMX balances will be staked, which will be converted to esGMXkeys.
        uint256 esGmxBalance = IERC20(esGmx).balanceOf(address(this));
        if (esGmxBalance > 0) rewardRouter.stakeEsGmx(esGmxBalance);

        // Transfer GLP back to the sender.
        uint256 stakedGlpBalance = IRewardTracker(stakedGlpTracker).balanceOf(address(this));
        if (stakedGlpBalance > 0) IERC20(stakedGlp).safeTransfer(sender, stakedGlpBalance);

        isForMpKey = _isForMpKey;

        IRewards(rewards).initTransferReceiver();
        accepted = true;
    }

    // - external view functions - //

    function version() external view virtual returns (uint256) {
        return _version;
    }

    // - internal functions - //

    /**
     * Call RewardRouter.signalTransfer to notify the new receiver contract 'to' that it can accept the transfer.
     */
    function _signalTransfer(address to) private {
        rewardRouter.signalTransfer(to);
        // Approval is needed for a later upgrade of this contract (enabling transfer process including signalTransfer & acceptTransfer).
        // According to the RewardTracker contract, this allowance can only be used for staking GMX to stakedGmxTracker itself.
        // https://github.com/gmx-io/gmx-contracts/blob/master/contracts/staking/RewardTracker.sol#L241
        IERC20 gmxToken = IERC20(rewardRouter.gmx());
        address stakedGmxTracker = rewardRouter.stakedGmxTracker();
        gmxToken.safeIncreaseAllowance(stakedGmxTracker, type(uint256).max);
        emit SignalTransfer(address(this), to);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyAdmin {
        require(address(newImplementation) == newTransferReceiverReserved.to, "TransferReceiver: should be same address with newTransferReceiverReserved.to");
        require(newTransferReceiverReserved.at != 0 && newTransferReceiverReserved.at <= block.timestamp, "TransferReceiver: newTransferReceiver is not yet available");
    }
}
