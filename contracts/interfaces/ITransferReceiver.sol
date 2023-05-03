// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./IRewardRouter.sol";
import "./IReserved.sol";

interface ITransferReceiver is IReserved {
    function rewardRouter() external view returns (IRewardRouter);
    function stakedGlpTracker() external view returns (address);
    function weth() external view returns (address);
    function esGmx() external view returns (address);
    function stakedGlp() external view returns (address);
    function GMXkey() external view returns (address);
    function MPkey() external view returns (address);
    function converter() external view returns (address);
    function rewards() external view returns (address);
    function signalTransferReserved() external view returns (address, uint256);
    function accepted() external view returns (bool);
    function isForMpKey() external view returns (bool);
    function claimAndUpdateReward(address feeTo) external;
    function acceptTransfer(address sender, bool _isForMpKey) external;
    function reserveSignalTransfer(address to, uint256 at) external;
    function signalTransfer() external;
    event TransferAccepted(address indexed sender);
}