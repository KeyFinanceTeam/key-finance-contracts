// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

contract ConfigUserInitializable {
    address public config;

    constructor() {}

    function __ConfigUser_init(address _config) internal {
        require(_config != address(0), "ConfigUserInitializable: config is the zero address");
        config = _config;
    }
}