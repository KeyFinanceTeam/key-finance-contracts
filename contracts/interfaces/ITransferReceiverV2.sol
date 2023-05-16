// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./ITransferReceiver.sol";

interface ITransferReceiverV2 is ITransferReceiver {
    function claimAndUpdateRewardFromTransferSender(address feeTo) external;
    function defaultTransferSender() external view returns (address);
}
