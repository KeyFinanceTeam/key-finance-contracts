// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./common/AdminableInitializable.sol";
import "./common/Adminable.sol";
import "./interfaces/IStakingFeeCalculator.sol";
import "./interfaces/IConvertingFeeCalculator.sol";

contract FeeCalculator is IStakingFeeCalculator, IConvertingFeeCalculator {
    uint16 public constant FEE_PERCENTAGE_BASE = 10000;
    uint16 public constant DEFAULT_CONVERTING_FEE_PERCENTAGE = 250;
    uint16 public constant DEFAULT_STAKING_FEE_PERCENTAGE = 500;

    constructor() {}

    function calculateStakingFee(
        address, // account
        uint256 amount,
        address, // stakingToken
        address // rewardToken
    ) public pure returns (uint256) {
        return amount * DEFAULT_STAKING_FEE_PERCENTAGE / FEE_PERCENTAGE_BASE;
    }

    function calculateConvertingFee(
        address, // account
        uint256 amount,
        address // convertingToken
    ) public pure returns (uint256) {
        return amount * DEFAULT_CONVERTING_FEE_PERCENTAGE / FEE_PERCENTAGE_BASE;
    }
}
