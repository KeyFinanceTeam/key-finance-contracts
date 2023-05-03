// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./interfaces/ITransferReceiver.sol";
import "./interfaces/IRewardRouter.sol";
import "./interfaces/IRewardTracker.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IRewards.sol";
import "./interfaces/IConverter.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IConfig.sol";
import "./common/SafeERC20.sol";
import "./common/Adminable.sol";
import "./common/ConfigUser.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./common/Pausable.sol";

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
contract TransferReceiver is ITransferReceiver, ConfigUser, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // external contracts
    IRewardRouter public immutable rewardRouter;
    address public immutable stakedGlpTracker;
    address public immutable weth;
    address public immutable esGmx;
    address public immutable stakedGlp;

    // key protocol contracts
    address public immutable GMXkey;
    address public immutable MPkey;
    address public immutable converter;
    address public immutable rewards;
    
    // state variables
    Reserved public signalTransferReserved;
    bool public accepted;
    bool public isForMpKey;

    constructor(
        address _admin,
        address _config,
        address _converter,
        IRewardRouter _rewardRouter,
        address _stakedGlp,
        address _rewards,
        address _gmxKey,
        address _mpKey
    ) Pausable(_admin) ConfigUser(_config) {
        require(_converter != address(0), "TransferReceiver: converter is the zero address");
        require(address(_rewardRouter) != address(0), "TransferReceiver: rewardRouter is the zero address");
        require(_stakedGlp != address(0), "TransferReceiver: stakedGlp is the zero address");
        require(_rewards != address(0), "TransferReceiver: rewards is the zero address");
        require(_gmxKey != address(0), "TransferReceiver: GMXkey is the zero address");
        require(_mpKey != address(0), "TransferReceiver: MPkey is the zero address");
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
        GMXkey = _gmxKey;
        MPkey = _mpKey;
    }

    // - config functions - //

    /**
     * Reserve signalTransfer function, able to be called after a certain time.
     * @param to The new receiver contract that will receive all the staked tokens.
     * @param at After this time, the signalTransfer function can be called.
     */
    function reserveSignalTransfer(address to, uint256 at) external onlyAdmin {
        require(accepted, "TransferReceiver: not yet accepted");
        require(to != address(0), "TransferReceiver: to is the zero address");
        require(at >= IConfig(config).getUpgradeableAt(), "TransferReceiver: at is in the past");
        signalTransferReserved = Reserved(to, at);
    }

    // - external state-changing functions - //

    /**
     * Settles various rewards allocated by the GMX protocol to this contract.
     * Claims rewards in the form of GMX, esGMX, and WETH,
     * calculates and updates related values for the resulting GMXkey and MPkey staking rewards.
     * Transfers GMXkey, MPkey, and WETH fees to the calling account.
     */
    function claimAndUpdateReward(address feeTo) external nonReentrant whenNotPaused {
        uint256 wethBalanceDiff = IERC20(weth).balanceOf(address(this));
        rewardRouter.handleRewards(false, false, true, true, true, true, false);
        wethBalanceDiff = IERC20(weth).balanceOf(address(this)) - wethBalanceDiff;
        if (wethBalanceDiff > 0) IERC20(weth).safeIncreaseAllowance(rewards, wethBalanceDiff);
        IRewards(rewards).updateAllRewardsForTransferReceiverAndTransferFee(address(this), feeTo);
    }

    /**
     * Call RewardRouter.signalTransfer to notify the new receiver contract 'to' that it can accept the transfer.
     */
    function signalTransfer() external nonReentrant whenNotPaused {
        require(signalTransferReserved.at <= block.timestamp, "TransferReceiver: not yet available");
        rewardRouter.signalTransfer(signalTransferReserved.to);
        // Approval is needed for a later upgrade of this contract (enabling transfer process including signalTransfer & acceptTransfer).
        // According to the RewardTracker contract, this allowance can only be used for staking GMX to stakedGmxTracker itself.
        // https://github.com/gmx-io/gmx-contracts/blob/master/contracts/staking/RewardTracker.sol#L241
        IERC20(rewardRouter.gmx()).safeIncreaseAllowance(rewardRouter.stakedGmxTracker(), type(uint256).max);
    }

    // - external function called by other key protocol contracts - //

    /**
     * @notice Receives tokens and performs processing for tokens that need to be additionally staked or returned.
     * @param sender Account that transferred tokens to this contract.
     */
    function acceptTransfer(address sender, bool _isForMpKey) external nonReentrant whenNotPaused {
        require(msg.sender == converter, "only converter");

        // Transfers all remaining staked tokens, possibly GMX, esGMX, GLP, etc.
        rewardRouter.acceptTransfer(sender);
        emit TransferAccepted(sender);

        // All esGMX balances will be staked, which will be converted to GMXkeys.
        uint256 esGmxBalance = IERC20(esGmx).balanceOf(address(this));
        if (esGmxBalance > 0) rewardRouter.stakeEsGmx(esGmxBalance);
        
        // Transfer GLP back to the sender.
        uint256 stakedGlpBalance = IRewardTracker(stakedGlpTracker).balanceOf(address(this));
        if (stakedGlpBalance > 0) IERC20(stakedGlp).safeTransfer(sender, stakedGlpBalance);

        isForMpKey = _isForMpKey;

        IRewards(rewards).initTransferReceiver();
        accepted = true;
    }

    /**
     * Withdraw any additional reward given by GMX protocol to distribute it to the GMXkey & MPkey stakers.
     * @notice This function is only for temporary use. It will be not used after the upgrade of this contract.
     * @param token The token to withdraw
     * @param to The address to send the token to
     */
    function withdrawTokens(address token, address to) external onlyAdmin {
        require(token != address(0), "TransferReceiver: token is the zero address");
        require(to != address(0), "TransferReceiver: to is the zero address");
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(to, balance);
        }
    }

}
