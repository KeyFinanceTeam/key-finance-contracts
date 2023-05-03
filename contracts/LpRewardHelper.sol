// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import './common/Math.sol';
import "./interfaces/ILpRewardHelper.sol";

contract LpRewardHelper is ILpRewardHelper {

    uint256 internal constant Q128 = 0x100000000000000000000000000000000;

    IUniswapV3Staker public immutable uniswapV3Staker;
    INonfungiblePositionManager public immutable nonfungiblePositionManager;

    constructor(IUniswapV3Staker _uniswapV3Staker, INonfungiblePositionManager _nonfungiblePositionManager) {
        require(address(_uniswapV3Staker) != address(0), "zero address");
        require(address(_nonfungiblePositionManager) != address(0), "zero address");
        uniswapV3Staker = _uniswapV3Staker;
        nonfungiblePositionManager = _nonfungiblePositionManager;
    }

    function claimableReward(ILpStaker lpStaker, uint256 tokenId) public view returns (uint256 reward) {
        reward += lpStaker.reward(tokenId);
        (uint16 first, uint16 last) = lpStaker.stakedIndex(tokenId);
        for (uint16 i = first; i <= last; i++) {
            (IERC20Minimal rewardToken, IUniswapV3Pool pool, uint256 startTime, uint256 endTime, address refundee) = lpStaker.incentiveKeys(i);
            IUniswapV3Staker.IncentiveKey memory key = IUniswapV3Staker.IncentiveKey(rewardToken, pool, startTime, endTime, refundee);
            try uniswapV3Staker.getRewardInfo(key, tokenId) returns (uint256 _reward, uint160) {
                reward += _reward;
            } catch {}
        }
    }

    function claimableRewards(ILpStaker lpStaker, uint256[] memory tokenIds) external view returns (uint256 reward) {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            reward += claimableReward(lpStaker, tokenIds[i]);
        }
    }

    function collectibleFee(ILpStaker lpStaker, uint256 tokenId) external view returns (uint256 tokensOwed0, uint256 tokensOwed1) {
        address pool = lpStaker.pool();
        (tokensOwed0, tokensOwed1) = _collectibleFee(pool, tokenId);
    }

    function collectibleFees(ILpStaker lpStaker, uint256[] memory tokenIds) external view returns (uint256 tokensOwed0, uint256 tokensOwed1) {
        address pool = lpStaker.pool();
        for (uint256 i = 0; i < tokenIds.length; i++) {
            (uint256 _tokensOwed0, uint256 _tokensOwed1) = _collectibleFee(pool, tokenIds[i]);
            tokensOwed0 += _tokensOwed0;
            tokensOwed1 += _tokensOwed1;
        }
    }

    function _collectibleFee(address pool, uint256 tokenId) internal view returns (uint256 tokensOwed0, uint256 tokensOwed1) {
        (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 prevFeeGrowthInside0LastX128, uint256 prevFeeGrowthInside1LastX128, , ) = 
            INonfungiblePositionManager(nonfungiblePositionManager).positions(tokenId);

        if (liquidity > 0) {
            (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) =
                IUniswapV3Pool(pool).positions(computePositionKey(address(nonfungiblePositionManager), tickLower, tickUpper));

            tokensOwed0 = 
                Math.mulDiv(
                    feeGrowthInside0LastX128 - prevFeeGrowthInside0LastX128,
                    liquidity,
                    Q128
                );
            tokensOwed1 = 
                Math.mulDiv(
                    feeGrowthInside1LastX128 - prevFeeGrowthInside1LastX128,
                    liquidity,
                    Q128
                );
        }
    }

    function computePositionKey(
        address owner,
        int24 tickLower,
        int24 tickUpper
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner, tickLower, tickUpper));
    }

}