// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./IERC20.sol";

interface IStaker {
    function GMXkey() external view returns (address);
    function MPkey() external view returns (address);
    function rewards() external view returns (address);
    function balance(address token, address account) external view returns (uint256);
    function totalBalance(address token) external view returns (uint256);
    function setRewards(address _rewards) external;
    function stake(address account, address token, uint256 amount) external;
    function unstake(address account, address token, uint256 amount) external;
    event Staked(address indexed caller, address indexed onBehalfOf, address indexed token, uint256 amount);
    event Unstaked(address indexed caller, address indexed onBehalfOf, address indexed token, uint256 amount);
}