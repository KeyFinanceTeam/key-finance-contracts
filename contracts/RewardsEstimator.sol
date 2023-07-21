// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./common/Adminable.sol";
import "./interfaces/IStaker.sol";
import "./interfaces/IRewards.sol";
import "./interfaces/IConverter.sol";
import "./interfaces/IBaseToken.sol";
import "./interfaces/IRewardTracker.sol";

contract RewardsEstimator is Adminable {

    address public staker;
    address public rewards;
    address public converter;
    address public stakedGmxTracker;
    address public bonusGmxTracker;
    address public feeGmxTracker;
    address public gmx;
    address public esGmx;
    address public bnGmx;
    address public weth;
    address public gmxKey;
    address public esGmxKey;
    address public mpKey;

    uint256 public startingBlockNumber;

    constructor(address _admin, IRewardRouter _rewardRouter, address _staker, address _rewards, address _converter, address _gmxKey, address _esGmxKey, address _mpKey) Adminable(_admin) {
        require(address(_rewardRouter) != address(0), "RewardsEstimator: rewardRouter is the zero address");
        require(_staker != address(0), "RewardsEstimator: staker is the zero address");
        require(_rewards != address(0), "RewardsEstimator: rewards is the zero address");
        require(_converter != address(0), "RewardsEstimator: converter is the zero address");
        require(_gmxKey != address(0), "RewardsEstimator: gmxKey is the zero address");
        require(_esGmxKey != address(0), "RewardsEstimator: esGmxKey is the zero address");
        require(_mpKey != address(0), "RewardsEstimator: mpKey is the zero address");
        staker = _staker;
        rewards = _rewards;
        converter = _converter;
        stakedGmxTracker = _rewardRouter.stakedGmxTracker();
        bonusGmxTracker = _rewardRouter.bonusGmxTracker();
        feeGmxTracker = _rewardRouter.feeGmxTracker();
        gmx = _rewardRouter.gmx();
        esGmx = _rewardRouter.esGmx();
        bnGmx = _rewardRouter.bnGmx();
        weth = _rewardRouter.weth();
        gmxKey = _gmxKey;
        esGmxKey = _esGmxKey;
        mpKey = _mpKey;
    }

    function setStartingBlockNumber(uint256 blockNumber) external onlyAdmin {
        require(blockNumber > 0, "RewardsEstimator: blockNumber is zero");
        startingBlockNumber = blockNumber;
    }

    function totalClaimableRewardSinceCurrentPeriodStart(address token) public view returns (uint256 totalMP, uint256 totalETH) {
        if (token != mpKey) totalMP = IRewards(rewards).cumulatedReward(token, mpKey);
        totalETH = IRewards(rewards).cumulatedReward(token, weth);
        uint256 length = IConverter(converter).registeredReceiversLength();
        for (uint256 i = 0; i < length; i++) {
            address receiver = IConverter(converter).registeredReceivers(i);
            uint256 allTokenBal = _allTokenBal(receiver);
            if (allTokenBal == 0) continue;
            if (token != mpKey) totalMP += IRewardTracker(bonusGmxTracker).claimable(receiver) * _tokenBal(receiver, token) / _panGmxBal(receiver);
            totalETH += IRewardTracker(feeGmxTracker).claimable(receiver) * _tokenBal(receiver, token) / allTokenBal;
        }
    }

    function userShareSinceCurrentPeriodStart(address token, address account) public view returns (uint256) {
        uint256 latestUpdatedAt = IStaker(staker).latestUserSharesUpdatedAt(account, token);
        if (_isTsCurrentPeriod(latestUpdatedAt)) {
            return IStaker(staker).latestUserShares(account, token) + IStaker(staker).userBalance(account, token) * (block.timestamp - latestUpdatedAt);
        } else {
            return IStaker(staker).userBalance(account, token) * _timeSinceCurrentPeriodStart();
        }
    }

    function totalShareSinceCurrentPeriodStart(address token) public view returns (uint256) {
        uint256 latestUpdatedAt = IStaker(staker).latestTotalSharesUpdatedAt(token);
        if (_isTsCurrentPeriod(latestUpdatedAt)) {
            return IStaker(staker).latestTotalShares(token) + IStaker(staker).totalBalance(token) * (block.timestamp - latestUpdatedAt);
        } else {
            return IStaker(staker).totalBalance(token) * _timeSinceCurrentPeriodStart();
        }
    }

    function maxTotalShareSinceCurrentPeriodStart(address token) public view returns (uint256) {
        return IBaseToken(token).totalSupply() * _timeSinceCurrentPeriodStart();
    }

    function maxTotalShareForRestOfPeriod(address token) public view returns (uint256) {
        return IBaseToken(token).totalSupply() * _restOfPeriod();
    }

    /**
     * @dev This is accurate only when there has been no change in total supply since the last period.
     */
    function claimableRewardEstimated(address token, address account) external view returns (uint256 mp, uint256 eth) {
        (uint256 TM, uint256 TE) = totalClaimableRewardSinceCurrentPeriodStart(token);
        uint256 u = userShareSinceCurrentPeriodStart(token, account);
        uint256 tt = totalShareSinceCurrentPeriodStart(token);
        uint256 t = maxTotalShareSinceCurrentPeriodStart(token);
        uint256 r = maxTotalShareForRestOfPeriod(token);
        mp = TM * u / t * (r + t) / (r + tt);
        eth = TE * u / t * (r + t) / (r + tt);
    }

    function allTerms(address token, address account) external view returns (uint256 totalMP, uint256 totalETH, uint256 u, uint256 t, uint256 r, uint256 tt) {
        (totalMP, totalETH) = totalClaimableRewardSinceCurrentPeriodStart(token);
        u = userShareSinceCurrentPeriodStart(token, account);
        tt = totalShareSinceCurrentPeriodStart(token);
        t = maxTotalShareSinceCurrentPeriodStart(token);
        r = maxTotalShareForRestOfPeriod(token);
    }

    function _tokenBal(address receiver, address token) private view returns (uint256) {
        if (token != mpKey) return IRewardTracker(stakedGmxTracker).depositBalances(receiver, _depositToken(token));
        else return IRewardTracker(feeGmxTracker).depositBalances(receiver, _depositToken(token));
    }

    function _panGmxBal(address receiver) private view returns (uint256) {
        return IRewardTracker(stakedGmxTracker).stakedAmounts(receiver);
    }

    function _allTokenBal(address receiver) private view returns (uint256) {
        return IRewardTracker(feeGmxTracker).stakedAmounts(receiver);
    }

    function _depositToken(address token) private view returns (address) {
        if (token == gmxKey) return gmx;
        else if (token == esGmxKey) return esGmx;
        else return bnGmx;
    }

    function _isTsCurrentPeriod(uint256 ts) private view returns (bool) {
        return ts / 1 weeks == block.timestamp / 1 weeks;
    }

    function _timeSinceCurrentPeriodStart() private view returns (uint256) {
        return block.timestamp - block.timestamp / 1 weeks * 1 weeks;
    }

    function _restOfPeriod() private view returns (uint256) {
        return (block.timestamp / 1 weeks + 1) * 1 weeks - block.timestamp;
    }
}