// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

contract ConfigUser {
    address public immutable config;

    constructor(address _config) {
        require(_config != address(0), "ConfigUser: config is the zero address");
        config = _config;
    }
}