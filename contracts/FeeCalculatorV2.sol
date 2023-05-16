// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./FeeCalculator.sol";
import "./interfaces/ITransferSenderFeeCalculator.sol";

contract FeeCalculatorV2 is FeeCalculator, ITransferSenderFeeCalculator {

    constructor(address _gmxKey, address _esGmxKey, address _mpKey) FeeCalculator(_gmxKey, _esGmxKey, _mpKey) {}

    function calculateTransferSenderFee(
        address account,
        uint256 amount,
        address token
    ) external view returns (uint256) {
        return calculateConvertingFee(account, amount, token);
    }
}
