// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IConvertingFeeCalculator {
    function calculateConvertingFee(
        address account,
        uint256 amount,
        address token
    ) external view returns (uint256);
}
