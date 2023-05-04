// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./AdminableInitializable.sol";

abstract contract PausableInitializable is AdminableInitializable {
    bool public paused;

    event Paused();
    event Resumed();

    constructor() {}

    function __Pausable_init(address _admin) internal {
        __Adminable_init(_admin);
    }

    modifier whenNotPaused() {
        require(!paused, "paused");
        _;
    }

    function pause() external onlyAdmin {
        paused = true;
        emit Paused();
    }

    function resume() external onlyAdmin {
        paused = false;
        emit Resumed();
    }

    uint256[64] private __gap;
}