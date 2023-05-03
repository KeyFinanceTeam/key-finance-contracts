// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./common/BaseToken.sol";

/**
 * @title esGMXkey
 * @notice
 * A simple ERC20 contract with minters
 * This token will be issued at a 1:1 ratio, corresponding to the amount of esGMX held.
 */
contract EsGMXkey is BaseToken {
    constructor(address _admin) BaseToken(_admin, "esGMX-KEY Token", "esGMXkey") {}
}
