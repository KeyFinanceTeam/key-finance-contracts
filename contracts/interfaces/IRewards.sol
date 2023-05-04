
// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

interface IRewards {
    function FEE_PERCENTAGE_BASE() external view returns (uint16);
    function FEE_PERCENTAGE_MAX() external view returns (uint16);
    function FEE_TIER_LENGTH_MAX() external view returns (uint128);
    function PRECISION() external view returns (uint128);
    function PERIOD() external view returns (uint256);
    function stakedGmxTracker() external view returns (address);
    function feeGmxTracker() external view returns (address);
    function gmx() external view returns (address);
    function esGmx() external view returns (address);
    function bnGmx() external view returns (address);
    function weth() external view returns (address);
    function GMXkey() external view returns (address);
    function esGMXkey() external view returns (address);
    function MPkey() external view returns (address);
    function staker() external view returns (address);
    function converter() external view returns (address);
    function treasury() external view returns (address);
    function feeCalculator() external view returns (address);
    function rewardPerUnit(address stakingToken, address rewardToken, uint256 periodIndex) external view returns (uint256);
    function lastRewardPerUnit(address account, address stakingToken, address rewardToken, uint256 periodIndex) external view returns (uint256);
    function reward(address account, address stakingToken, address rewardToken) external view returns (uint256);
    function lastDepositBalancesForReceivers(address receiver, address token) external view returns (uint256);
    function cumulatedReward(address stakingToken, address rewardToken) external view returns (uint256);
    function feeTiers(address rewardToken, uint256 index) external view returns (uint256);
    function feePercentages(address rewardToken, uint256 index) external view returns (uint16);
    function feeLength(address rewardToken) external view returns (uint256);
    function lastUpdatedAt(address receiver) external view returns (uint256);
    function currentPeriodIndex() external view returns (uint256);
    function maxPeriodsToUpdateRewards() external view returns (uint256);
    function feeCalculatorReserved() external view returns (address, uint256);
    function setTreasury(address _treasury) external;
    function setConverter(address _converter) external;
    function reserveFeeCalculator(address _feeCalculator, uint256 _at) external;
    function setFeeCalculator() external;
    function setFeeTiersAndPercentages(address _rewardToken, uint256[] memory _feeTiers, uint16[] memory _feePercentages) external;
    function setMaxPeriodsToUpdateRewards(uint256 _maxPeriodsToUpdateRewards) external;
    function claimRewardWithIndices(address account, uint256[] memory periodIndices) external;
    function claimRewardWithCount(address account, uint256 count) external;
    function claimableRewardWithIndices(address account, uint256[] memory periodIndices) external view returns(uint256 esGMXkeyRewardByGMXkey, uint256 esGMXkeyRewardByEsGMXkey, uint256 mpkeyRewardByGMXkey, uint256 mpkeyRewardByEsGMXkey, uint256 wethRewardByGMXkey, uint256 wethRewardByEsGMXkey, uint256 wethRewardByMPkey);
    function claimableRewardWithCount(address account, uint256 count) external view returns (uint256 esGMXkeyRewardByGMXkey, uint256 esGMXkeyRewardByEsGMXkey, uint256 mpkeyRewardByGMXkey, uint256 mpkeyRewardByEsGMXkey, uint256 wethRewardByGMXkey, uint256 wethRewardByEsGMXkey, uint256 wethRewardByMPkey);
    function initTransferReceiver() external;
    function updateAllRewardsForTransferReceiverAndTransferFee(address feeTo) external;
    event RewardClaimed(
        address indexed account,
        uint256 esGMXKeyAmountByGMXkey, uint256 esGMXKeyFeeByGMXkey, uint256 mpKeyAmountByGMXKey, uint256 mpKeyFeeByGMXkey,
        uint256 esGmxKeyAmountByEsGMXkey, uint256 esGmxKeyFeeByEsGMXkey, uint256 mpKeyAmountByEsGMXkey, uint256 mpKeyFeeByEsGMXkey,
        uint256 ethAmountByGMXkey, uint256 ethFeeByGMXkey,
        uint256 ethAmountByEsGMXkey, uint256 ethFeeByEsGMXkey,
        uint256 ethAmountByMPkey, uint256 ethFeeByMPkey);
    event ReceiverInitialized(address indexed receiver, uint256 stakedGmxAmount, uint256 stakedEsGmxAmount, uint256 stakedMpAmount);
    event RewardsCalculated(address indexed receiver, uint256 esGmxKeyAmountToMint, uint256 mpKeyAmountToMint, uint256 wethAmountToTransfer);
    event FeeUpdated(address token, uint256[] newFeeTiers, uint16[] newFeePercentages);
    event StakingFeeCalculatorReserved(address to, uint256 at);
}