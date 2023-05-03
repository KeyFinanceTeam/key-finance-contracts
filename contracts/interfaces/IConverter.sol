// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./IRewardRouter.sol";

interface IConverter {
    function FEE_RATE_BASE() external pure returns (uint16);
    function esGmx() external view returns (address);
    function rewardRouter() external view returns (IRewardRouter);
    function stakedGmxTracker() external view returns (address);
    function feeGmxTracker() external view returns (address);
    function stakedGlp() external view returns (address);
    function GMXkey() external view returns (address);
    function MPkey() external view returns (address);
    function treasury() external view returns (address);
    function rewards() external view returns (address);
    function receivers(address _account) external view returns (address);
    function feeRate(address _token) external view returns (uint16);
    function minGmxAmount() external view returns (uint128);
    function qualifiedRatio() external view returns (uint32);
    function isForMpKey(address sender) external view returns (bool);
    function receiverActiveAt(address _receiver) external view returns (uint256);
    function registerReceiver(address newReceiver, uint256 activeAt) external;
    function setFeeRate(address _token, uint16 _feeRate) external;
    function setQualification(uint128 _minGmxAmount, uint32 _qualifiedRatio) external;
    function createTransferReceiver() external;
    function approveMpKeyConversion(bool _approved) external;
    function completeConversion() external;
    function completeConversionToMpKey(address sender) external;
    function isActiveReceiver(address _receiver) external view returns (bool);
    event ReceiverRegistered(address indexed receiver, uint256 activeAt);
    event ReceiverCreated(address indexed account, address indexed receiver);
    event ConvertCompleted(address indexed account, address indexed receiver, uint256 gmxAmount, uint256 mpAmount);
    event ConvertForMpCompleted(address indexed account, address indexed receiver, uint256 amount);
}