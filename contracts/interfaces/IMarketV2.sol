// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./IERC20.sol";
import "../SortedArrays.sol";
import "../LinkedList.sol";

interface IMarketV2 {

    struct Order {
        uint256 id;
        uint256 price;
        uint256 amount;
        uint256 filledAmount;
        bool bidAsk; // 'bid' if true, otherwise 'ask'
        address maker;
        uint256 createdAt;
    }

    struct OrderBookInfo {
        uint256 price;
        uint256 amount;
        bool bidAsk;
    }

    struct OrderIndex {
        bool bidAsk;
        uint256 price;
        uint256 location;
    }

    function token() external view returns (IERC20);
    function currency() external view returns (IERC20);
    function orderId() external view returns (uint256);
    function bid(uint256 price, uint256 amount, uint256 loop) external;
    function ask(uint256 price, uint256 amount, uint256 loop) external;
    function cancel(uint256 orderId) external;
    function getOrderBookInfo(bool _bidAsk, uint256 _count) external view returns (OrderBookInfo[] memory);
    function getUserOrdersLength(address account) external view returns (uint256);
    function getUserOrders(address _account, uint256 _count) external view returns (Order[] memory);
    function getUserOrders(address _account, uint256 _firstOrderId, uint256 _count) external view returns (Order[] memory);

    event MakeOrder(address indexed account, uint256 indexed orderId, address token, address currency, uint256 price, uint256 amount, bool bidAsk, uint256 timestamp);
    event CancelOrder(address indexed account, uint256 indexed orderId, address token, address currency, uint256 price, uint256 totalAmount, uint256 amount, bool bidAsk, uint256 timestamp);
    event TakeOrder(address indexed account, uint256 indexed orderId, address indexed maker, address token, address currency, uint256 price, uint256 totalAmount, uint256 amount, uint256 filled, bool bidAsk, uint256 timestamp);
    event MarketFeeCalculatorReserved(address indexed feeCalculator, uint256 at);
}