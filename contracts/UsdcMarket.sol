// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./interfaces/IConfig.sol";
import "./interfaces/IMarket.sol";
import "./interfaces/IMarketFeeCalculator.sol";
import "./common/Adminable.sol";
import "./common/ConfigUser.sol";
import "./LinkedList.sol";
import "./interfaces/IReserved.sol";

contract UsdcMarket is IMarket, Adminable, ConfigUser, IReserved {
    using SortedArrays for SortedArrays.SortedArray;
    using LinkedList for LinkedList.List;

    IERC20 public constant currency = IERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831); // use USDC token as currency
    uint256 public constant MIN_AMOUNT = 1e18;
    uint256 public constant TICK_TO_CURRENCY = 10000; // 1 tick = 0.0001 by unit of currency
    uint256 public constant DENOMINATOR_FOR_6_DECIMALS = 1e12;

    IERC20 public token;
    address public treasury;
    address public feeCalculator;

    uint256 public tick_size; // tick size of 10 means 0.001 (10 / 10000) by unit of currency
    uint256 public max_price; // max_price of 20000 means 2.00 by unit of currency

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
        IERC20 _token,
        address _feeCalculator,
        address _treasury,
        uint256 _tick_size,
        uint256 _max_price
    ) Adminable(_admin) ConfigUser(_config) {
        require(address(_token) != address(0), "Market: token is zero address");
        require(_feeCalculator != address(0), "Market: feeCalculator is zero address");
        require(_treasury != address(0), "Market: treasury is zero address");
        require(_tick_size > 0, "Market: tick_to_unit is zero");
        require(_max_price > 0, "Market: max_price is zero");
        token = _token;
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

    function bid(uint256 _price, uint256 _amount, uint256 _loop) external {
        _executeOrder(_price, _amount, _loop, true);
    }

    function ask(uint256 _price, uint256 _amount, uint256 _loop) external {
        _executeOrder(_price, _amount, _loop, false);
    }

    function cancel(uint256 _orderId) external {
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

    function _matchOrders(LinkedList.List storage _orders, uint256 _amount, uint256 _loop, bool _bidAsk) private returns (uint256, uint256) {
        for (uint256 j = _orders.head; j != 0; j = _orders.nodes[j].next) {
            (uint256 _id,,) = _orders.get(j);
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
        }
        return (_amount, _loop);
    }

    function _executeOrder(uint256 _price, uint256 _amount, uint256 _loop, bool _bidAsk) private {
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

    function _makeOrder(uint256 _price, uint256 _amount, bool _bidAsk) private {
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
        uint256 amountToTransfer = _bidAsk ? _amount * _price / TICK_TO_CURRENCY / DENOMINATOR_FOR_6_DECIMALS : _amount;
        tokenToTransfer.transferFrom(msg.sender, address(this), amountToTransfer);
        uint256 _id = userOrders[msg.sender].insert(_orderId);
        userOrdersOrderIdToIndex[_orderId] = _id;

        emit MakeOrder(msg.sender, _orderId, address(token), address(currency), _newOrder.price, _newOrder.amount, _newOrder.bidAsk, block.timestamp);
    }

    function _cancelOrder(uint256 _orderId) private {
        Order memory _order = orderIdMap[_orderId];
        bool bidAsk = _order.bidAsk;
        mapping(uint256 => LinkedList.List) storage orderMap = bidAsk ? bidOrderMap : askOrderMap;
        mapping(uint256 => OrderIndex) storage orderIdToIndex = bidAsk ? bidOrderIdToIndex : askOrderIdToIndex;

        OrderIndex memory _orderIndex = orderIdToIndex[_orderId];
        require(_order.maker == msg.sender, 'Market: not order maker');
        require(_order.id == _orderId, 'Market: invalid order id');
        _returnTokensToMaker(_order);
        _removeOrder(_order.maker, orderMap[_orderIndex.price], orderIdToIndex, _orderIndex.location);

        emit CancelOrder(msg.sender, _orderId, address(token), address(currency), _order.price, _order.amount, _order.bidAsk, block.timestamp);
    }

    function _takeOrder(Order storage _order, uint256 _amount) private {
        _transferTokensTaker(_order, msg.sender, _amount);
        _transferTokensMaker(_order, _amount);
        _order.filledAmount += _amount;

        emit TakeOrder(msg.sender, _order.id, _order.maker, address(token), address(currency), _order.price, _order.amount, _order.filledAmount, _order.bidAsk, block.timestamp);
    }

    function _transferTokensMaker(Order storage _order, uint256 _amount) private {
        IERC20 tokenToTransfer = _order.bidAsk ? token : currency;
        uint256 _amountToTransfer = _order.bidAsk ? _amount : _amount * _order.price / TICK_TO_CURRENCY / DENOMINATOR_FOR_6_DECIMALS;
        uint256 _fee = _order.bidAsk ?
        IMarketFeeCalculator(feeCalculator).calculateMarketBuyerFee(_order.maker, address(token), _amountToTransfer) :
        IMarketFeeCalculator(feeCalculator).calculateMarketSellerFee(_order.maker, address(currency), _amountToTransfer);
        tokenToTransfer.transferFrom(msg.sender, _order.maker, _amountToTransfer - _fee);
        tokenToTransfer.transferFrom(msg.sender, treasury, _fee);
    }

    function _transferTokensTaker(Order storage _order, address _taker, uint256 _amount) private {
        IERC20 tokenToTransfer = _order.bidAsk ? currency : token;
        uint256 _amountToTransfer = _order.bidAsk ? _amount * _order.price / TICK_TO_CURRENCY / DENOMINATOR_FOR_6_DECIMALS : _amount;
        uint256 _fee = _order.bidAsk ?
        IMarketFeeCalculator(feeCalculator).calculateMarketSellerFee(_taker, address(currency), _amountToTransfer) :
        IMarketFeeCalculator(feeCalculator).calculateMarketBuyerFee(_taker, address(token), _amountToTransfer);
        tokenToTransfer.transfer(_taker, _amountToTransfer - _fee);
        tokenToTransfer.transfer(treasury, _fee);
    }

    function _removeOrder(
        address _maker,
        LinkedList.List storage _orders,
        mapping(uint256 => OrderIndex) storage _orderIdToIndex,
        uint256 _location
    ) private {
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

    function _returnTokensToMaker(Order memory _order) private {
        if (_order.bidAsk) {
            currency.transfer(_order.maker, _getRemainingAmount(_order) * _order.price / TICK_TO_CURRENCY / DENOMINATOR_FOR_6_DECIMALS);
        } else {
            token.transfer(_order.maker, _getRemainingAmount(_order));
        }
    }

    function _getOrderBookInfo(bool _bidAsk, uint256 count) private view returns (OrderBookInfo[] memory orderBookInfo) {
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
    ) private view returns (Order[] memory _orders) {
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
    ) private view returns (uint256[] memory _prices) {
        uint256[] memory prices = priceSorted.array;
        _prices = new uint256[](_last - _first);
        for (uint256 i = _first; i < _last; i++) {
            _prices[i - _first] = prices[i];
        }
    }

    function _getRemainingAmount(Order memory _order) private pure returns (uint256) {
        return _order.amount - _order.filledAmount;
    }
}