// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

interface ITransferSenderFeeCalculator {
    function calculateTransferSenderFee(
        address account,
        uint256 amount,
        address token
    ) external view returns (uint256);
}
