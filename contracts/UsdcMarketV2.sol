// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./common/BaseMarketV2.sol";

contract UsdcMarketV2 is BaseMarketV2 {

    uint256 public constant DENOMINATOR_FOR_6_DECIMALS = 1e12;

    IERC20 public constant USDC = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);

    constructor(
        address _admin,
        address _config,
        IERC20 _token,
        address _staker,
        address _feeCalculator,
        address _treasury,
        uint256 _tick_size,
        uint256 _max_price
    ) BaseMarketV2(_admin, _config, USDC, _token, _staker, _feeCalculator, _treasury, _tick_size, _max_price) {}

    function _toCurrencyAmount(uint256 _amount, uint256 _price) internal override pure returns (uint256) {
        return super._toCurrencyAmount(_amount, _price) / DENOMINATOR_FOR_6_DECIMALS;
    }

}