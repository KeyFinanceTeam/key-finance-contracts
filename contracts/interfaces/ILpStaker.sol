// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./uniswap/IUniswapV3Staker.sol";

interface ILpStaker {

    struct StakedIndex {
        uint16 first;
        uint16 last;
    }

    function uniswapPositionManager() external view returns (address);
    function uniswapV3Staker() external view returns (address);
    function pool() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function rewardToken() external view returns (address);

    function idToOwner(uint256 tokenId) external view returns (address);
    function stakedIndex(uint256 tokenId) external view returns (uint16, uint16);
    function currentIndex() external view returns (uint16);
    function reward(uint256 tokenId) external view returns (uint256);
    function incentiveKeys(uint256 index) external view returns (
        IERC20Minimal rewardToken,
        IUniswapV3Pool pool,
        uint256 startTime,
        uint256 endTime,
        address refundee
    );

    function setCurrentIncentiveKey(IUniswapV3Staker.IncentiveKey memory key) external;
    function depositAndStakeLpToken(uint256[] memory tokenIds) external;
    function unstakeAndWithdrawLpToken(uint256[] memory tokenIds) external;
    function unstakeTokens(uint256[] memory tokenIds, uint16 keyCount) external;
    function unstakeTokenOnce(uint256 tokenId) external;
    function extendStaking(uint256[] memory tokenIds) external;
    function extendStakingAndUnstakeTokens(uint256[] memory tokenIds) external;
    function claimAllReward(uint256[] memory tokenIds, uint16 keyCount) external;
    function collectFee(uint256[] memory tokenIds) external;
    function getNumberOfTokensStaked(address owner) external view returns (uint256);
    function getTokenStaked(address owner, uint256 index) external view returns (uint256);
    function getCurrentIncentiveKey() external view returns (IUniswapV3Staker.IncentiveKey memory);

    event DepositedAndStaked(address indexed user, uint256 tokenId, uint256 index);
    event UnstakedAndWithdrawn(address indexed user, uint256 tokenId);
    event Unstaked(address indexed user, uint256 tokenId, uint256 index);
    event Staked(address indexed user, uint256 tokenId, uint256 index);
    event RewardClaimed(uint256 tokenId);
    event FeeCollected(address indexed user, uint256 tokenId);

}