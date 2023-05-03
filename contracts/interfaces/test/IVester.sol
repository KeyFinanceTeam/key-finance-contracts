// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

interface IVester {
    function withdraw() external;
    function balanceOf(address account) external view returns (uint256);
}

