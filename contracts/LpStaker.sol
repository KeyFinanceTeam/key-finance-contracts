// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./interfaces/ILpStaker.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/uniswap/INonfungiblePositionManager.sol";
import "./common/Pausable.sol";
import "./common/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract LpStaker is ILpStaker, ReentrancyGuard, Pausable, IERC721Receiver {
    using SafeERC20 for IERC20;

    address immutable public uniswapPositionManager;
    address immutable public uniswapV3Staker;
    address immutable public pool;
    address immutable public token0;
    address immutable public token1;
    address immutable public rewardToken;

    mapping(uint256 => address) public idToOwner;
    mapping(address => uint256[]) public tokensStaked;

    IUniswapV3Staker.IncentiveKey[5200] public incentiveKeys; // incentive will be registered once a week (max. 100 yrs)
    mapping(uint256 => StakedIndex) public stakedIndex;
    uint16 public currentIndex;
    uint128 public minLiquidity;
    mapping(uint256 => uint256) public reward;

    constructor(address _admin, address _uniswapPositionManager, address _uniswapV3Staker, address _pool, address _rewardToken) Pausable(_admin) {
        require(_uniswapPositionManager != address(0), "Staker: _uniswapPositionManager is the zero address");
        require(_uniswapV3Staker != address(0), "Staker: _uniswapV3Staker is the zero address");
        require(_pool != address(0), "Staker: _pool is the zero address");
        require(_rewardToken != address(0), "Staker: _rewardToken is the zero address");
        uniswapPositionManager = _uniswapPositionManager;
        uniswapV3Staker = _uniswapV3Staker;
        pool = _pool;
        rewardToken = _rewardToken;
        token0 = IUniswapV3Pool(_pool).token0();
        require(token0 != address(0), "Staker: token0 is the zero address");
        token1 = IUniswapV3Pool(_pool).token1();
        require(token1 != address(0), "Staker: token1 is the zero address");
        currentIndex = type(uint16).max;
    }

    function setMinLiquidity(uint128 _minLiquidity) external onlyAdmin {
        minLiquidity = _minLiquidity;
    }

    function setCurrentIncentiveKey(IUniswapV3Staker.IncentiveKey memory key) external onlyAdminOrOperator {
        require(key.startTime <= block.timestamp && key.endTime > block.timestamp, "Staker: not stakable incentive key");
        require(address(key.rewardToken) == rewardToken, "Staker: rewardToken is not matched");
        require(address(key.pool) == pool, "Staker: pool is not matched");

        (uint256 totalRewardUnclaimed,,) = IUniswapV3Staker(uniswapV3Staker).incentives(keccak256(abi.encode(key)));
        require(totalRewardUnclaimed > 0, "Staker: incentive key is not registered");
        
        uint16 _index = currentIndex;
        if (_index == type(uint16).max) _index = 0;
        else _index += 1;

        incentiveKeys[_index] = key;
        currentIndex = _index;
    }

    // below 2 functions are for unstaking multiple tokens when cannot withdraw & also stakes with any past keys are always unstakable

    function unstakeTokens(uint256[] memory tokenIds, uint16 keyCount) external nonReentrant {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _unstakeTokenWithPastIncentives(tokenIds[i], keyCount);
        }
    }

    function unstakeTokenOnce(uint256 tokenId) external nonReentrant {
        StakedIndex memory _stakedIndex = stakedIndex[tokenId];
        uint16 firstIndex = _stakedIndex.first;
        require(firstIndex < currentIndex, "Staker: already unstaked all past tokens");
        IUniswapV3Staker.IncentiveKey memory key = incentiveKeys[firstIndex];
        _unstakeTokenForKey(key, tokenId);
    }

    function extendStaking(uint256[] memory tokenIds) external nonReentrant whenNotPaused {
        IUniswapV3Staker.IncentiveKey memory key = _getCurrentIncentiveKey();
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            _stakeToken(key, tokenId);
        }
    }

    function extendStakingAndUnstakeTokens(uint256[] memory tokenIds) external nonReentrant whenNotPaused {
        IUniswapV3Staker.IncentiveKey memory key = _getCurrentIncentiveKey();
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            _stakeToken(key, tokenId);
            _unstakeTokenWithPastIncentives(tokenId, type(uint16).max);
        }
    }

    function depositAndStakeLpToken(uint256[] memory tokenIds) external nonReentrant whenNotPaused {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            // transfer token from msg.sender to this contract
            INonfungiblePositionManager(uniswapPositionManager).safeTransferFrom(msg.sender, address(this), tokenId);
        }
    }

    function unstakeAndWithdrawLpToken(uint256[] memory tokenIds) external nonReentrant {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            // validate requested by owner
            require(idToOwner[tokenId] == msg.sender, "Staker: msg.sender is not owner");

            // unstake from all the incentive keys
            _unstakeTokenWithAllIncentives(tokenId, type(uint16).max);
            uint256 _reward = reward[tokenId];
            delete reward[tokenId];
            if (_reward > 0) IERC20(rewardToken).safeTransfer(idToOwner[tokenId], _reward);

            // remove records for staking
            _deleteTokenFromStaked(msg.sender, tokenId);
            delete idToOwner[tokenId];

            delete stakedIndex[tokenId];

            // withdraw token from staker
            IUniswapV3Staker(uniswapV3Staker).withdrawToken(tokenId, msg.sender, "");

            emit UnstakedAndWithdrawn(msg.sender, tokenId);
        }
    }

    function claimAllReward(uint256[] memory tokenIds, uint16 keyCount) external nonReentrant whenNotPaused {
        IUniswapV3Staker.IncentiveKey memory key = _getCurrentIncentiveKey();
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(idToOwner[tokenId] == msg.sender, "Staker: msg.sender is not owner");
            _unstakeTokenWithAllIncentives(tokenId, keyCount);
            if (key.endTime > block.timestamp) {
                StakedIndex memory _stakedIndex = stakedIndex[tokenId];
                if (keyCount > _stakedIndex.last - _stakedIndex.first) {
                    _stakeToken(key, tokenId);
                }
            }
            uint256 _reward = reward[tokenId];
            reward[tokenId] = 0;
            if (_reward > 0) IERC20(rewardToken).safeTransfer(idToOwner[tokenId], _reward);
        }
    }

    function collectFee(uint256[] memory tokenIds) external nonReentrant whenNotPaused {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _collectFee(tokenIds[i]);
        }
    }

    function getNumberOfTokensStaked(address owner) external view returns (uint256) {
        return tokensStaked[owner].length;
    }

    function getTokenStaked(address owner, uint256 index) external view returns (uint256) {
        return tokensStaked[owner][index];
    }

    function getCurrentIncentiveKey() external view returns (IUniswapV3Staker.IncentiveKey memory) {
        return _getCurrentIncentiveKey();
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        require(msg.sender == uniswapPositionManager, "Staker: only uniswap v3 nft allowed");

        if (from != uniswapV3Staker) {
            require(operator == from || operator == address(this), "Staker: msg.sender is not owner of tokenId");

            (,,,,,,,uint128 liquidity,,,,) = INonfungiblePositionManager(uniswapPositionManager).positions(tokenId);
            require(liquidity >= minLiquidity, "Staker: liquidity is too small");
            
            // register token to owner & owner to token
            idToOwner[tokenId] = from;
            tokensStaked[from].push(tokenId);

            // set indices
            stakedIndex[tokenId] = StakedIndex(currentIndex, currentIndex);

            // deposit & stake token with current incentive key
            INonfungiblePositionManager(uniswapPositionManager).safeTransferFrom(address(this), uniswapV3Staker, tokenId, abi.encode(_getCurrentIncentiveKey()));

            emit DepositedAndStaked(operator, tokenId, currentIndex);
        }

        return this.onERC721Received.selector;
    }

    function _deleteTokenFromStaked(address owner, uint256 tokenId) internal {
        uint256[] storage staked = tokensStaked[owner];
        for (uint256 i = 0; i < staked.length; i++) {
            if (staked[i] == tokenId) {
                staked[i] = staked[staked.length - 1];
                staked.pop();
                break;
            }
        }
    }

    function _unstakeTokenWithAllIncentives(uint256 tokenId, uint16 keyCount) internal {
        uint16 exclusiveLastIndex = stakedIndex[tokenId].last + 1;
        _unstakeTokenWithExclusiveLastIndex(tokenId, keyCount, exclusiveLastIndex);
    }

    function _unstakeTokenWithPastIncentives(uint256 tokenId, uint16 keyCount) internal {
        uint16 exclusiveLastIndex = stakedIndex[tokenId].last + 1;
        if (currentIndex < exclusiveLastIndex) exclusiveLastIndex = currentIndex;
        _unstakeTokenWithExclusiveLastIndex(tokenId, keyCount, exclusiveLastIndex);
    }

    function _unstakeTokenWithExclusiveLastIndex(uint256 tokenId, uint16 keyCount, uint16 exclusiveLastIndex) internal {
        StakedIndex memory _stakedIndex = stakedIndex[tokenId];
        if (keyCount != type(uint16).max && exclusiveLastIndex - _stakedIndex.first > keyCount) {
            exclusiveLastIndex = _stakedIndex.first + keyCount;
        }
        for (uint256 i = _stakedIndex.first; i < exclusiveLastIndex; i++) {
            _unstakeTokenForKey(incentiveKeys[i], tokenId);
        }
    }

    function _unstakeTokenForKey(IUniswapV3Staker.IncentiveKey memory key, uint256 tokenId) internal {
        StakedIndex memory _stakedIndex = stakedIndex[tokenId];
        emit Unstaked(msg.sender, tokenId, _stakedIndex.first);
        if (_stakedIndex.first < _stakedIndex.last) stakedIndex[tokenId].first += 1;
        (,uint128 liquidity)= IUniswapV3Staker(uniswapV3Staker).stakes(tokenId, keccak256(abi.encode(key)));
        if (liquidity > 0) {
            IUniswapV3Staker(uniswapV3Staker).unstakeToken(key, tokenId);
            _claimReward(tokenId);
        }
    }

    function _stakeToken(IUniswapV3Staker.IncentiveKey memory key, uint256 tokenId) internal {
        IUniswapV3Staker(uniswapV3Staker).stakeToken(key, tokenId);
        stakedIndex[tokenId].last = currentIndex;
        emit Staked(msg.sender, tokenId, currentIndex);
    }

    function _claimReward(uint256 tokenId) internal {
        reward[tokenId] += IUniswapV3Staker(uniswapV3Staker).claimReward(IERC20Minimal(rewardToken), address(this), 0);
        emit RewardClaimed(tokenId);
    }

    function _collectFee(uint256 tokenId) internal {
        require(idToOwner[tokenId] == msg.sender, "Staker: msg.sender is not owner");

        // unstake from all the incentive keys
        _unstakeTokenWithAllIncentives(tokenId, type(uint16).max);

        // withdraw token from staker
        IUniswapV3Staker(uniswapV3Staker).withdrawToken(tokenId, address(this), "");

        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams(
            tokenId, 
            address(this),
            type(uint128).max,
            type(uint128).max
        );
        (uint256 amount0, uint256 amount1)= INonfungiblePositionManager(uniswapPositionManager).collect(params);
        if (amount0 > 0) IERC20(token0).safeTransfer(msg.sender, amount0);
        if (amount1 > 0) IERC20(token1).safeTransfer(msg.sender, amount1);

        // deposit & stake token with current incentive key
        INonfungiblePositionManager(uniswapPositionManager).safeTransferFrom(address(this), uniswapV3Staker, tokenId, abi.encode(_getCurrentIncentiveKey()));
        emit DepositedAndStaked(msg.sender, tokenId, currentIndex);

        // set indices
        stakedIndex[tokenId] = StakedIndex(currentIndex, currentIndex);

        emit FeeCollected(msg.sender, tokenId);
    }

    function _getCurrentIncentiveKey() internal view returns (IUniswapV3Staker.IncentiveKey memory) {
        return incentiveKeys[currentIndex];
    }

}