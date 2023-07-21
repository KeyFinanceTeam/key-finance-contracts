// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./interfaces/IERC20.sol";
import "./interfaces/IStaker.sol";
import "./common/SafeERC20.sol";
import "./common/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Staker
 * @author Key Finance
 * @notice
 * Staker is a contract that allows users to stake GMXkey, esGMXkey and MPkey tokens and calculate shares.
 * Shares are proportional to time and volume and are settled at weekly intervals.
 */
contract Staker is IStaker, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // constants
    uint256 public constant PERIOD = 1 weeks;

    // key protocol contracts
    address public immutable GMXkey;
    address public immutable esGMXkey;
    address public immutable MPkey;

    // state variables
    mapping(address => uint256) public totalBalance; // by token
    mapping(address => mapping(address => uint256)) public userBalance; // by account and token

    mapping(address => mapping(uint256 => uint256)) public totalSharesByPeriod; // by token and period
    mapping(address => mapping(address => mapping(uint256 => uint256))) internal _userSharesByPeriod; // by account and token and period

    mapping(address => uint256) public latestTotalShares; // when latest updated, by token
    mapping(address => uint256) public latestTotalSharesUpdatedAt; // by token

    mapping(address => mapping(address => uint256)) public latestUserShares; // when latest updated, by account and token
    mapping(address => mapping(address => uint256)) public latestUserSharesUpdatedAt; // by account and token

    constructor(address _admin, address _GMXkey, address _esGMXkey, address _MPkey) Pausable(_admin) {
        require(_GMXkey != address(0), "Staker: GMXkey is the zero address");
        require(_esGMXkey != address(0), "Staker: esGMXkey is the zero address");
        require(_MPkey != address(0), "Staker: MPkey is the zero address");
        GMXkey = _GMXkey;
        esGMXkey = _esGMXkey;
        MPkey = _MPkey;
    }

    // - external state-changing functions - //

    /**
     * @notice Stakes GMXkey, esGMXkey, or MPkey tokens.
     * @param token Token to stake.
     * @param amount Amount to unstake.
     */
    function stake(address token, uint256 amount) external nonReentrant whenNotPaused {
        require(_isStakable(token), "Staker: token is not stakable");
        require(amount > 0, "Staker: amount is 0");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // update totalSharesByPeriod
        _updateTotalSharesByPeriod(token);

        // update userSharesByPeriod
        _updateUserSharesByPeriod(token, msg.sender);

        totalBalance[token] += amount;
        unchecked {
            userBalance[msg.sender][token] += amount;
        }

        emit Staked(msg.sender, token, amount);
    }

    /**
     * @notice Unstakes GMXkey, esGMXkey or MPkey tokens.
     * @param token Token to unstake.
     * @param amount Amount to unstake.
     */
    function unstake(address token, uint256 amount) external nonReentrant {
        require(_isStakable(token), "Staker: token is not stakable");
        require(amount > 0, "Staker: amount is 0");

        uint256 _balance = userBalance[msg.sender][token];
        require(_isAmountUnstakable(token, _balance, amount), "Staker: insufficient balance");

        // update totalSharesByPeriod
        _updateTotalSharesByPeriod(token);

        // update userSharesByPeriod
        _updateUserSharesByPeriod(token, msg.sender);

        unchecked {
            totalBalance[token] -= amount;
            userBalance[msg.sender][token] = _balance - amount;
        }

        IERC20(token).safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, token, amount);
    }

    /**
     * @notice Updates total share values in the past.
     * @param token Token to update total share values in the past.
     * @param loop The number of periods to update.
     */
    function updatePastTotalSharesByPeriod(address token, uint256 loop) external {
        _updatePastTotalSharesByPeriod(token, loop);
    }

    /**
     * @notice Updates user share values in the past.
     * @param token Token to update user share values in the past.
     * @param account Account to update user share values in the past.
     * @param loop The number of periods to update.
     */
    function updatePastUserSharesByPeriod(address account, address token, uint256 loop) external {
        _updatePastUserSharesByPeriod(token, account, loop);
    }

    // - external view functions - //

    /**
     * @notice Returns the total share of the previous period.
     * @param token Token to look up
     */
    function totalSharesPrevPeriod(address token) external view returns (uint256) {
        return totalSharesByPeriod[token][_getPeriodNumber(block.timestamp) - 1];
    }

    /**
     * @notice Returns the user share for the specified period.
     * @dev This should be used for the previous periods.
     * @param token Token to look up
     * @param account Account to look up
     * @param periodIndex Period index to look up
     */
    function userSharesByPeriod(address account, address token, uint256 periodIndex) external view returns (uint256) {
        if ((periodIndex + 1) * PERIOD > block.timestamp) return 0;

        uint256 _latestUpdatedPeriod = _getPeriodNumber(latestUserSharesUpdatedAt[account][token]);
        if (periodIndex < _latestUpdatedPeriod) {
            return _userSharesByPeriod[account][token][periodIndex];
        } else if (periodIndex == _latestUpdatedPeriod) {
            return latestUserShares[account][token] + _getShare(userBalance[account][token], latestUserSharesUpdatedAt[account][token], (_latestUpdatedPeriod + 1) * PERIOD);
        } else {
            return _getShare(userBalance[account][token], PERIOD);
        }
    }

    // - internal functions - //

    /**
     * Checks if the token is stakeable.
     * @param token Token address to check.
     */
    function _isStakable(address token) internal view returns (bool) {
        return token == GMXkey || token == esGMXkey || token == MPkey;
    }

    function _isAmountUnstakable(address, uint256 _userBalance, uint256 _amount) internal virtual view returns (bool) {
        return _userBalance >= _amount;
    }

    function _updateTotalSharesByPeriod(address token) internal {
        _updatePastTotalSharesByPeriod(token, type(uint256).max);
    }

    function _updatePastTotalSharesByPeriod(address token, uint256 loop) internal {
        _updatePastSharesByPeriod(
            token,
            totalBalance[token],
            totalSharesByPeriod[token],
            latestTotalShares,
            latestTotalSharesUpdatedAt,
            loop
        );
    }

    function _updateUserSharesByPeriod(address token, address account) internal {
        _updatePastUserSharesByPeriod(token, account, type(uint256).max);
    }

    function _updatePastUserSharesByPeriod(address token, address account, uint256 loop) internal {
        _updatePastSharesByPeriod(
            token,
            userBalance[account][token],
            _userSharesByPeriod[account][token],
            latestUserShares[account],
            latestUserSharesUpdatedAt[account],
            loop
        );
    }

    /**
     * Updates sharesByPeriod in the past.
     */
    function _updatePastSharesByPeriod
    (
        address token,
        uint256 _balance,
        mapping(uint256 => uint256) storage _sharesByPeriod,
        mapping(address => uint256) storage _latestShares,
        mapping(address => uint256) storage _latestSharesUpdatedAt,
        uint256 loop
    ) internal {
        if (loop == 0) revert("loop must be greater than 0");

        if (_latestSharesUpdatedAt[token] == 0) {
            _latestSharesUpdatedAt[token] = block.timestamp;
            return;
        }

        uint256 firstIndex = _getPeriodNumber(_latestSharesUpdatedAt[token]);
        uint256 lastIndex = _getPeriodNumber(block.timestamp) - 1;
        if (loop != type(uint256).max && lastIndex >= firstIndex + loop) {
            lastIndex = firstIndex + loop - 1;
        }

        if (firstIndex > lastIndex) { // called again in the same period
            _latestShares[token] += _getShare(_balance, _latestSharesUpdatedAt[token], block.timestamp);
            _latestSharesUpdatedAt[token] = block.timestamp;
        } else { // when the last updated period passed, update sharesByPeriod of the period
            _sharesByPeriod[firstIndex] = _latestShares[token] + _getShare(_balance, _latestSharesUpdatedAt[token], (firstIndex + 1) * PERIOD);
            for (uint256 i = firstIndex + 1; i <= lastIndex; i++) {
                _sharesByPeriod[i] = _getShare(_balance, PERIOD);
            }

            if (loop != type(uint256).max) {
                _latestShares[token] = 0;
                _latestSharesUpdatedAt[token] = (lastIndex + 1) * PERIOD;
            } else {
                _latestShares[token] = _getShare(_balance, (lastIndex + 1) * PERIOD, block.timestamp);
                _latestSharesUpdatedAt[token] = block.timestamp;
            }
        }
    }

    function _getPeriodNumber(uint256 _time) internal pure returns (uint256) {
        return _time / PERIOD;
    }

    function _getShare(uint256 _balance, uint256 _startTime, uint256 _endTime) internal pure returns (uint256) {
        return _getShare(_balance, (_endTime - _startTime));
    }

    function _getShare(uint256 _balance, uint256 _duration) internal pure returns (uint256) {
        return _balance * _duration;
    }
}
