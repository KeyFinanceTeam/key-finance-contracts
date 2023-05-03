// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./IERC20.sol";

interface IBaseToken is IERC20 {
    function decimals() external view returns (uint8);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function setMinter(address _minter) external;
    function removeMinter(address _minter) external;
    function isMinter(address _account) external view returns (bool);
    function burn(uint256 _amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event MinterSet(address indexed minter);
    event MinterRemoved(address indexed minter);
}