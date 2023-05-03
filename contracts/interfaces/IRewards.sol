
// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

interface IRewards {
    function FEE_RATE_BASE() external view returns (uint16);
    function PRECISION() external view returns (uint128);
    function stakedGmxTracker() external view returns (address);
    function feeGmxTracker() external view returns (address);
    function esGmx() external view returns (address);
    function bnGmx() external view returns (address);
    function weth() external view returns (address);
    function GMXkey() external view returns (address);
    function MPkey() external view returns (address);
    function staker() external view returns (address);
    function converter() external view returns (address);
    function treasury() external view returns (address);
    function feeRate(address rewardToken) external view returns (uint16);
    function setFeeRate(address rewardToken, uint16 ratio) external;
    function claimReward(address account) external;
    function claimableReward(address account) external view returns (uint256, uint256, uint256, uint256);
    function initTransferReceiver() external;
    function updateRewards(address account, address stakingToken) external;
    function updateAllRewardsForTransferReceiverAndTransferFee(address receiver, address feeTo) external;
    event RewardClaimed(address indexed account, uint256 gmxKeyAmount, uint256 gmxKeyFee, uint256 mpKeyAmount, uint256 mpKeyFee, uint256 ethAmountFromGMXkey, uint256 ethFeeFromGMXkey, uint256 ethAmountFromMPkey, uint256 ethFeeFromMPkey);
    event ReceiverInitialized(address indexed receiver, uint256 stakedEsGmxAmount, uint256 stakedMpAmount);
    event RewardsCalculated(address indexed receiver, uint256 gmxKeyAmountToMint, uint256 mpKeyAmountToMint, uint256 wethAmountToTransfer);
}