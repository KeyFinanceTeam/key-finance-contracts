// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./common/BaseMarketV2.sol";
import "./interfaces/IRewardRouter.sol";
import "./interfaces/IRewardTracker.sol";
import "./interfaces/IWETH.sol";

contract MarketV2 is BaseMarketV2 {

    IERC20 public constant GMX = IERC20(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a); // use GMX token as currency
    uint256 public constant PRECISION = 1e36;

    address public immutable rewardRouter;
    address public immutable stakedGmxTracker;
    address public immutable feeGmxTracker;
    IERC20 public immutable weth;

    uint256 internal rewardsPerBidBalance;
    mapping(uint256 => uint256) internal lastRewardsPerBidBalance; // order id => last record for rewards

    constructor(
        address _admin,
        address _config,
        address _rewardRouter,
        IERC20 _token,
        address _staker,
        address _feeCalculator,
        address _treasury,
        uint256 _tick_size,
        uint256 _max_price
    ) BaseMarketV2(_admin, _config, GMX, _token, _staker, _feeCalculator, _treasury, _tick_size, _max_price) {
        require(_rewardRouter != address(0), "Market: rewardRouter is zero address");
        rewardRouter = _rewardRouter;
        stakedGmxTracker = IRewardRouter(_rewardRouter).stakedGmxTracker();
        feeGmxTracker = IRewardRouter(_rewardRouter).feeGmxTracker();
        weth = IERC20(IRewardRouter(_rewardRouter).weth());
     
        currency.approve(stakedGmxTracker, type(uint256).max);
    }

    function claimBidReward(uint256 _orderId) external nonReentrant {
        _updateBidRewards();
        _settleBidReward(orderIdMap[_orderId]);
    }

    function claimableBidReward(uint256 _orderId) external view returns (uint256) {
        Order memory order = orderIdMap[_orderId];
        require(order.bidAsk, "Market: not bid order");
        return _rewardAmountForOrderClaimable(order);
    }

    function _executeOrder(uint256 _price, uint256 _amount, uint256 _loop, bool _bidAsk) internal override {
        _updateBidRewards();
        super._executeOrder(_price, _amount, _loop, _bidAsk);
    }

    function _updateBidRewards() private {
        uint256 totalBidBalance = IRewardTracker(stakedGmxTracker).depositBalances(address(this), address(currency));
        if (totalBidBalance > 0) {
            uint256 rewardAmount = weth.balanceOf(address(this));
            IRewardRouter(rewardRouter).handleRewards(false, false, true, true, true, true, false);
            rewardAmount = weth.balanceOf(address(this)) - rewardAmount;
            if (rewardAmount > 0) {
                rewardsPerBidBalance += rewardAmount * PRECISION / totalBidBalance;
            }
        }
    }

    function _afterMakeBidOrder(uint256 _orderId, uint256 _amountToTransfer) internal override {
        lastRewardsPerBidBalance[_orderId] = rewardsPerBidBalance;
        if (_amountToTransfer > 0) IRewardRouter(rewardRouter).stakeGmx(_amountToTransfer);
    }

    function _beforeTransferTokensToTaker(Order memory _order, uint256 _amountToTransfer) internal override {
        _settleBidReward(_order);
        if (_amountToTransfer > 0) IRewardRouter(rewardRouter).unstakeGmx(_amountToTransfer);
    }

    function _beforeReturningTransferTokensToMaker(Order memory _order, uint256 _amountToTransfer) internal override {
        _updateBidRewards();
        _settleBidReward(_order);
        if (_amountToTransfer > 0) IRewardRouter(rewardRouter).unstakeGmx(_amountToTransfer);
    }

    function _settleBidReward(Order memory _order) private {
        uint256 _rewardAmount = _rewardAmountForOrder(_order);
        lastRewardsPerBidBalance[_order.id] = rewardsPerBidBalance;
        _transferAsETH(_order.maker, _rewardAmount);
    }

    function _transferAsETH(address to, uint256 amount) private {
        if (amount > 0) {
            IWETH(address(weth)).withdraw(amount);
            assembly {
                pop(call(30000, to, amount, 0, 0, 0, 0))
            }
        }
    }

    function _rewardAmountForOrder(Order memory _order) private view returns (uint256 amount) {
        uint256 currencyAmount = _toCurrencyAmount(_getRemainingAmount(_order), _order.price);
        amount = (rewardsPerBidBalance - lastRewardsPerBidBalance[_order.id]) * currencyAmount / PRECISION;
    }

    function _rewardAmountForOrderClaimable(Order memory _order) private view returns (uint256 amount) {
        uint256 currencyAmount = _toCurrencyAmount(_getRemainingAmount(_order), _order.price);
        uint256 rewardsAmount = IRewardTracker(feeGmxTracker).claimable(address(this));
        uint256 totalBidBalance = IRewardTracker(stakedGmxTracker).depositBalances(address(this), address(currency));
        amount = ((rewardsPerBidBalance - lastRewardsPerBidBalance[_order.id] + rewardsAmount * PRECISION / totalBidBalance) * currencyAmount) / PRECISION;
    }

    receive() external payable {
        require(msg.sender == address(weth), "Not weth");
    }
}