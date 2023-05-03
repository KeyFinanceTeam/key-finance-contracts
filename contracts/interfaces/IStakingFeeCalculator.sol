// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IStakingFeeCalculator {
    function calculateStakingFee(
        address account,
        uint256 amount,
        address stakingToken,
        address rewardToken
    ) external view returns (uint256);
}
