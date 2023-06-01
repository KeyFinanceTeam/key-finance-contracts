// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./FeeCalculatorV2.sol";

contract FeeCalculatorV3 is FeeCalculatorV2 {

    constructor(address _gmxKey, address _esGmxKey, address _mpKey) FeeCalculatorV2(_gmxKey, _esGmxKey, _mpKey) {}

    function calculateConvertingFee(
        address, // account
        uint256, // amount
        address // convertingToken
    ) public override pure returns (uint256) {
        return 0;
    }
}
