// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./common/BaseToken.sol";

/**
 * @title GMXkey
 * @notice
 * A simple ERC20 contract with minters
 * This token will be issued in a 1:1 ratio corresponding to the amount of pan-GMX tokens (GMX, esGMX) held.
 */
contract GMXkey is BaseToken {
    constructor(address _admin) BaseToken(_admin, "GMX-KEY Token", "GMXkey") {}
}
