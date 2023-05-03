// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function withdrawTo(address to, uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}