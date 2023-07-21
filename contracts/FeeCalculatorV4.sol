// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./FeeCalculatorV3.sol";
import "./interfaces/IBaseToken.sol";

contract FeeCalculatorV4 is FeeCalculatorV3, Adminable {

    address[] treasuries;
    uint256 public PRECISION = 1e9;

    constructor(address _admin, address _gmxKey, address _esGmxKey, address _mpKey, address[] memory _treasuries) FeeCalculatorV3(_gmxKey, _esGmxKey, _mpKey) Adminable(_admin){
        treasuries = _treasuries;
    }

    function calculateStakingFee(
        address, // account
        uint256 amount,
        address stakingToken,
        address // rewardToken
    ) public view override returns (uint256) {
        require(stakingToken == gmxKey || stakingToken == esGmxKey || stakingToken == mpKey, "Only Key Utility Tokens");
        uint256 _totalSupply = IBaseToken(stakingToken).totalSupply();
        uint256 _sum = 0;
        for (uint256 i = 0; i < treasuries.length; i++) {
            _sum += IBaseToken(stakingToken).balanceOf(treasuries[i]);
        }
        return amount * (_sum * PRECISION / _totalSupply) / PRECISION / 2;
    }

    function setTreasuries(address[] memory _treasuries) public onlyAdmin {
        treasuries = _treasuries;
    }

    function getTreasuryLength() public view returns (uint256) {
        return treasuries.length;
    }
}
