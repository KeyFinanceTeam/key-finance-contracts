// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./IRewardRouter.sol";

interface IConverter {
    function gmx() external view returns (address);
    function esGmx() external view returns (address);
    function bnGmx() external view returns (address);
    function rewardRouter() external view returns (IRewardRouter);
    function stakedGmxTracker() external view returns (address);
    function feeGmxTracker() external view returns (address);
    function stakedGlp() external view returns (address);
    function GMXkey() external view returns (address);
    function esGMXkey() external view returns (address);
    function MPkey() external view returns (address);
    function rewards() external view returns (address);
    function treasury() external view returns (address);
    function operator() external view returns (address);
    function transferReceiver() external view returns (address);
    function feeCalculator() external view returns (address);
    function receivers(address _account) external view returns (address);
    function minGmxAmount() external view returns (uint128);
    function qualifiedRatio() external view returns (uint32);
    function isForMpKey(address sender) external view returns (bool);
    function registeredReceivers(uint256 index) external view returns (address);
    function registeredReceiversLength() external view returns (uint256);
    function isValidReceiver(address _receiver) external view returns (bool);
    function convertedAmount(address account, address token) external view returns (uint256);
    function feeCalculatorReserved() external view returns (address, uint256);
    function setTransferReceiver(address _transferReceiver) external;
    function setQualification(uint128 _minGmxAmount, uint32 _qualifiedRatio) external;
    function createTransferReceiver() external;
    function approveMpKeyConversion(address _receiver, bool _approved) external;
    function completeConversion() external;
    function completeConversionToMpKey(address sender) external;
    event ReceiverRegistered(address indexed receiver, uint256 activeAt);
    event ReceiverCreated(address indexed account, address indexed receiver);
    event ConvertCompleted(address indexed account, address indexed receiver, uint256 gmxAmount, uint256 esGmxAmount, uint256 mpAmount);
    event ConvertForMpCompleted(address indexed account, address indexed receiver, uint256 amount);
    event ConvertingFeeCalculatorReserved(address to, uint256 at);

}