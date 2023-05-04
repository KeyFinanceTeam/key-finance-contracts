// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

abstract contract AdminableInitializable {
    address public admin;
    address public candidate;

    event AdminUpdated(address indexed previousAdmin, address indexed newAdmin);
    event AdminCandidateRegistered(address indexed admin, address indexed candidate);

    constructor() {}

    function __Adminable_init(address _admin) internal {
        require(_admin != address(0), "admin is the zero address");
        admin = _admin;
        emit AdminUpdated(address(0), _admin);
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
        emit AdminUpdated(admin, candidate);
        admin = candidate;
        candidate = address(0);
    }

    uint256[64] private __gap;
}