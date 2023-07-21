// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

interface IStakerV2 {
    // Events
    event Staked(address indexed user, address indexed token, uint256 amount);
    event Unstaked(address indexed user, address indexed token, uint256 amount);
    event Locked(address indexed user, address indexed token, uint256 amount);
    event Unlocked(address indexed user, address indexed token, uint256 amount);
    event MarketReserved(address indexed market, uint256 at);

    // State-changing functions
    function stake(address token, uint256 amount) external;
    function unstake(address token, uint256 amount) external;
    function updatePastTotalSharesByPeriod(address token, uint256 count) external;
    function updatePastUserSharesByPeriod(address account, address token, uint256 count) external;
    function stakeAndLock(address account, address token, uint256 amount) external;
    function unlockAndUnstake(address account, address token, uint256 amount) external;

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

    function GMXkey() external view returns (address);
    function esGMXkey() external view returns (address);
    function MPkey() external view returns (address);

    function PERIOD() external view returns (uint256);
}