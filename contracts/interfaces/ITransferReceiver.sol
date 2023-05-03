// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./IRewardRouter.sol";
import "./IReserved.sol";

interface ITransferReceiver is IReserved {
    function initialize(
        address _admin,
        address _config,
        address _converter,
        IRewardRouter _rewardRouter,
        address _stakedGlp,
        address _rewards
    ) external;
    function rewardRouter() external view returns (IRewardRouter);
    function stakedGlpTracker() external view returns (address);
    function weth() external view returns (address);
    function esGmx() external view returns (address);
    function stakedGlp() external view returns (address);
    function converter() external view returns (address);
    function rewards() external view returns (address);
    function transferSender() external view returns (address);
    function transferSenderReserved() external view returns (address to, uint256 at);
    function newTransferReceiverReserved() external view returns (address to, uint256 at);
    function accepted() external view returns (bool);
    function isForMpKey() external view returns (bool);
    function reserveTransferSender(address _transferSender, uint256 _at) external;
    function setTransferSender() external;
    function reserveNewTransferReceiver(address _newTransferReceiver, uint256 _at) external;
    function claimAndUpdateReward(address feeTo) external;
    function signalTransfer(address to) external;
    function acceptTransfer(address sender, bool _isForMpKey) external;
    function version() external view returns (uint256);
    event TransferAccepted(address indexed sender);
    event SignalTransfer(address indexed from, address indexed to);
    event TokenWithdrawn(address token, address to, uint256 balance);
    event TransferSenderReserved(address transferSender, uint256 at);
    event NewTransferReceiverReserved(address indexed to, uint256 at);
}