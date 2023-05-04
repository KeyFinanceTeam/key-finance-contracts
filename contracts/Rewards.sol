// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./interfaces/IConfig.sol";
import "./interfaces/IRewards.sol";
import "./interfaces/IStaker.sol";
import "./interfaces/IConverter.sol";
import "./interfaces/IRewardRouter.sol";
import "./interfaces/IRewardTracker.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/ITransferReceiver.sol";
import "./interfaces/IStakingFeeCalculator.sol";
import "./common/ConfigUser.sol";
import "./common/SafeERC20.sol";
import "./common/Math.sol";
import "./common/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Rewards
 * @author Key Finance
 * @notice
 * This contract enables users to request and claim rewards produced by staking GMXkey, esGMXkey, and MPkey.
 * Moreover, it encompasses a range of functions necessary for handling records associated with reward distribution.
 * A significant example is the updateAllRewardsForTransferReceiverAndTransferFee function, invoked from TransferReceiver contract.
 */
contract Rewards is IRewards, IReserved, ConfigUser, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // constants
    uint16 public constant FEE_PERCENTAGE_BASE = 10000;
    uint16 public constant FEE_PERCENTAGE_MAX = 2500;
    uint128 public constant FEE_TIER_LENGTH_MAX = 10;
    uint128 public constant PRECISION = 1e36;
    uint256 public constant PERIOD = 1 weeks;

    // external contracts
    address public immutable stakedGmxTracker;
    address public immutable feeGmxTracker;
    address public immutable gmx;
    address public immutable esGmx;
    address public immutable bnGmx;
    address public immutable weth;

    // key protocol contracts & addresses
    address public immutable GMXkey;
    address public immutable esGMXkey;
    address public immutable MPkey;
    address public immutable staker;
    address public converter;
    address public treasury;
    address public feeCalculator;

    // state variables
    mapping(address => mapping(address => mapping(uint256 => uint256))) public rewardPerUnit;
    mapping(address => mapping(address => mapping(address => mapping(uint256 => uint256)))) public lastRewardPerUnit;
    mapping(address => mapping(address => mapping(address => uint256))) public reward;
    mapping(address => mapping(address => uint256)) public lastDepositBalancesForReceivers;
    mapping(address => mapping(address => uint256)) public cumulatedReward;
    mapping(address => uint256[]) public feeTiers;
    mapping(address => uint16[]) public feePercentages;
    mapping(address => uint256) public lastUpdatedAt;
    uint256 public currentPeriodIndex;
    uint256 public maxPeriodsToUpdateRewards;
    Reserved public feeCalculatorReserved;

    constructor(address _admin, address _config, IRewardRouter _rewardRouter, address _GMXkey, address _esGMXkey, address _MPkey, address _staker, address _treasury, address _feeCalculator) Pausable(_admin) ConfigUser(_config) {
        require(address(_rewardRouter) != address(0), "Rewards: rewardRouter must not be zero address");
        require(_GMXkey != address(0), "Rewards: GMXkey must not be zero address");
        require(_esGMXkey != address(0), "Rewards: esGMXkey must not be zero address");
        require(_MPkey != address(0), "Rewards: MPkey must not be zero address");
        require(_staker != address(0), "Rewards: staker must not be zero address");
        require(_treasury != address(0), "Rewards: treasury must not be zero address");
        require(_feeCalculator != address(0), "Rewards: feeCalculator must not be zero address");
        stakedGmxTracker = _rewardRouter.stakedGmxTracker();
        require(stakedGmxTracker != address(0), "Rewards: stakedGmxTracker must not be zero address");
        feeGmxTracker = _rewardRouter.feeGmxTracker();
        require(feeGmxTracker != address(0), "Rewards: feeGmxTracker must not be zero address");
        gmx = _rewardRouter.gmx();
        require(gmx != address(0), "Rewards: gmx must not be zero address");
        esGmx = _rewardRouter.esGmx();
        require(esGmx != address(0), "Rewards: esGmx must not be zero address");
        bnGmx = _rewardRouter.bnGmx();
        require(bnGmx != address(0), "Rewards: bnGmx must not be zero address");
        GMXkey = _GMXkey;
        esGMXkey = _esGMXkey;
        MPkey = _MPkey;
        weth = _rewardRouter.weth();
        require(weth != address(0), "Rewards: weth must not be zero address");
        staker = _staker;
        treasury = _treasury;
        feeCalculator = _feeCalculator;
        maxPeriodsToUpdateRewards = 4;
        _initializePeriod();
    }

    // - config functions - //

    // Sets treasury address
    function setTreasury(address _treasury) external onlyAdmin {
        require(_treasury != address(0), "Rewards: _treasury is the zero address");
        treasury = _treasury;
    }

    // Sets converter address
    function setConverter(address _converter) external onlyAdmin {
        require(_converter != address(0), "Rewards: _converter is the zero address");
        converter = _converter;
    }

    /**
     * @notice Reserves to set feeCalculator contract.
     * @param _feeCalculator contract address
     * @param _at _feeCalculator can be set after this time
     */
    function reserveFeeCalculator(address _feeCalculator, uint256 _at) external onlyAdmin {
        require(_feeCalculator != address(0), "Rewards: feeCalculator is the zero address");
        require(_at >= IConfig(config).getUpgradeableAt(), "Rewards: at should be later");
        feeCalculatorReserved = Reserved(_feeCalculator, _at);
        emit StakingFeeCalculatorReserved(_feeCalculator, _at);
    }
    
    // Sets reserved FeeCalculator contract.
    function setFeeCalculator() external onlyAdmin {
        require(feeCalculatorReserved.at != 0 && feeCalculatorReserved.at <= block.timestamp, "Rewards: feeCalculator is not yet available");
        feeCalculator = feeCalculatorReserved.to;
    }

    /**
     * @notice Sets the fee tiers and fee amount to be paid to the account calling the reward settlement function for a specific receiver.
     * @param _rewardToken The token type for which the fee will be applied. esGMXkey, MPkey, and weth are all possible.
     * @param _feeTiers Sets the tiers of fee
     * @param _feePercentages Sets the amount of fee to be charged. It is set in 0.01% increments. 10000 = 100%
     */
    function setFeeTiersAndPercentages(address _rewardToken, uint256[] memory _feeTiers, uint16[] memory _feePercentages) external onlyAdmin {
        require(_feeTiers.length == _feePercentages.length, "Rewards: Fee tiers and percentages arrays must have the same length");
        require(_feeTiers.length <= FEE_TIER_LENGTH_MAX, "Rewards: The length of Fee tiers cannot exceed FEE_TIER_LENGTH_MAX");
        require(_rewardToken == esGMXkey || _rewardToken == MPkey || _rewardToken == weth, "Rewards: rewardToken must be esGMXkey, MPkey, or weth");

        // Check if the _feeTiers array is sorted
        for (uint256 i = 1; i < _feeTiers.length; i++) {
            require(_feeTiers[i] < _feeTiers[i - 1], "Rewards: _feeTiers must be sorted in descending order");
        }

        for (uint256 i = 0; i < _feePercentages.length; i++) {
            require(_feePercentages[i] <= FEE_PERCENTAGE_MAX, "Rewards: ratio must be less than or equal to 2500");
        }

        feeTiers[_rewardToken] = _feeTiers;
        feePercentages[_rewardToken] = _feePercentages;
        emit FeeUpdated(_rewardToken, _feeTiers, _feePercentages);
    }

    // Sets max periods to update rewards
    function setMaxPeriodsToUpdateRewards(uint256 maxPeriods) external onlyAdmin {
        require(maxPeriods >= 1, "Rewards: maxPeriods must be greater than or equal to 1");
        maxPeriodsToUpdateRewards = maxPeriods;
    }

    // - external state-changing functions - //

    /**
     * @notice Allows any user to claim rewards for 'account'.
     * Claim for specified periods.
     * @param account The account to claim rewards for.
     * @param periodIndices The periods to claim rewards for.
     */
    function claimRewardWithIndices(address account, uint256[] memory periodIndices) external nonReentrant whenNotPaused {
        _updateAllPastShareByPeriods(account);

        for (uint256 i = 0; i < periodIndices.length; i++) {
            _updateAccountReward(account, periodIndices[i]);
        }
        _claimReward(account);
    }

    /**
     * @notice Allows any user to claim rewards for 'account'.
     * Claim for the recent periods.
     * @param account The account to claim rewards for.
     * @param count The number of periods to claim rewards for.
     */
    function claimRewardWithCount(address account, uint256 count) external nonReentrant whenNotPaused {
        if (count > currentPeriodIndex) count = currentPeriodIndex;

        _updateAllPastShareByPeriods(account);

        for (uint256 i = 1; i <= count; i++) {
            _updateAccountReward(account, currentPeriodIndex - i);
        }
        _claimReward(account);
    }

    // - external view functions - //

    /**
     * @notice Returns the length of feeTiers (or feePercentages, which is the same) to help users query feeTiers and feePercentage elements.
    */
    function feeLength(address _rewardToken) external view returns (uint256) {
        return feeTiers[_rewardToken].length;
    }

    /**
     * @notice Returns the claimable rewards for a given account for the specified periods.
     * @param account The account to check.
     * @param periodIndices The periods to check.
     */
    function claimableRewardWithIndices(address account, uint256[] memory periodIndices) external view returns (uint256 esGMXkeyRewardByGMXkey, uint256 esGMXkeyRewardByEsGMXkey, uint256 mpkeyRewardByGMXkey, uint256 mpkeyRewardByEsGMXkey, uint256 wethRewardByGMXkey, uint256 wethRewardByEsGMXkey, uint256 wethRewardByMPkey) {
        return _claimableReward(account, periodIndices);
    }

    /**
     * @notice Returns the claimable rewards for a given account for the recent periods.
     * @param account The account to check.
     * @param count The number of periods to check.
     */
    function claimableRewardWithCount(address account, uint256 count) external view returns (uint256 esGMXkeyRewardByGMXkey, uint256 esGMXkeyRewardByEsGMXkey, uint256 mpkeyRewardByGMXkey, uint256 mpkeyRewardByEsGMXkey, uint256 wethRewardByGMXkey, uint256 wethRewardByEsGMXkey, uint256 wethRewardByMPkey) {
        if (count > currentPeriodIndex) count = currentPeriodIndex;
        
        uint256[] memory periodIndices = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            periodIndices[i] = currentPeriodIndex - i - 1;
        }
        return _claimableReward(account, periodIndices);
    }

    // - external functions called by other key protocol contracts - //

    /**
     * @notice Initializes the last record for the receiver's deposit balance for esGmx and bnGmx.
     */
    function initTransferReceiver() external {
        require(IConverter(converter).isValidReceiver(msg.sender), "Rewards: receiver is not a valid receiver");
        require(!ITransferReceiver(msg.sender).accepted(), "Rewards: receiver has already accepted the transfer");
        uint256 stakedGmxAmount = IRewardTracker(stakedGmxTracker).depositBalances(msg.sender, gmx);
        lastDepositBalancesForReceivers[msg.sender][gmx] = stakedGmxAmount;
        uint256 stakedEsGmxAmount = IRewardTracker(stakedGmxTracker).depositBalances(msg.sender, esGmx);
        lastDepositBalancesForReceivers[msg.sender][esGmx] = stakedEsGmxAmount;
        uint256 stakedMpAmount = IRewardTracker(feeGmxTracker).depositBalances(msg.sender, bnGmx);
        lastDepositBalancesForReceivers[msg.sender][bnGmx] = stakedMpAmount;
        lastUpdatedAt[msg.sender] = block.timestamp;
        emit ReceiverInitialized(msg.sender, stakedGmxAmount, stakedEsGmxAmount, stakedMpAmount);
    }

    /**
     * @notice Updates all rewards for the transfer receiver contract and transfers the fees.
     * This function mints GMXkey & MPkey, updates common reward-related values,
     * and updates the receiver's value and records for future calls.
     * @dev Allows anyone to call this for a later upgrade of the transfer receiver contract,
     * which might enable anyone to update all rewards & receive fees.
     * @param feeTo The address that receives the fee.
     */
    function updateAllRewardsForTransferReceiverAndTransferFee(address feeTo) external nonReentrant whenNotPaused {
        require(IConverter(converter).isValidReceiver(msg.sender), "Rewards: msg.sender is not a valid receiver");
        require(ITransferReceiver(msg.sender).accepted(), "Rewards: only transferFeeReceiver can be used for this function");

        if (_isFirstInCurrentPeriod()) _initializePeriod();

        uint256 esGmxKeyAmountToMint = _updateNonEthRewardsForTransferReceiverAndTransferFee(msg.sender, esGMXkey, feeTo); // esGMXkey
        uint256 mpKeyAmountToMint = _updateNonEthRewardsForTransferReceiverAndTransferFee(msg.sender, MPkey, feeTo); // MPkey
        uint256 wethAmountToTransfer = _updateWethRewardsForTransferReceiverAndTransferFee(msg.sender, feeTo); // weth

        // Update the receiver's records for later call
        uint256 stakedGmxAmount = IRewardTracker(stakedGmxTracker).depositBalances(msg.sender, gmx);
        if (stakedGmxAmount > lastDepositBalancesForReceivers[msg.sender][gmx]) lastDepositBalancesForReceivers[msg.sender][gmx] = stakedGmxAmount;
        uint256 stakedEsGmxAmount = IRewardTracker(stakedGmxTracker).depositBalances(msg.sender, esGmx);
        if (stakedEsGmxAmount > lastDepositBalancesForReceivers[msg.sender][esGmx]) lastDepositBalancesForReceivers[msg.sender][esGmx] = stakedEsGmxAmount;
        uint256 stakedMpAmount = IRewardTracker(feeGmxTracker).depositBalances(msg.sender, bnGmx);
        if (stakedMpAmount > lastDepositBalancesForReceivers[msg.sender][bnGmx]) lastDepositBalancesForReceivers[msg.sender][bnGmx] = stakedMpAmount;
        lastUpdatedAt[msg.sender] = block.timestamp;

        emit RewardsCalculated(msg.sender, esGmxKeyAmountToMint, mpKeyAmountToMint, wethAmountToTransfer);
    }

    // - internal functions - //

    /**
     * Returns true if it's first reward update call in the current period (period based on the current block).
     */
    function _isFirstInCurrentPeriod() internal view returns (bool) {
        return currentPeriodIndex < block.timestamp / PERIOD;
    }

    /**
     * Initializes period and update reward-related values for the previous periods
     */
    function _initializePeriod() internal {
        // initialize total share values in staker if necessary
        IStaker(staker).updatePastTotalSharesByPeriod(GMXkey, type(uint256).max);
        IStaker(staker).updatePastTotalSharesByPeriod(esGMXkey, type(uint256).max);
        IStaker(staker).updatePastTotalSharesByPeriod(MPkey, type(uint256).max);

        uint256 totalShareForPrevPeriod = IStaker(staker).totalSharesPrevPeriod(GMXkey);
        if (totalShareForPrevPeriod > 0) {
            _applyCumulatedReward(GMXkey, esGMXkey, totalShareForPrevPeriod);
            _applyCumulatedReward(GMXkey, MPkey, totalShareForPrevPeriod);
            _applyCumulatedReward(GMXkey, weth, totalShareForPrevPeriod);
        }

        totalShareForPrevPeriod = IStaker(staker).totalSharesPrevPeriod(esGMXkey);
        if (totalShareForPrevPeriod > 0) {
            _applyCumulatedReward(esGMXkey, esGMXkey, totalShareForPrevPeriod);
            _applyCumulatedReward(esGMXkey, MPkey, totalShareForPrevPeriod);
            _applyCumulatedReward(esGMXkey, weth, totalShareForPrevPeriod);
        }

        totalShareForPrevPeriod = IStaker(staker).totalSharesPrevPeriod(MPkey);
        if (totalShareForPrevPeriod > 0) {
            _applyCumulatedReward(MPkey, weth, totalShareForPrevPeriod);
        }
        currentPeriodIndex = block.timestamp / PERIOD;
    }

    /**
     * Updates all the past share values for the given account.
     */
    function _updateAllPastShareByPeriods(address account) internal {
        IStaker(staker).updatePastUserSharesByPeriod(account, GMXkey, type(uint256).max);
        IStaker(staker).updatePastUserSharesByPeriod(account, esGMXkey, type(uint256).max);
        IStaker(staker).updatePastUserSharesByPeriod(account, MPkey, type(uint256).max);
    }

    /**
     * Claims all the calculated reward and fee for the given account.
     */
    function _claimReward(address account) internal {
        (uint256 esGMXKeyAmountByGMXkey, uint256 esGMXKeyFeeByGMXkey) = _calculateAndClaimRewardAndFee(account, GMXkey, esGMXkey);
        (uint256 mpKeyAmountByGMXKey, uint256 mpKeyFeeByGMXkey) = _calculateAndClaimRewardAndFee(account, GMXkey, MPkey);
        (uint256 esGmxKeyAmountByEsGMXkey, uint256 esGmxKeyFeeByEsGMXkey) = _calculateAndClaimRewardAndFee(account, esGMXkey, esGMXkey);
        (uint256 mpKeyAmountByEsGMXkey, uint256 mpKeyFeeByEsGMXkey) = _calculateAndClaimRewardAndFee(account, esGMXkey, MPkey);
        (uint256 ethAmountByGMXkey, uint256 ethFeeByGMXkey) = _calculateAndClaimRewardAndFee(account, GMXkey, weth);
        (uint256 ethAmountByEsGMXkey, uint256 ethFeeByEsGMXkey) = _calculateAndClaimRewardAndFee(account, esGMXkey, weth);
        (uint256 ethAmountByMPkey, uint256 ethFeeByMPkey) = _calculateAndClaimRewardAndFee(account, MPkey, weth);
        if (ethFeeByGMXkey > 0 || ethFeeByEsGMXkey > 0 || ethFeeByMPkey > 0) _transferAsETH(treasury, ethFeeByGMXkey + ethFeeByEsGMXkey + ethFeeByMPkey);
        if (ethAmountByGMXkey > 0 || ethAmountByEsGMXkey > 0 || ethAmountByMPkey > 0) _transferAsETH(account, ethAmountByGMXkey + ethAmountByEsGMXkey + ethAmountByMPkey);

        emit RewardClaimed(account, esGMXKeyAmountByGMXkey, esGMXKeyFeeByGMXkey, mpKeyAmountByGMXKey, mpKeyFeeByGMXkey, esGmxKeyAmountByEsGMXkey, esGmxKeyFeeByEsGMXkey, 
            mpKeyAmountByEsGMXkey, mpKeyFeeByEsGMXkey, ethAmountByGMXkey, ethFeeByGMXkey, ethAmountByEsGMXkey, ethFeeByEsGMXkey, ethAmountByMPkey, ethFeeByMPkey);
    }

    /**
     * Calculates fee from 'reward' variable and transfer reward & fee if 'isNonWeth' parameter is true
     */
    function _calculateAndClaimRewardAndFee(address account, address stakingToken, address rewardToken) internal returns (uint256 amount, uint256 fee) {
        amount = reward[account][stakingToken][rewardToken];
        if (amount > 0) {
            reward[account][stakingToken][rewardToken] = 0;
            fee = IStakingFeeCalculator(feeCalculator).calculateStakingFee(account, amount, stakingToken, rewardToken);
            amount -= fee;
            if (rewardToken != weth) { // if it's weth, weth rewards from GMXkey, esGMXkey and MPkey will be transferred together
                if (fee > 0) IERC20(rewardToken).safeTransfer(treasury, fee);
                IERC20(rewardToken).safeTransfer(account, amount);
            }
        }
    }

    /**
     * Updates the account's reward.
     */
    function _updateAccountReward(address account, uint256 periodIndex) internal {
        _updateAccountRewardForStakingTokenAndRewardToken(account, GMXkey, esGMXkey, periodIndex);
        _updateAccountRewardForStakingTokenAndRewardToken(account, GMXkey, MPkey, periodIndex);
        _updateAccountRewardForStakingTokenAndRewardToken(account, GMXkey, weth, periodIndex);
        _updateAccountRewardForStakingTokenAndRewardToken(account, esGMXkey, esGMXkey, periodIndex);
        _updateAccountRewardForStakingTokenAndRewardToken(account, esGMXkey, MPkey, periodIndex);
        _updateAccountRewardForStakingTokenAndRewardToken(account, esGMXkey, weth, periodIndex);
        _updateAccountRewardForStakingTokenAndRewardToken(account, MPkey, weth, periodIndex);
    }

    /**
     * Updates the account's reward & other reward-related values for the specified staking token and reward token.
     */
    function _updateAccountRewardForStakingTokenAndRewardToken(address account, address stakingToken, address rewardToken, uint256 periodIndex) internal {
        if (IStaker(staker).userSharesByPeriod(account, stakingToken, periodIndex) > 0) {
            uint256 delta = _calculateReward(stakingToken, rewardToken, account, periodIndex);
            if (delta > 0) {
                reward[account][stakingToken][rewardToken] += delta;
                lastRewardPerUnit[account][stakingToken][rewardToken][periodIndex] = rewardPerUnit[stakingToken][rewardToken][periodIndex];
            }
        }
    }

    /**
     * Calculates the reward for the specified staking token and reward token that is claimable by the account.
     */
    function _calculateReward(address stakingToken, address rewardToken, address account, uint256 periodIndex) internal view returns (uint256) {
        return Math.mulDiv(
            rewardPerUnit[stakingToken][rewardToken][periodIndex] - lastRewardPerUnit[account][stakingToken][rewardToken][periodIndex], 
            IStaker(staker).userSharesByPeriod(account, stakingToken, periodIndex),
            PRECISION
        );
    }

    /**
     * Updates the esGMX, MP rewards from the transfer receiver contract & transfer fee.
     * @param receiver The receiver contract from which the rewards originate.
     * @param rewardToken The reward token to update.
     * @param feeTo The address to which the transfer fee is sent.
     */
    function _updateNonEthRewardsForTransferReceiverAndTransferFee(address receiver, address rewardToken, address feeTo) internal returns (uint256 amountToMint) {
        if (ITransferReceiver(receiver).isForMpKey()) return 0;
        uint256 _depositBalance = _getDepositBalancesForReceiver(receiver, rewardToken);
        uint256 _lastDepositBalance = lastDepositBalancesForReceivers[receiver][_getStakedToken(rewardToken)];
        if (_depositBalance > _lastDepositBalance) {
            amountToMint = _depositBalance - _lastDepositBalance;

            (uint256 amount, uint256 fee) = _calculateFee(amountToMint, _getFeeRate(receiver, rewardToken));

            // Distribute esGMXkey or MPkey in the ratio of GMX and esGMX
            uint256 gmxBalance = lastDepositBalancesForReceivers[receiver][gmx];
            uint256 esGmxBalance = lastDepositBalancesForReceivers[receiver][esGmx];

            uint256 amountByEsGMX = Math.mulDiv(amount, esGmxBalance, gmxBalance + esGmxBalance);

            uint256 _lastUpdatedAt = lastUpdatedAt[receiver];
            _updateNonSharedReward(GMXkey, rewardToken, amount - amountByEsGMX, _lastUpdatedAt);
            _updateNonSharedReward(esGMXkey, rewardToken, amountByEsGMX, _lastUpdatedAt);

            IERC20(rewardToken).mint(address(this), amount);
            if (fee > 0) IERC20(rewardToken).mint(feeTo, fee);
        }
    }

    /**
     * Updates the WETH rewards from the transfer receiver contract & transfer fee.
     * @param receiver The receiver contract from which the rewards originate.
     * @param feeTo The address to which the transfer fee is sent.
     */
    function _updateWethRewardsForTransferReceiverAndTransferFee(address receiver, address feeTo) internal returns (uint256 amountToTransfer) {
        amountToTransfer = IERC20(weth).allowance(receiver, address(this));
        // use allowance to prevent 'weth transfer attack' by transferring any amount of weth to the receiver contract
        if (amountToTransfer > 0) {
            IERC20(weth).safeTransferFrom(receiver, address(this), amountToTransfer);
            // Update common reward-related values
            (uint256 amount, uint256 fee) = _calculateFee(amountToTransfer, _getFeeRate(receiver, weth));
            _updateWethReward(amount, receiver);
            if (fee > 0) _transferAsETH(feeTo, fee);
        }
    }

    /**
     * Records the calculated reward amount per unit staking amount.
     * @param stakingToken Staked token
     * @param rewardToken Token paid as a reward
     * @param amount Total claimable reward amount
     * @param _lastUpdatedAt The last time the reward was updated
     */
    function _updateNonSharedReward(address stakingToken, address rewardToken, uint256 amount, uint256 _lastUpdatedAt) internal {
        if (_lastUpdatedAt >= currentPeriodIndex * PERIOD) {
            cumulatedReward[stakingToken][rewardToken] += amount;
        } else {
            uint256 denominator = block.timestamp - _lastUpdatedAt;
            uint256 firstIdx = _lastUpdatedAt / PERIOD + 1;
            uint256 lastIdx = block.timestamp / PERIOD - 1;
            uint256 amountLeft = amount;
            uint256 amountToDistribute = 0;
            uint256 totalShare = 0;
            if (lastIdx + 2 - firstIdx > maxPeriodsToUpdateRewards) {
                firstIdx = lastIdx - maxPeriodsToUpdateRewards + 1;
                denominator = maxPeriodsToUpdateRewards * PERIOD + block.timestamp - block.timestamp / PERIOD * PERIOD;
            } else {
                amountToDistribute = amount * ((_lastUpdatedAt / PERIOD + 1) * PERIOD - _lastUpdatedAt) / denominator;
                amountLeft -= amountToDistribute;
                totalShare = IStaker(staker).totalSharesByPeriod(stakingToken, _lastUpdatedAt / PERIOD);
                if (totalShare == 0) {
                    cumulatedReward[stakingToken][rewardToken] += amountToDistribute;
                } else {
                    rewardPerUnit[stakingToken][rewardToken][_lastUpdatedAt / PERIOD] += Math.mulDiv(amountToDistribute, PRECISION, totalShare);
                }
            }

            for (uint256 i = firstIdx; i <= lastIdx; i++) {
                amountToDistribute = amount * PERIOD / denominator;
                amountLeft -= amountToDistribute;
                totalShare = IStaker(staker).totalSharesByPeriod(stakingToken, i);
                if (totalShare == 0) {
                    cumulatedReward[stakingToken][rewardToken] += amountToDistribute;
                } else {
                    rewardPerUnit[stakingToken][rewardToken][i] += Math.mulDiv(amountToDistribute, PRECISION, totalShare);
                }
            }

            cumulatedReward[stakingToken][rewardToken] += amountLeft;
        }
    }

    /**
     * Applies the cumulated reward to the previous period.
     */
    function _applyCumulatedReward(address stakingToken, address rewardToken, uint256 totalShareForPrevPeriod) internal {
        rewardPerUnit[stakingToken][rewardToken][block.timestamp / PERIOD - 1] += Math.mulDiv(cumulatedReward[stakingToken][rewardToken], PRECISION, totalShareForPrevPeriod);
        cumulatedReward[stakingToken][rewardToken] = 0;
    }

    /**
     * Records the reward amount per unit staking amount for WETH rewards paid to both GMXkey, esGMXkey and MPkey.
     * @dev In the case of WETH rewards paid to GMXkey, esGMXkey and MPkey, the reward amount for each cannot be known.
     * Therefore, they are calculated together at once.
     * @param amount Total claimable WETH amount
     * @param receiver The receiver contract from which the rewards originate.
     */
    function _updateWethReward(uint256 amount, address receiver) internal {
        uint256 _lastUpdatedAt = lastUpdatedAt[receiver];
        if (ITransferReceiver(receiver).isForMpKey()) {
            _updateNonSharedReward(MPkey, weth, amount, _lastUpdatedAt);
            return;
        }
        uint256 gmxStaked = lastDepositBalancesForReceivers[receiver][gmx];
        uint256 esGmxStaked = lastDepositBalancesForReceivers[receiver][esGmx];
        uint256 mpStaked = lastDepositBalancesForReceivers[receiver][bnGmx];
        uint256 totalStaked = gmxStaked + esGmxStaked + mpStaked;
        uint256 amountForMpKey = Math.mulDiv(amount, mpStaked, totalStaked);
        uint256 amountForEsGmxKey = Math.mulDiv(amount, esGmxStaked, totalStaked);
        uint256 amountForGmxKey = amount - amountForEsGmxKey - amountForMpKey;
        _updateNonSharedReward(GMXkey, weth, amountForGmxKey, _lastUpdatedAt);
        _updateNonSharedReward(esGMXkey, weth, amountForEsGmxKey, _lastUpdatedAt);
        _updateNonSharedReward(MPkey, weth, amountForMpKey, _lastUpdatedAt);
    }

    /**
     * Returns the claimable rewards for a given account for the specified periods.
     * @param account The account to check.
     * @param periodIndices The period indices to check.
     * @return esGMXkeyRewardByGMXkey The claimable esGMXkey reward by GMXkey.
     * @return esGMXkeyRewardByEsGMXkey The claimable esGMXkey reward by esGMXkey.
     * @return mpkeyRewardByGMXkey The claimable MPkey reward by GMXkey.
     * @return mpkeyRewardByEsGMXkey The claimable MPkey reward by esGMXkey.
     * @return wethRewardByGMXkey The claimable WETH reward by GMXkey.
     * @return wethRewardByEsGMXkey The claimable WETH reward by esGMXkey.
     * @return wethRewardByMPkey The claimable WETH reward by MPkey.
     */
    function _claimableReward(address account, uint256[] memory periodIndices) internal view returns (uint256 esGMXkeyRewardByGMXkey, uint256 esGMXkeyRewardByEsGMXkey, uint256 mpkeyRewardByGMXkey, uint256 mpkeyRewardByEsGMXkey, uint256 wethRewardByGMXkey, uint256 wethRewardByEsGMXkey, uint256 wethRewardByMPkey) {
        esGMXkeyRewardByGMXkey = reward[account][GMXkey][esGMXkey];
        esGMXkeyRewardByEsGMXkey = reward[account][esGMXkey][esGMXkey];
        mpkeyRewardByGMXkey = reward[account][GMXkey][MPkey];
        mpkeyRewardByEsGMXkey = reward[account][esGMXkey][MPkey];
        wethRewardByGMXkey = reward[account][GMXkey][weth];
        wethRewardByEsGMXkey = reward[account][esGMXkey][weth];
        wethRewardByMPkey = reward[account][MPkey][weth];
        for (uint256 i = 0; i < periodIndices.length; i++) {
            uint256 periodIndex = periodIndices[i];
            esGMXkeyRewardByGMXkey += _calculateReward(GMXkey, esGMXkey, account, periodIndex);
            esGMXkeyRewardByEsGMXkey += _calculateReward(esGMXkey, esGMXkey, account, periodIndex);
            mpkeyRewardByGMXkey += _calculateReward(GMXkey, MPkey, account, periodIndex);
            mpkeyRewardByEsGMXkey += _calculateReward(esGMXkey, MPkey, account, periodIndex);
            wethRewardByGMXkey += _calculateReward(GMXkey, weth, account, periodIndex);
            wethRewardByEsGMXkey += _calculateReward(esGMXkey, weth, account, periodIndex);
            wethRewardByMPkey += _calculateReward(MPkey, weth, account, periodIndex);
        }
        esGMXkeyRewardByGMXkey -= IStakingFeeCalculator(feeCalculator).calculateStakingFee(account, esGMXkeyRewardByGMXkey, GMXkey, esGMXkey);
        esGMXkeyRewardByEsGMXkey -= IStakingFeeCalculator(feeCalculator).calculateStakingFee(account, esGMXkeyRewardByEsGMXkey, esGMXkey, esGMXkey);
        mpkeyRewardByGMXkey -= IStakingFeeCalculator(feeCalculator).calculateStakingFee(account, mpkeyRewardByGMXkey, GMXkey, MPkey);
        mpkeyRewardByEsGMXkey -= IStakingFeeCalculator(feeCalculator).calculateStakingFee(account, mpkeyRewardByEsGMXkey, esGMXkey, MPkey);
        wethRewardByGMXkey -= IStakingFeeCalculator(feeCalculator).calculateStakingFee(account, wethRewardByGMXkey, GMXkey, weth);
        wethRewardByEsGMXkey -= IStakingFeeCalculator(feeCalculator).calculateStakingFee(account, wethRewardByEsGMXkey, esGMXkey, weth);
        wethRewardByMPkey -= IStakingFeeCalculator(feeCalculator).calculateStakingFee(account, wethRewardByMPkey, MPkey, weth);
    }

    function _getFeeRate(address receiver, address _rewardToken) internal view returns (uint16) {
        uint256[] memory _feeTiers = feeTiers[_rewardToken];
        if (_feeTiers.length == 0) return 0;

        uint16[] memory _feePercentages = feePercentages[_rewardToken];

        uint256 panGmxAmount = _getLastPanGmxDepositBalances(receiver);
        uint16 _feePercentage = _feePercentages[_feePercentages.length - 1];
        for (uint256 i = 0; i < _feeTiers.length; i++) {
            if (panGmxAmount >= _feeTiers[i]) {
                _feePercentage = _feePercentages[i];
                break;
            }
        }

        return _feePercentage;
    }

    function _getLastPanGmxDepositBalances(address receiver) internal view returns (uint256) {
        return lastDepositBalancesForReceivers[receiver][gmx] + lastDepositBalancesForReceivers[receiver][esGmx];
    }

    /**
     * Queries the staking amount of the token corresponding to the rewardToken.
     * @param receiver The receiver contract targeted to check how much stakingToken has been accumulated for the given rewardToken.
     * @param rewardToken Which rewardToken's stakingToken amount is being queried.
     */
    function _getDepositBalancesForReceiver(address receiver, address rewardToken) internal view returns (uint256) {
        if (rewardToken == GMXkey || rewardToken == esGMXkey) {
            return IRewardTracker(stakedGmxTracker).depositBalances(receiver, _getStakedToken(rewardToken));
        } else { // rewardToken == MPkey
            return IRewardTracker(feeGmxTracker).depositBalances(receiver, _getStakedToken(rewardToken));
        }
    }

    /**
     * Queries the token staked at GMX protocol, corresponding to the rewardToken.
     */
    function _getStakedToken(address rewardToken) internal view returns (address) {
        if (rewardToken == GMXkey) {
            return gmx;
        } else if (rewardToken == esGMXkey) {
            return esGmx;
        } else { // rewardToken == MPkey
            return bnGmx;
        }
    }

    /**
     * Calculates the reward amount after fee transfer and its fee.
     */
    function _calculateFee(uint256 _amount, uint16 _feeRate) internal pure returns (uint256, uint256) {
        uint256 _fee = _amount * _feeRate / FEE_PERCENTAGE_BASE;
        return (_amount - _fee, _fee);
    }

    /**
     * Transfers the specified amount as ETH to the specified address.
     */
    function _transferAsETH(address to, uint256 amount) internal {
        // amount is already non-zero

        IWETH(weth).withdraw(amount);
        (bool success,) = to.call{value : amount}("");
        require(success, "Transfer failed");
    }

    receive() external payable {
        require(msg.sender == weth);
    }
}
