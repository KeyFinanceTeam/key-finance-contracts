// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./IRewardRouter.sol";

interface IConverter {
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
    function minGmxAmount() external view returns (uint128);
    function qualifiedRatio() external view returns (uint32);
    function isForMpKey(address sender) external view returns (bool);
    function setQualification(uint128 _minGmxAmount, uint32 _qualifiedRatio) external;
    function createTransferReceiver() external;
    function approveMpKeyConversion(address _receiver, bool _approved) external;
    function completeConversion() external;
    function completeConversionToMpKey(address sender) external;
    function isValidReceiver(address _receiver) external view returns (bool);
    event ReceiverRegistered(address indexed receiver, uint256 activeAt);
    event ReceiverCreated(address indexed account, address indexed receiver);
    event ConvertCompleted(address indexed account, address indexed receiver, uint256 gmxAmount, uint256 esGmxAmount, uint256 mpAmount);
    event ConvertForMpCompleted(address indexed account, address indexed receiver, uint256 amount);
    event ConvertingFeeCalculatorReserved(address to, uint256 at);

}