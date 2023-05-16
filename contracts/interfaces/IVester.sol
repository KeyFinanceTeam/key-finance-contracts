// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

interface IVester {
    function transferredAverageStakedAmounts(address account) external view returns (uint256);
    function transferredCumulativeRewards(address account) external view returns (uint256);
    function withdraw() external;
    function balanceOf(address account) external view returns (uint256);
}
