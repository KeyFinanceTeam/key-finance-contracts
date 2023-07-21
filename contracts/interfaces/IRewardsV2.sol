
// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./IRewards.sol";

interface IRewardsV2 is IRewards {
    function migrateTransferReceiver() external;
}