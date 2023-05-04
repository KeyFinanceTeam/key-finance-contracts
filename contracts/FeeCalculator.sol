// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./common/AdminableInitializable.sol";
import "./common/Adminable.sol";
import "./interfaces/IStakingFeeCalculator.sol";
import "./interfaces/IConvertingFeeCalculator.sol";

contract FeeCalculator is IStakingFeeCalculator, IConvertingFeeCalculator {
    uint16 public constant FEE_PERCENTAGE_BASE = 10000;
    uint16 public constant GMXKEY_CONVERTING_FEE_PERCENTAGE = 50; //0.5%
    uint16 public constant DEFAULT_CONVERTING_FEE_PERCENTAGE = 250; //2.5%
    uint16 public constant DEFAULT_STAKING_FEE_PERCENTAGE = 500; //5%

    address public immutable gmxKey;
    address public immutable esGmxKey;
    address public immutable mpKey;

    constructor(address _gmxKey, address _esGmxKey, address _mpKey) {
        require(_gmxKey != address(0), "Converter: gmxKey is the zero address");
        require(_esGmxKey != address(0), "Converter: esGmxKey is the zero address");
        require(_mpKey != address(0), "Converter: mpKey is the zero address");

        gmxKey = _gmxKey;
        esGmxKey = _esGmxKey;
        mpKey = _mpKey;
    }

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
        address convertingToken
    ) public view returns (uint256) {
        if (convertingToken == gmxKey) {
            return amount * GMXKEY_CONVERTING_FEE_PERCENTAGE / FEE_PERCENTAGE_BASE;
        } else {
            return amount * DEFAULT_CONVERTING_FEE_PERCENTAGE / FEE_PERCENTAGE_BASE;
        }
    }
}
