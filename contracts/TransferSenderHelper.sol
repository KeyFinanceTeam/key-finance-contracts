// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./interfaces/IConverter.sol";
import "./interfaces/ITransferSender.sol";
import "./interfaces/IRewardTracker.sol";
import "./interfaces/IRewardRouter.sol";
import "./interfaces/IERC20.sol";
import "./TransferSender.sol";
import "./TransferSenderHelper.sol";

contract TransferSenderHelper {

    // external contracts
    address public immutable gmx;
    address public immutable esGmx;
    address public immutable bnGmx;
    IRewardRouter public immutable rewardRouter;
    address public immutable stakedGmxTracker;
    address public immutable feeGmxTracker;

    // key protocol contracts & addresses
    address public transferSender;
    address public converter;

    struct ReceiverInfo {
        address account;
        uint256 gmx;
        uint256 esGmx;
        uint256 mp;
        address lockAccount;
        uint256 lockStartedAt;
    }

    constructor(address _transferSender, address _converter, IRewardRouter _rewardRouter) {
        require(_transferSender != address(0), "TransferSenderHelper: transferSender is the zero address");
        require(_converter != address(0), "TransferSenderHelper: converter is the zero address");
        require(address(_rewardRouter) != address(0), "TransferSenderHelper: rewardRouter is the zero address");
        transferSender = _transferSender;
        converter = _converter;
        rewardRouter = _rewardRouter;
        gmx = _rewardRouter.gmx();
        esGmx = _rewardRouter.esGmx();
        bnGmx = _rewardRouter.bnGmx();
        stakedGmxTracker = _rewardRouter.stakedGmxTracker();
        require(stakedGmxTracker != address(0), "TransferSenderHelper: stakedGmxTracker is the zero address");
        feeGmxTracker = _rewardRouter.feeGmxTracker();
        require(feeGmxTracker != address(0), "TransferSenderHelper: feeGmxTracker is the zero address");
    }

    function receiverList(address userAddress) public view returns (ReceiverInfo[] memory)
    {
        IConverter _converter = IConverter(converter);
        ITransferSender _transferSender = ITransferSender(transferSender);

        uint256 receiverLength = _converter.registeredReceiversLength();
        uint256 unwrappedLength = _transferSender.unwrappedReceiverLength();

        ReceiverInfo[] memory receivers = new ReceiverInfo[](receiverLength - unwrappedLength + 1);
        uint256 j = 0;
        for (uint256 i = 0; i < receiverLength; i++) {
            address _transferReceiver = _converter.registeredReceivers(i);
            if (_converter.isValidReceiver(_transferReceiver)) {
                if (!_transferSender.isUnwrappedReceiver(_transferReceiver) ||
                    rewardRouter.pendingReceivers(_transferReceiver) == userAddress) {
                    (address _lockAccount, uint256 _lockStartedAt) = _transferSender.addressLock(_transferReceiver);
                    ReceiverInfo memory _receiverInfo = ReceiverInfo(
                        address(_transferReceiver),
                        IRewardTracker(stakedGmxTracker).depositBalances(_transferReceiver, gmx),
                        IRewardTracker(stakedGmxTracker).depositBalances(_transferReceiver, esGmx),
                        IRewardTracker(feeGmxTracker).depositBalances(_transferReceiver, bnGmx),
                        _lockAccount,
                        _lockStartedAt
                    );
                    receivers[j++] = _receiverInfo;
                }
            }
        }
        return receivers;
    }

    function receiverNotAccepted() public view returns (ReceiverInfo memory) {
        ITransferSender _transferSender = ITransferSender(transferSender);
        uint256 unwrappedLength = _transferSender.unwrappedReceiverLength();
        for (uint256 i = 0; i < unwrappedLength; i++) {
            address _receiver = _transferSender.unwrappedReceivers(i);
            address _account = rewardRouter.pendingReceivers(_receiver);
            if (_account != address(0) && _account == msg.sender) {
                ReceiverInfo memory _receiverInfo = ReceiverInfo(
                    address(_receiver),
                    IRewardTracker(stakedGmxTracker).depositBalances(_receiver, gmx),
                    IRewardTracker(stakedGmxTracker).depositBalances(_receiver, esGmx),
                    IRewardTracker(feeGmxTracker).depositBalances(_receiver, bnGmx),
                    _account,
                    0
                );
                return _receiverInfo;
            }
        }
        return ReceiverInfo(address(0), 0, 0, 0, address(0), 0);
    }
}