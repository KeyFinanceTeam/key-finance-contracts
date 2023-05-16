// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

interface IRewardTracker {
    function unstake(address _depositToken, uint256 _amount) external;
    function transfer(address _recipient, uint256 _amount) external returns (bool);
    function stakedAmounts(address account) external view returns (uint256);
    function depositBalances(address account, address depositToken) external view returns (uint256);
    function claimable(address _account) external view returns (uint256);
    function glp() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function averageStakedAmounts(address account) external view returns (uint256);
    function cumulativeRewards(address account) external view returns (uint256);

}