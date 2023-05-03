// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./interfaces/IConfig.sol";
import "./common/Adminable.sol";

contract Config is IConfig, Adminable {

    uint256 public constant MIN_DELAY_TIME = 1 weeks;

    uint256 public upgradeDelayTime;

    constructor(address _admin) Adminable(_admin) {
        upgradeDelayTime = MIN_DELAY_TIME;
    }

    /**
     * @notice Set a delay period for upgrades. Upgrades can only be performed after the specified delay time has passed.
     * @param time The delay time in seconds
     */
    function setUpgradeDelayTime(uint256 time) external onlyAdmin {
        require(time >= MIN_DELAY_TIME, "Config: delay time too short");
        upgradeDelayTime = time;
    }

    /**
     * @notice Retrieve the timestamp, in seconds, when the upgrade is allowed to be performed.
     */
    function getUpgradeableAt() external view returns (uint256) {
        return block.timestamp + upgradeDelayTime;
    }
}