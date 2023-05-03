// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

interface IStaker {
    // Events
    event Staked(address indexed user, address indexed token, uint256 amount);
    event Unstaked(address indexed user, address indexed token, uint256 amount);

    // State-changing functions
    function stake(address token, uint256 amount) external;
    function unstake(address token, uint256 amount) external;
    function updatePastTotalSharesByPeriod(address token, uint256 count) external;
    function updatePastUserSharesByPeriod(address account, address token, uint256 count) external;

    // Getter functions for public variables
    function totalBalance(address token) external view returns (uint256);
    function userBalance(address user, address token) external view returns (uint256);
    function totalSharesByPeriod(address token, uint256 periodIndex) external view returns (uint256);
    function userSharesByPeriod(address user, address token, uint256 periodIndex) external view returns (uint256);
    function latestTotalShares(address token) external view returns (uint256);
    function latestTotalSharesUpdatedAt(address token) external view returns (uint256);
    function latestUserShares(address user, address token) external view returns (uint256);
    function latestUserSharesUpdatedAt(address user, address token) external view returns (uint256);

    // View functions
    function totalSharesPrevPeriod(address token) external view returns (uint256);
}