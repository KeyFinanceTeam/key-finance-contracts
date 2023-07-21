// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./TransferReceiverV2.sol";
import "./interfaces/IRewardsV2.sol";

contract TransferReceiverV3 is TransferReceiverV2 {
    using SafeERC20 for IERC20;

    // @dev replace this as a deployed Rewards contract address before deploying TransferReceiverV3
    address public constant rewardsV2 = 0xd09A4C66A0c0048561a87EE7938B406E5C6e55b3;

    function version() external view virtual override returns (uint256) {
        return 2;
    }

    function initialize(
        address _admin,
        address _config,
        address _converter,
        IRewardRouter _rewardRouter,
        address _stakedGlp,
        address
    ) public override initializer {
        super.initialize(_admin, _config, _converter, _rewardRouter, _stakedGlp, rewardsV2);
    }

    /**
     * @notice Receives tokens and performs processing for tokens that need to be additionally staked or returned.
     * @param sender Account that transferred tokens to this contract.
     * @param _isForMpKey Whether the transferred tokens are for minting MPkey.
     */
    function acceptTransfer(address sender, bool _isForMpKey) public override {
        migrateIfNeeded();
        super.acceptTransfer(sender, _isForMpKey);
    }

    /**
     * @notice Settles various rewards allocated by the GMX protocol to this contract.
     * Claims rewards in the form of GMX, esGMX, and WETH,
     * calculates and updates related values for the resulting esGMXkey and MPkey staking rewards.
     * Transfers esGMXkey, MPkey, and WETH fees to the calling account.
     * @param feeTo Account to transfer fee to.
     */
    function claimAndUpdateReward(address feeTo) public override {
        migrateIfNeeded();
        super.claimAndUpdateReward(feeTo);
    }

    /**
     * @notice claimAndUpdateReward which guarantees unwrap by TransferSender even in paused state
     */
    function claimAndUpdateRewardFromTransferSender(address feeTo) public override {
        migrateIfNeeded();
        super.claimAndUpdateRewardFromTransferSender(feeTo);
    }

    function migrateIfNeeded() public {
        if (rewards != rewardsV2) {
            rewards = rewardsV2;
            IRewardsV2(rewardsV2).migrateTransferReceiver();
        }
    }

}
