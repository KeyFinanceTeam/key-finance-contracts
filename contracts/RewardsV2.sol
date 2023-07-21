// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./Rewards.sol";
import "./interfaces/ITransferReceiverV2.sol";
import "./interfaces/IRewardsV2.sol";

contract RewardsV2 is Rewards, IRewardsV2 {
    using SafeERC20 for IERC20;

    address public constant rewardsV1 = 0x8688d884BeBE0F6928E91985e7BAF51b0f06Dd6e;

    constructor(
        address _admin, 
        address _config, 
        IRewardRouter _rewardRouter, 
        address _GMXkey, 
        address _esGMXkey, 
        address _MPkey, 
        address _staker, 
        address _treasury, 
        address _feeCalculator
    ) Rewards(_admin, _config, _rewardRouter, _GMXkey, _esGMXkey, _MPkey, _staker, _treasury, _feeCalculator) {}

    function migrateTransferReceiver() external {
        require(_isCalledByValidReceiver(), "Rewards: invalid receiver");
        require(ITransferReceiverV2(msg.sender).version() >= 2, "Rewards: invalid version");
        require(lastUpdatedAt[msg.sender] == 0, "Rewards: already migrated");
        lastDepositBalancesForReceivers[msg.sender][gmx] = _oldLastDepositBalancesForReceivers(msg.sender, gmx);
        lastDepositBalancesForReceivers[msg.sender][esGmx] = _oldLastDepositBalancesForReceivers(msg.sender, esGmx);
        lastDepositBalancesForReceivers[msg.sender][bnGmx] = _oldLastDepositBalancesForReceivers(msg.sender, bnGmx);
        lastUpdatedAt[msg.sender] = IRewards(rewardsV1).lastUpdatedAt(msg.sender);
    }

    function _oldLastDepositBalancesForReceivers(address _receiver, address token) private view returns (uint256) {
        return IRewards(rewardsV1).lastDepositBalancesForReceivers(_receiver, token);
    }

}
