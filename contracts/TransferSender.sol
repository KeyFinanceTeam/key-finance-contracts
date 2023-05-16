// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./interfaces/ITransferSender.sol";
import "./interfaces/IConfig.sol";
import "./interfaces/IConverter.sol";
import "./interfaces/ITransferReceiverV2.sol";
import "./interfaces/ITransferSenderFeeCalculator.sol";
import "./interfaces/IVester.sol";
import "./interfaces/IRewardRouter.sol";
import "./interfaces/IRewardTracker.sol";
import "./interfaces/IERC20Burnable.sol";
import "./common/Adminable.sol";
import "./common/ConfigUser.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TransferSender is ITransferSender, Adminable, ConfigUser, IReserved, ReentrancyGuard {

    // constant
    uint256 constant public LOCK_VALID_TIME = 5 minutes;

    // external contracts
    address public immutable gmx;
    address public immutable esGmx;
    address public immutable bnGmx;
    address public immutable stakedGmxTracker;
    address public immutable bonusGmxTracker;
    address public immutable feeGmxTracker;
    address public immutable stakedGlpTracker;
    address public immutable feeGlpTracker;
    address public immutable gmxVester;
    address public immutable glpVester;

    // key protocol contracts & addresses
    address public immutable GMXkey;
    address public immutable esGMXkey;
    address public immutable MPkey;
    address public converter;
    address public treasury;
    address public feeCalculator;
    Reserved public feeCalculatorReserved;
    Reserved public converterReserved;

    mapping(address => Lock) public addressLock;
    mapping(address => Price) public addressPrice;

    address[] public unwrappedReceivers;
    mapping(address => bool) public isUnwrappedReceiver;
    mapping(address => mapping(address => uint256)) public unwrappedAmount;
    mapping(address => address) public unwrappedReceiverToUnwrapper;

    constructor(
        address _admin,
        address _config,
        address _GMXkey,
        address _esGMXkey,
        address _MPkey,
        address _converter,
        address _treasury,
        address _feeCalculator,
        IRewardRouter _rewardRouter
    ) Adminable(_admin) ConfigUser(_config) {
        require(_GMXkey != address(0), "TransferSender: GMXkey is the zero address");
        require(_esGMXkey != address(0), "TransferSender: esGMXkey is the zero address");
        require(_MPkey != address(0), "TransferSender: MPkey is the zero address");
        require(_converter != address(0), "TransferSender: converter is the zero address");
        require(_treasury != address(0), "TransferSender: treasury is the zero address");
        require(_feeCalculator != address(0), "TransferSender: feeCalculator is the zero address");
        GMXkey = _GMXkey;
        esGMXkey = _esGMXkey;
        MPkey = _MPkey;
        converter = _converter;
        treasury = _treasury;
        feeCalculator = _feeCalculator;

        gmx = _rewardRouter.gmx();
        esGmx = _rewardRouter.esGmx();
        bnGmx = _rewardRouter.bnGmx();
        stakedGmxTracker = _rewardRouter.stakedGmxTracker();
        bonusGmxTracker = _rewardRouter.bonusGmxTracker();
        feeGmxTracker = _rewardRouter.feeGmxTracker();
        stakedGlpTracker = _rewardRouter.stakedGlpTracker();
        feeGlpTracker = _rewardRouter.feeGlpTracker();
        gmxVester = _rewardRouter.gmxVester();
        glpVester = _rewardRouter.glpVester();
        require(gmx != address(0), "TransferSender: gmx is the zero address");
        require(esGmx != address(0), "TransferSender: esGmx is the zero address");
        require(bnGmx != address(0), "TransferSender: bnGmx is the zero address");
        require(stakedGmxTracker != address(0), "TransferSender: stakedGmxTracker is the zero address");
        require(bonusGmxTracker != address(0), "TransferSender: bonusGmxTracker is the zero address");
        require(feeGmxTracker != address(0), "TransferSender: feeGmxTracker is the zero address");
        require(stakedGlpTracker != address(0), "TransferSender: stakedGlpTracker is the zero address");
        require(feeGlpTracker != address(0), "TransferSender: feeGlpTracker is the zero address");
        require(gmxVester != address(0), "TransferSender: gmxVester is the zero address");
        require(glpVester != address(0), "TransferSender: glpVester is the zero address");
    }

    // Sets treasury address
    function setTreasury(address _treasury) external onlyAdmin {
        require(_treasury != address(0), "TransferSender: treasury is the zero address");
        treasury = _treasury;
    }

    function reserveConverter(address _converter, uint256 _at) external onlyAdmin {
        require(_converter != address(0), "TransferSender: converter is the zero address");
        require(_at >= IConfig(config).getUpgradeableAt(), "TransferSender: at should be later");
        converterReserved = Reserved(_converter, _at);
        emit ConverterReserved(_converter, _at);
    }

    // Sets reserved converter contract.
    function setConverter() external onlyAdmin {
        require(converterReserved.at != 0 && converterReserved.at <= block.timestamp, "TransferSender: converter is not yet available");
        converter = converterReserved.to;
        emit ConverterSet(converter, converterReserved.at);
    }

    function reserveFeeCalculator(address _feeCalculator, uint256 _at) external onlyAdmin {
        require(_feeCalculator != address(0), "TransferSender: feeCalculator is the zero address");
        require(_at >= IConfig(config).getUpgradeableAt(), "TransferSender: at should be later");
        feeCalculatorReserved = Reserved(_feeCalculator, _at);
        emit FeeCalculatorReserved(_feeCalculator, _at);
    }

    // Sets reserved FeeCalculator contract.
    function setFeeCalculator() external onlyAdmin {
        require(feeCalculatorReserved.at != 0 && feeCalculatorReserved.at <= block.timestamp, "TransferSender: feeCalculator is not yet available");
        feeCalculator = feeCalculatorReserved.to;
        emit FeeCalculatorSet(feeCalculator, feeCalculatorReserved.at);
    }

    function lock(address _receiver) external nonReentrant returns (Lock memory, Price memory) {
        require(IConverter(converter).isValidReceiver(_receiver), "TransferSender: invalid receiver");
        require(ITransferReceiverV2(_receiver).version() >= 1, "TransferSender: invalid receiver version");
        require(!isUnwrappedReceiver[_receiver], "TransferSender: already unwrapped");
        require(_isUnlocked(addressLock[_receiver]), "TransferSender: already locked");

        _validateReceiver(msg.sender);

        Price memory _price = _claimRewardAndGetPrice(_receiver);

        // lock
        Lock memory _lock = Lock(msg.sender, block.timestamp);

        addressLock[_receiver] = _lock;
        addressPrice[_receiver] = _price;

        emit UnwrapLocked(msg.sender, _receiver, _lock, _price);

        return (_lock, _price);
    }

    function unwrap(address _receiver) external nonReentrant {
        // lock check
        Lock memory _lock = addressLock[_receiver];
        require(msg.sender == _lock.account, "TransferSender: invalid account");
        require(!isUnwrappedReceiver[_receiver], "TransferSender: already unwrapped");
        require(!_isUnlocked(_lock), "TransferSender: unlocked. Lock the receiver first");

        Price memory _price = addressPrice[_receiver];

        _settleFeeAndSignalTransfer(_receiver, _price);

        emit UnwrapCompleted(msg.sender, _receiver, _price);
    }

    function claimAndUnwrap(address _receiver) external nonReentrant {
        require(IConverter(converter).isValidReceiver(_receiver), "TransferSender: invalid receiver");
        require(ITransferReceiverV2(_receiver).version() >= 1, "TransferSender: invalid receiver version");
        require(!isUnwrappedReceiver[_receiver], "TransferSender: already unwrapped");

        _unlock(_receiver);

        Price memory _price = _claimRewardAndGetPrice(_receiver);

        _settleFeeAndSignalTransfer(_receiver, _price);

        emit UnwrapCompleted(msg.sender, _receiver, _price);
    }

    function changeAcceptableAccount(address _receiver, address account) external nonReentrant {
        require(msg.sender == unwrappedReceiverToUnwrapper[_receiver], "TransferSender: invalid account");
        require(isUnwrappedReceiver[_receiver], "TransferSender: not unwrapped");

        ITransferReceiverV2(_receiver).signalTransfer(account);

        emit AcceptableAccountChanged(msg.sender, _receiver, account);
    }

    function unwrappedReceiverLength() external view returns (uint256) {
        return unwrappedReceivers.length;
    }

    function isUnlocked(address _receiver) external view returns (bool) {
        Lock memory _lock = addressLock[_receiver];
        return _isUnlocked(_lock);
    }

    function _claimRewardAndGetPrice(address _receiver) private returns (Price memory _price) {
        // reward claim
        ITransferReceiverV2(_receiver).claimAndUpdateRewardFromTransferSender(treasury);

        // balance check
        uint256 gmxAmount = IRewardTracker(stakedGmxTracker).depositBalances(_receiver, gmx);
        uint256 esGmxAmount = IRewardTracker(stakedGmxTracker).depositBalances(_receiver, esGmx);
        uint256 mpAmount = IRewardTracker(feeGmxTracker).depositBalances(_receiver, bnGmx);

        // price
        uint256 _gmxKeyFee = ITransferSenderFeeCalculator(feeCalculator).calculateTransferSenderFee(msg.sender, gmxAmount, GMXkey);
        uint256 _esGmxKeyFee = ITransferSenderFeeCalculator(feeCalculator).calculateTransferSenderFee(msg.sender, esGmxAmount, esGMXkey);
        uint256 _mpKeyFee = ITransferSenderFeeCalculator(feeCalculator).calculateTransferSenderFee(msg.sender, mpAmount, MPkey);
        _price = Price(gmxAmount, _gmxKeyFee, esGmxAmount, _esGmxKeyFee, mpAmount, _mpKeyFee);
    }

    function _settleFeeAndSignalTransfer(address _receiver, Price memory _price) private {
        // burn & transfer token
        if (_price.gmxKey > 0) _burnAndTransferFee(treasury, GMXkey, _price.gmxKey, _price.gmxKeyFee);
        if (_price.esGmxKey > 0) _burnAndTransferFee(treasury, esGMXkey, _price.esGmxKey, _price.esGmxKeyFee);
        if (_price.mpKey > 0) _burnAndTransferFee(treasury, MPkey, _price.mpKey, _price.mpKeyFee);

        unwrappedAmount[msg.sender][GMXkey] = _price.gmxKey;
        unwrappedAmount[msg.sender][esGMXkey] = _price.esGmxKey;
        unwrappedAmount[msg.sender][MPkey] = _price.mpKey;

        // signal transfer
        ITransferReceiverV2(_receiver).signalTransfer(msg.sender);

        _addToUnwrappedReceivers(_receiver);
        unwrappedReceiverToUnwrapper[_receiver] = msg.sender;
    }

    function _unlock(address _receiver) private {
        Lock storage _lock = addressLock[_receiver];
        _lock.account = address(0);
        _lock.startedAt = 0;
    }

    function _burnAndTransferFee(address to, address _token, uint256 amount, uint256 fee) private {
        // These calls are safe, because _token is based on BaseToken contract.
        IERC20Burnable(_token).transferFrom(msg.sender, address(this), amount + fee);
        IERC20Burnable(_token).burn(amount);
        IERC20Burnable(_token).transfer(to, fee);
    }

    function _addToUnwrappedReceivers(address _receiver) private {
        unwrappedReceivers.push(_receiver);
        isUnwrappedReceiver[_receiver] = true;
    }

    function _isUnlocked(Lock memory _lock) private view returns (bool) {
        return _lock.startedAt + LOCK_VALID_TIME < block.timestamp;
    }

    // https://github.com/gmx-io/gmx-contracts/blob/6a6a7fd7c387d0b6b159e2a11d65a9e08bd2c099/contracts/staking/RewardRouterV2.sol#L346
    function _validateReceiver(address _receiver) private view {
        require(IRewardTracker(stakedGmxTracker).averageStakedAmounts(_receiver) == 0, "TransferSender: stakedGmxTracker.averageStakedAmounts > 0");
        require(IRewardTracker(stakedGmxTracker).cumulativeRewards(_receiver) == 0, "TransferSender: stakedGmxTracker.cumulativeRewards > 0");

        require(IRewardTracker(bonusGmxTracker).averageStakedAmounts(_receiver) == 0, "TransferSender: bonusGmxTracker.averageStakedAmounts > 0");
        require(IRewardTracker(bonusGmxTracker).cumulativeRewards(_receiver) == 0, "TransferSender: bonusGmxTracker.cumulativeRewards > 0");

        require(IRewardTracker(feeGmxTracker).averageStakedAmounts(_receiver) == 0, "TransferSender: feeGmxTracker.averageStakedAmounts > 0");
        require(IRewardTracker(feeGmxTracker).cumulativeRewards(_receiver) == 0, "TransferSender: feeGmxTracker.cumulativeRewards > 0");

        require(IVester(gmxVester).transferredAverageStakedAmounts(_receiver) == 0, "TransferSender: gmxVester.transferredAverageStakedAmounts > 0");
        require(IVester(gmxVester).transferredCumulativeRewards(_receiver) == 0, "TransferSender: gmxVester.transferredCumulativeRewards > 0");

        require(IRewardTracker(stakedGlpTracker).averageStakedAmounts(_receiver) == 0, "TransferSender: stakedGlpTracker.averageStakedAmounts > 0");
        require(IRewardTracker(stakedGlpTracker).cumulativeRewards(_receiver) == 0, "TransferSender: stakedGlpTracker.cumulativeRewards > 0");

        require(IRewardTracker(feeGlpTracker).averageStakedAmounts(_receiver) == 0, "TransferSender: feeGlpTracker.averageStakedAmounts > 0");
        require(IRewardTracker(feeGlpTracker).cumulativeRewards(_receiver) == 0, "TransferSender: feeGlpTracker.cumulativeRewards > 0");

        require(IVester(glpVester).transferredAverageStakedAmounts(_receiver) == 0, "TransferSender: glpVester.transferredAverageStakedAmounts > 0");
        require(IVester(glpVester).transferredCumulativeRewards(_receiver) == 0, "TransferSender: glpVester.transferredCumulativeRewards > 0");

        require(IERC20(gmxVester).balanceOf(_receiver) == 0, "TransferSender: gmxVester.balance > 0");
        require(IERC20(glpVester).balanceOf(_receiver) == 0, "TransferSender: glpVester.balance > 0");
    }
}
