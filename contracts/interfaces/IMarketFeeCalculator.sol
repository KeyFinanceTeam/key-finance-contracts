// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IMarketFeeCalculator {
    function calculateMarketBuyerFee(
        address account,
        address token,
        uint256 amount
    ) external pure returns (uint256);

    function calculateMarketSellerFee(
        address account,
        address token,
        uint256 amount
    ) external pure returns (uint256);
}
