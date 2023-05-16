// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./TransferReceiver.sol";
import "./interfaces/ITransferReceiverV2.sol";
import "./interfaces/ITransferSender.sol";
import "./common/SafeERC20.sol";

contract TransferReceiverV2 is TransferReceiver {
    using SafeERC20 for IERC20;

    // @dev replace this as a deployed TransferSender contract address before deploying TransferReceiverV2
    address public constant defaultTransferSender = 0xc6d79DeE3049319eDdB52F040A64167396a2928d;

    function version() external view virtual override returns (uint256) {
        return 1;
    }

    modifier onlyTransferSender() override {
        require(msg.sender == _getTransferSender(), "only transferSender");
        _;
    }

    /**
     * @notice Settles various rewards allocated by the GMX protocol to this contract.
     * Claims rewards in the form of GMX, esGMX, and WETH,
     * calculates and updates related values for the resulting esGMXkey and MPkey staking rewards.
     * Transfers esGMXkey, MPkey, and WETH fees to the calling account.
     * @param feeTo Account to transfer fee to.
     */
    function claimAndUpdateReward(address feeTo) external override nonReentrant whenNotPaused {
        _validateReceiver();
        uint256 wethBalanceDiff = IERC20(weth).balanceOf(address(this));
        rewardRouter.handleRewards(false, false, true, true, true, true, false);
        wethBalanceDiff = IERC20(weth).balanceOf(address(this)) - wethBalanceDiff;
        if (wethBalanceDiff > 0) IERC20(weth).safeIncreaseAllowance(rewards, wethBalanceDiff);
        IRewards(rewards).updateAllRewardsForTransferReceiverAndTransferFee(feeTo);
    }

    /**
     * @notice claimAndUpdateReward which guarantees unwrap by TransferSender even in paused state
     */
    function claimAndUpdateRewardFromTransferSender(address feeTo) external virtual nonReentrant onlyTransferSender {
        _validateReceiver();
        uint256 wethBalanceDiff = IERC20(weth).balanceOf(address(this));
        if (paused) {
            // claim only wETH
            rewardRouter.handleRewards(false, false, false, false, false, true, false);
            wethBalanceDiff = IERC20(weth).balanceOf(address(this)) - wethBalanceDiff;
            if (wethBalanceDiff > 0) IERC20(weth).transfer(feeTo, wethBalanceDiff);
        } else {
            rewardRouter.handleRewards(false, false, true, true, true, true, false);
            wethBalanceDiff = IERC20(weth).balanceOf(address(this)) - wethBalanceDiff;
            if (wethBalanceDiff > 0) IERC20(weth).safeIncreaseAllowance(rewards, wethBalanceDiff);
            IRewards(rewards).updateAllRewardsForTransferReceiverAndTransferFee(feeTo);
        }
    }

    /**
     * @notice Calls signalTransfer to make 'to' account able to accept transfer.
     * @param to Account to transfer tokens to.
     */
    function signalTransfer(address to) external override nonReentrant onlyTransferSender {
        require(accepted, "TransferReceiver: not yet accepted");
        _signalTransfer(to);
    }

    /**
     * Call RewardRouter.signalTransfer to notify the new receiver contract 'to' that it can accept the transfer.
     */
    function _signalTransfer(address to) internal override {
        rewardRouter.signalTransfer(to);
        // Approval is needed for a later upgrade of this contract (enabling transfer process including signalTransfer & acceptTransfer).
        // According to the RewardTracker contract, this allowance can only be used for staking GMX to stakedGmxTracker itself.
        // https://github.com/gmx-io/gmx-contracts/blob/master/contracts/staking/RewardTracker.sol#L241
        IERC20 gmxToken = IERC20(rewardRouter.gmx());
        address stakedGmxTracker = rewardRouter.stakedGmxTracker();
        if (gmxToken.allowance(address(this), stakedGmxTracker) == 0) {
            gmxToken.safeIncreaseAllowance(stakedGmxTracker, type(uint256).max);
        }
        emit SignalTransfer(address(this), to);
    }

    function _getTransferSender() private view returns (address) {
        if (transferSender == address(0)) return defaultTransferSender;
        else return transferSender;
    }

    function _validateReceiver() internal view {
        address _transferSender = _getTransferSender();
        require(!ITransferSender(_transferSender).isUnwrappedReceiver(address(this)), "TransferReceiver: unwrapped receiver");
        require(ITransferSender(_transferSender).isUnlocked(address(this)), "TransferReceiver: lock not yet expired");
    }
}
