// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./IERC20.sol";

interface IERC20Burnable is IERC20 {
    function burn(uint256 amount) external returns (bool); //
}