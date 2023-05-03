// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Adminable.sol";

abstract contract OperatorAdminable is Adminable {
    mapping(address => bool) private _operators;

    event OperatorAdded(address indexed operator);
    event OperatorRemoved(address indexed operator);

    modifier onlyAdminOrOperator() {
        require(isAdmin(msg.sender) || isOperator(msg.sender), "OperatorAdminable: caller is not admin or operator");
        _;
    }

    function isOperator(address account) public view returns (bool) {
        return _operators[account];
    }

    function addOperator(address account) external onlyAdmin {
        require(account != address(0), "OperatorAdminable: operator is the zero address");
        require(!_operators[account], "OperatorAdminable: operator already added");
        _operators[account] = true;
        emit OperatorAdded(account);
    }

    function removeOperator(address account) external onlyAdmin {
        require(_operators[account], "OperatorAdminable: operator not found");
        _operators[account] = false;
        emit OperatorRemoved(account);
    }
}
