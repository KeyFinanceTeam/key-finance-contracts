// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

interface IConfig {
    function MIN_DELAY_TIME() external pure returns (uint256);
    function upgradeDelayTime() external view returns (uint256);
    function setUpgradeDelayTime(uint256 time) external;
    function getUpgradeableAt() external view returns (uint256);
}