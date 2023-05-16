// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./IRewardRouter.sol";
import "./IReserved.sol";

interface ITransferSender {
    struct Lock {
        address account;
        uint256 startedAt;
    }

    struct Price {
        uint256 gmxKey;
        uint256 gmxKeyFee;
        uint256 esGmxKey;
        uint256 esGmxKeyFee;
        uint256 mpKey;
        uint256 mpKeyFee;
    }

    function gmx() external view returns (address);
    function esGmx() external view returns (address);
    function bnGmx() external view returns (address);
    function stakedGmxTracker() external view returns (address);
    function feeGmxTracker() external view returns (address);
    function stakedGlpTracker() external view returns (address);
    function feeGlpTracker() external view returns (address);
    function gmxVester() external view returns (address);
    function glpVester() external view returns (address);
    function GMXkey() external view returns (address);
    function esGMXkey() external view returns (address);
    function MPkey() external view returns (address);
    function converter() external view returns (address);
    function treasury() external view returns (address);
    function converterReserved() external view returns (address, uint256);
    function feeCalculator() external view returns (address);
    function feeCalculatorReserved() external view returns (address, uint256);
    function addressLock(address _receiver) external view returns (address, uint256);
    function addressPrice(address _receiver) external view returns (uint256, uint256, uint256, uint256, uint256, uint256);
    function unwrappedReceivers(uint256 index) external view returns (address);
    function unwrappedReceiverLength() external view returns (uint256);
    function isUnwrappedReceiver(address _receiver) external view returns (bool);
    function unwrappedAmount(address account, address token) external view returns (uint256);
    function setTreasury(address _treasury) external;
    function reserveConverter(address _converter, uint256 _at) external;
    function setConverter() external;
    function reserveFeeCalculator(address _feeCalculator, uint256 _at) external;
    function setFeeCalculator() external;
    function lock(address _receiver) external returns (Lock memory, Price memory);
    function unwrap(address _receiver) external;
    function changeAcceptableAccount(address _receiver, address account) external;
    function isUnlocked(address _receiver) external view returns (bool);


    event ConverterReserved(address to, uint256 at);
    event ConverterSet(address to, uint256 at);
    event FeeCalculatorReserved(address to, uint256 at);
    event FeeCalculatorSet(address to, uint256 at);
    event UnwrapLocked(address indexed account, address indexed receiver, Lock _lock, Price _price);
    event UnwrapCompleted(address indexed account, address indexed receiver, Price _price);
    event AcceptableAccountChanged(address indexed account, address indexed receiver, address indexed to);
}