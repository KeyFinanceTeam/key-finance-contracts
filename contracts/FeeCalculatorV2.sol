// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./FeeCalculator.sol";
import "./interfaces/ITransferSenderFeeCalculator.sol";
import "./interfaces/IMarketFeeCalculator.sol";

contract FeeCalculatorV2 is FeeCalculator, ITransferSenderFeeCalculator, IMarketFeeCalculator {

    uint16 public constant DEFAULT_MARKET_FEE_PERCENTAGE = 100; //1%

    constructor(address _gmxKey, address _esGmxKey, address _mpKey) FeeCalculator(_gmxKey, _esGmxKey, _mpKey) {}

    function calculateTransferSenderFee(
        address account,
        uint256 amount,
        address token
    ) external view returns (uint256) {
        return calculateConvertingFee(account, amount, token);
    }

    function calculateMarketBuyerFee(
        address, // account,
        address,// token,
        uint256 amount
    ) external pure returns (uint256) {
        return amount * DEFAULT_MARKET_FEE_PERCENTAGE / FEE_PERCENTAGE_BASE;
    }

    function calculateMarketSellerFee(
        address, // account,
        address, // token,
        uint256 amount
    ) external pure returns (uint256) {
        return amount * DEFAULT_MARKET_FEE_PERCENTAGE / FEE_PERCENTAGE_BASE;
    }
}
