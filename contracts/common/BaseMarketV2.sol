// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "../interfaces/IConfig.sol";
import "../interfaces/IMarketV2.sol";
import "../interfaces/IMarketFeeCalculator.sol";
import "./Adminable.sol";
import "./ConfigUser.sol";
import "../LinkedList.sol";
import "../interfaces/IReserved.sol";
import "../interfaces/IStakerV2.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

abstract contract BaseMarketV2 is IMarketV2, Adminable, ConfigUser, IReserved, ReentrancyGuard {
    using SortedArrays for SortedArrays.SortedArray;
    using LinkedList for LinkedList.List;

    uint256 public constant MIN_AMOUNT = 1e18;
    uint256 public constant TICK_TO_CURRENCY = 10000; // 1 tick = 0.0001 by unit of currency

    IERC20 public immutable currency;
    IERC20 public immutable token;
    address public treasury;
    address public immutable staker;
    address public feeCalculator;

    uint256 public immutable tick_size; // tick size of 10 means 0.001 (10 / 10000) by unit of currency
    uint256 public immutable max_price; // max_price of 20000 means 2.00 by unit of currency

    uint256 public orderId = 1;

    mapping(uint256 => OrderIndex) internal bidOrderIdToIndex;
    mapping(uint256 => OrderIndex) internal askOrderIdToIndex;

    mapping(uint256 => LinkedList.List) internal bidOrderMap;
    mapping(uint256 => LinkedList.List) internal askOrderMap;

    mapping(uint256 => Order) public orderIdMap; // order id => order

    SortedArrays.SortedArray internal bidPriceSorted; // descending
    SortedArrays.SortedArray internal askPriceSorted; // ascending

    mapping(uint256 => uint256) internal userOrdersOrderIdToIndex;
    mapping(address => LinkedList.List) internal userOrders;

    Reserved public feeCalculatorReserved;

    constructor(
        address _admin,
        address _config,
        IERC20 _currency,
        IERC20 _token,
        address _staker,
        address _feeCalculator,
        address _treasury,
        uint256 _tick_size,
        uint256 _max_price
    ) Adminable(_admin) ConfigUser(_config) {
        require(address(_currency) != address(0), "Market: currency is zero address");
        require(address(_token) != address(0), "Market: token is zero address");
        require(_staker != address(0), "Market: staker is zero address");
        require(_feeCalculator != address(0), "Market: feeCalculator is zero address");
        require(_treasury != address(0), "Market: treasury is zero address");
        require(_tick_size > 0, "Market: tick_to_unit is zero");
        require(_max_price > 0, "Market: max_price is zero");
        currency = _currency;
        token = _token;
        staker = _staker;
        feeCalculator = _feeCalculator;
        treasury = _treasury;
        tick_size = _tick_size;
        max_price = _max_price;
        bidPriceSorted.initialize(false);
        askPriceSorted.initialize(true);
    }

    function setTreasury(address _treasury) external onlyAdmin {
        require(_treasury != address(0), "Market: treasury is zero address");
        treasury = _treasury;
    }

    function reserveFeeCalculator(address _feeCalculator, uint256 _at) external onlyAdmin {
        require(_feeCalculator != address(0), "Market: feeCalculator is the zero address");
        require(_at >= IConfig(config).getUpgradeableAt(), "Market: at should be later");
        feeCalculatorReserved = Reserved(_feeCalculator, _at);

        emit MarketFeeCalculatorReserved(_feeCalculator, _at);
    }

    // Sets reserved FeeCalculator contract.
    function setFeeCalculator() external onlyAdmin {
        require(feeCalculatorReserved.at != 0 && feeCalculatorReserved.at <= block.timestamp, "Market: feeCalculator is not yet available");
        feeCalculator = feeCalculatorReserved.to;
    }

    function bid(uint256 _price, uint256 _amount, uint256 _loop) external nonReentrant {
        _executeOrder(_price, _amount, _loop, true);
    }

    function ask(uint256 _price, uint256 _amount, uint256 _loop) external nonReentrant {
        _executeOrder(_price, _amount, _loop, false);
    }

    function cancel(uint256 _orderId) external nonReentrant {
        _cancelOrder(_orderId);
    }

    function getUserOrdersLength(address _account) external view returns (uint256) {
        return userOrders[_account].size;
    }

    function getOrderBookInfo(bool _bidAsk, uint256 _count) external view returns (OrderBookInfo[] memory) {
        return _getOrderBookInfo(_bidAsk, _count);
    }

    function getOrdersLength(bool _bidAsk, uint256 _price) external view returns (uint256) {
        if (_bidAsk) return bidOrderMap[_price].size;
        else return askOrderMap[_price].size;
    }

    function getFirstOrderIdFromOrders(bool _bidAsk, uint256 _price) external view returns (uint id) {
        if (_bidAsk) {
            (id,,) = bidOrderMap[_price].get(bidOrderMap[_price].head);
        } else {
            (id,,) = askOrderMap[_price].get(askOrderMap[_price].head);
        }
    }

    function getOrders(bool _bidAsk, uint256 _price, uint256 _id, uint256 _count) external view returns (Order[] memory) {
        return _getOrders(_bidAsk ? bidOrderMap : askOrderMap, _bidAsk ? bidOrderIdToIndex : askOrderIdToIndex, _price, _id, _count);
    }

    function getPriceSortedLength(bool _bidAsk) external view returns (uint256) {
        if (_bidAsk) return bidPriceSorted.array.length;
        else return askPriceSorted.array.length;
    }

    function getPriceSorted(bool _bidAsk, uint256 _first, uint256 _last) external view returns (uint256[] memory) {
        return _getPrices(_bidAsk ? bidPriceSorted : askPriceSorted, _first, _last);
    }

    function getUserOrders(address _account, uint256 _count) external view returns (Order[] memory) {
        return getUserOrders(_account, 0, _count);
    }

    function getUserOrders(address _account, uint256 _id, uint256 _count) public view returns (Order[] memory) {
        LinkedList.List storage _orders = userOrders[_account];
        Order[] memory _ret = new Order[](_count);
        uint256 i = 0;
        for (uint256 j = _id != 0 ? userOrdersOrderIdToIndex[_id] : _orders.head; j != 0 && i < _count; j = _orders.nodes[j].next) {
            (uint256 _orderId,,) = _orders.get(j);
            _ret[i++] = orderIdMap[_orderId];
        }
        assembly {
            mstore(_ret, i)
        }
        return _ret;
    }

    function _matchOrders(LinkedList.List storage _orders, uint256 _amount, uint256 _loop, bool _bidAsk) internal returns (uint256, uint256) {
        for (uint256 j = _orders.head; j != 0;) {
            (uint256 _id,,uint256 next_j) = _orders.get(j);
            Order storage _o = orderIdMap[_id];
            uint256 _r = _getRemainingAmount(_o);
            if (_amount >= _r) {
                _takeOrder(_o, _r);
                _amount -= _r;
                _removeOrder(_o.maker, _orders, _bidAsk ? askOrderIdToIndex : bidOrderIdToIndex, j);
            } else {
                _takeOrder(_o, _amount);
                _amount = 0;
                break;
            }
            if (--_loop == 0) break;
            j = next_j;
        }
        return (_amount, _loop);
    }

    function _executeOrder(uint256 _price, uint256 _amount, uint256 _loop, bool _bidAsk) internal virtual {
        require(_amount >= MIN_AMOUNT, 'Market: order with too small amount');
        require(_price % tick_size == 0, 'Market: the price must be a multiple of the tick size.');

        SortedArrays.SortedArray storage priceSorted = _bidAsk ? askPriceSorted : bidPriceSorted;
        mapping(uint256 => LinkedList.List) storage orderMap = _bidAsk ? askOrderMap : bidOrderMap;
        uint256[] memory arr = priceSorted.array;

        for (uint256 i = 0; i < arr.length; i++) {
            if ((_bidAsk && arr[i] <= _price) || (!_bidAsk && arr[i] >= _price)) {
                LinkedList.List storage _orders = orderMap[arr[i]];
                (_amount, _loop) = _matchOrders(_orders, _amount, _loop, _bidAsk);
                if (_amount == 0) return;
                if (_loop == 0) return;
            } else {
                break;
            }
        }

        _makeOrder(_price, _amount, _bidAsk);
    }

    function _toCurrencyAmount(uint256 _amount, uint256 _price) internal virtual pure returns (uint256) {
        return _amount * _price / TICK_TO_CURRENCY;
    }

    function _makeOrder(uint256 _price, uint256 _amount, bool _bidAsk) internal virtual {
        // Choose the appropriate storage depending on whether it's a bid or ask order
        SortedArrays.SortedArray storage priceSorted = _bidAsk ? bidPriceSorted : askPriceSorted;
        mapping(uint256 => LinkedList.List) storage orderMap = _bidAsk ? bidOrderMap : askOrderMap;
        mapping(uint256 => OrderIndex) storage orderIdToIndex = _bidAsk ? bidOrderIdToIndex : askOrderIdToIndex;

        require(_price <= max_price, "Market: price is too high");
        priceSorted.insertIfNotExist(_price);
        LinkedList.List storage _orders = orderMap[_price];
        uint256 _orderId = orderId++;

        Order memory _newOrder = Order(_orderId, _price, _amount, 0, _bidAsk, msg.sender, block.timestamp);
        uint256 _location = _orders.insert(_orderId);
        orderIdMap[_orderId] = _newOrder;
        orderIdToIndex[_orderId] = OrderIndex(_bidAsk, _price, _location);

        // Transfer the appropriate amount of token depending on whether it's a bid or ask order
        IERC20 tokenToTransfer = _bidAsk ? currency : token;
        uint256 amountToTransfer = _bidAsk ? _toCurrencyAmount(_amount, _price) : _amount;
        uint256 _id = userOrders[msg.sender].insert(_orderId);
        userOrdersOrderIdToIndex[_orderId] = _id;
        tokenToTransfer.transferFrom(msg.sender, address(this), amountToTransfer);
        if (_bidAsk) {
            _afterMakeBidOrder(_orderId, amountToTransfer);
        } else {
            token.approve(staker, amountToTransfer);
            IStakerV2(staker).stakeAndLock(msg.sender, address(token), amountToTransfer);
        }

        emit MakeOrder(msg.sender, _orderId, address(token), address(currency), _newOrder.price, _newOrder.amount, _newOrder.bidAsk, block.timestamp);
    }

    function _afterMakeBidOrder(uint256 _orderId, uint256 _amountToTransfer) internal virtual {
        // Do nothing
    }

    function _cancelOrder(uint256 _orderId) internal {
        Order memory _order = orderIdMap[_orderId];
        bool bidAsk = _order.bidAsk;
        mapping(uint256 => LinkedList.List) storage orderMap = bidAsk ? bidOrderMap : askOrderMap;
        mapping(uint256 => OrderIndex) storage orderIdToIndex = bidAsk ? bidOrderIdToIndex : askOrderIdToIndex;

        OrderIndex memory _orderIndex = orderIdToIndex[_orderId];
        require(_order.maker == msg.sender, 'Market: not order maker');
        require(_order.id == _orderId, 'Market: invalid order id');
        _returnTokensToMaker(_order);
        _removeOrder(_order.maker, orderMap[_orderIndex.price], orderIdToIndex, _orderIndex.location);

        emit CancelOrder(msg.sender, _orderId, address(token), address(currency), _order.price, _order.amount, _getRemainingAmount(_order), _order.bidAsk, block.timestamp);
    }

    function _takeOrder(Order storage _order, uint256 _amount) internal {
        _transferTokensTaker(_order, _amount);
        _transferTokensMaker(_order, _amount);
        _order.filledAmount += _amount;

        emit TakeOrder(msg.sender, _order.id, _order.maker, address(token), address(currency), _order.price, _order.amount, _amount, _order.filledAmount, _order.bidAsk, block.timestamp);
    }

    function _transferTokensTaker(Order storage _order, uint256 _amount) internal virtual {
        IERC20 tokenToTransfer = _order.bidAsk ? currency : token;
        uint256 _amountToTransfer = _order.bidAsk ? _toCurrencyAmount(_amount, _order.price) : _amount;
        uint256 _fee = _order.bidAsk ?
            IMarketFeeCalculator(feeCalculator).calculateMarketSellerFee(msg.sender, address(currency), _amountToTransfer) :
            IMarketFeeCalculator(feeCalculator).calculateMarketBuyerFee(msg.sender, address(token), _amountToTransfer);
        if (_order.bidAsk) {
            _beforeTransferTokensToTaker(_order, _amountToTransfer);
        } else {
            if (_amountToTransfer > 0) IStakerV2(staker).unlockAndUnstake(_order.maker, address(token), _amountToTransfer);
        }
        tokenToTransfer.transfer(msg.sender, _amountToTransfer - _fee);
        tokenToTransfer.transfer(treasury, _fee);
    }

    function _beforeTransferTokensToTaker(Order memory _order, uint256 _amountToTransfer) internal virtual {
        // Do nothing
    }

    function _transferTokensMaker(Order storage _order, uint256 _amount) internal {
        IERC20 tokenToTransfer = _order.bidAsk ? token : currency;
        uint256 _amountToTransfer = _order.bidAsk ? _amount : _toCurrencyAmount(_amount, _order.price);
        uint256 _fee = _order.bidAsk ?
            IMarketFeeCalculator(feeCalculator).calculateMarketBuyerFee(_order.maker, address(token), _amountToTransfer) :
            IMarketFeeCalculator(feeCalculator).calculateMarketSellerFee(_order.maker, address(currency), _amountToTransfer);
        tokenToTransfer.transferFrom(msg.sender, _order.maker, _amountToTransfer - _fee);
        tokenToTransfer.transferFrom(msg.sender, treasury, _fee);
    }

    function _removeOrder(
        address _maker,
        LinkedList.List storage _orders,
        mapping(uint256 => OrderIndex) storage _orderIdToIndex,
        uint256 _location
    ) internal {
        (uint256 _orderId,,) = _orders.get(_location);
        _orders.remove(_location);

        if (_orders.head == 0) {
            Order memory _removed = orderIdMap[_orderId];
            SortedArrays.SortedArray storage priceSorted = _removed.bidAsk ? bidPriceSorted : askPriceSorted;
            priceSorted.removeIfExist(_removed.price);
        }

        userOrders[_maker].remove(userOrdersOrderIdToIndex[_orderId]);
        delete userOrdersOrderIdToIndex[_orderId];
        delete _orderIdToIndex[_orderId];
        delete orderIdMap[_orderId];
    }

    function _returnTokensToMaker(Order memory _order) internal virtual {
        if (_order.bidAsk) {
            uint256 _amountToTransfer = _toCurrencyAmount(_getRemainingAmount(_order), _order.price);
            _beforeReturningTransferTokensToMaker(_order, _amountToTransfer);
            currency.transfer(_order.maker, _amountToTransfer);
        } else {
            uint256 _amountToTransfer = _getRemainingAmount(_order);
            if (_amountToTransfer > 0) IStakerV2(staker).unlockAndUnstake(_order.maker, address(token), _amountToTransfer);
            token.transfer(_order.maker, _amountToTransfer);
        }
    }

    function _beforeReturningTransferTokensToMaker(Order memory _order, uint256 _amountToTransfer) internal virtual {
        // Do nothing
    }

    function _getOrderBookInfo(bool _bidAsk, uint256 count) internal view returns (OrderBookInfo[] memory orderBookInfo) {
        SortedArrays.SortedArray storage priceSorted = _bidAsk ? bidPriceSorted : askPriceSorted;
        mapping(uint256 => LinkedList.List) storage orderMap = _bidAsk ? bidOrderMap : askOrderMap;
        uint256[] memory arr = priceSorted.array;
        if (count > arr.length) count = arr.length;

        orderBookInfo = new OrderBookInfo[](count);
        for (uint256 i = 0; i < count; i++) {
            uint256 price = arr[i];
            LinkedList.List storage _orders = orderMap[price];
            uint256 amount = 0;

            for (uint256 j = _orders.head; j != 0; j = _orders.nodes[j].next) {
                (uint256 _id,,) = _orders.get(j);
                amount += _getRemainingAmount(orderIdMap[_id]);
            }
            orderBookInfo[i] = OrderBookInfo(price, amount, _bidAsk);
        }
    }

    function _getOrders(
        mapping(uint256 => LinkedList.List) storage orderMap,
        mapping(uint256 => OrderIndex) storage orderIdToIndex,
        uint256 _price,
        uint256 _id,
        uint256 _count
    ) internal view returns (Order[] memory _orders) {
        LinkedList.List storage orders = orderMap[_price];
        uint256 _location = orderIdToIndex[_id].location;
        _orders = new Order[](_count);
        uint256 i = 0;
        for (; i < _count;) {
            (_id,,_location) = orders.get(_location);
            _orders[i++] = orderIdMap[_id];
            if (_location == 0) break;
        }
        assembly {
            mstore(_orders, i)
        }
    }

    function _getPrices(
        SortedArrays.SortedArray storage priceSorted,
        uint256 _first,
        uint256 _last
    ) internal view returns (uint256[] memory _prices) {
        uint256[] memory prices = priceSorted.array;
        _prices = new uint256[](_last - _first);
        for (uint256 i = _first; i < _last; i++) {
            _prices[i - _first] = prices[i];
        }
    }

    function _getRemainingAmount(Order memory _order) internal pure returns (uint256) {
        return _order.amount - _order.filledAmount;
    }
}