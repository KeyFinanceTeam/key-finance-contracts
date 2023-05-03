// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

abstract contract Adminable {
    address public admin;
    address public candidate;

    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    event AdminCandidateRegistered(address indexed admin, address indexed candidate);

    constructor(address _admin) {
        require(_admin != address(0), "admin is the zero address");
        admin = _admin;
        emit AdminChanged(address(0), _admin);
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin");
        _;
    }

    function registerAdminCandidate(address _newAdmin) external onlyAdmin {
        require(_newAdmin != address(0), "new admin is the zero address");
        candidate = _newAdmin;
        emit AdminCandidateRegistered(admin, _newAdmin);
    }

    function confirmAdmin() external {
        require(msg.sender == candidate, "only candidate");
        emit AdminChanged(admin, candidate);
        admin = candidate;
        candidate = address(0);
    }
}