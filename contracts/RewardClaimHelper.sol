// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./interfaces/ITransferReceiver.sol";
import "./interfaces/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract RewardClaimHelper is ReentrancyGuard {

    address public GMXkey;
    address public MPkey;

    constructor(address _GMXkey, address _MPkey) {
        GMXkey = _GMXkey;
        MPkey = _MPkey;
    }

    function claimAndUpdateRewardMulti(address[] memory transferReceivers, address feeTo) external nonReentrant {
        for (uint256 i = 0; i < transferReceivers.length; i++) {
            address transferReceiver = transferReceivers[i];
            ITransferReceiver(transferReceiver).claimAndUpdateReward(feeTo);
        }
    }
}