// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./interfaces/IERC20.sol";
import "./interfaces/IReserved.sol";
import "./interfaces/IConfig.sol";
import "./common/ConfigUser.sol";
import "./common/SafeERC20.sol";
import "./Staker.sol";

/**
 * @title StakerV2
 * @author Key Finance
 * @notice
 * StakerV2 is a contract that allows users to stake GMXkey, esGMXkey and MPkey tokens and calculate shares.
 * Shares are proportional to time and volume and are settled at weekly intervals.
 */
contract StakerV2 is Staker, IReserved, ConfigUser {
    using SafeERC20 for IERC20;

    address public immutable gmx;
    address public immutable usdc;

    // key protocol contracts
    mapping(address => mapping(address => address)) public markets; // by token and currency (gmx or usdc)

    mapping(address => mapping(address => uint256)) public lockedBalance; // by account and token

    mapping(address => mapping(address => Reserved)) public marketReserved;

    event Locked(address indexed user, address indexed token, uint256 amount);
    event Unlocked(address indexed user, address indexed token, uint256 amount);
    event MarketReserved(address indexed market, uint256 at);

    constructor(address _admin, address _config, address _GMXkey, address _esGMXkey, address _MPkey, address _gmx, address _usdc) ConfigUser(_config) Staker(_admin, _GMXkey, _esGMXkey, _MPkey) {
        require(_gmx != address(0), "Staker: gmx is the zero address");
        require(_usdc != address(0), "Staker: usdc is the zero address");
        gmx = _gmx;
        usdc = _usdc;
    }

    modifier onlyMarket(address _token) {
        require(msg.sender == markets[_token][gmx] || msg.sender == markets[_token][usdc], "Staker: caller is not the market");
        _;
    }

    function setMarket(address _token, address _currency, address _market) external onlyAdmin {
        require(_market != address(0), "Staker: market is the zero address");
        require(_token == GMXkey || _token == esGMXkey || _token == MPkey, "Staker: token is not supported");
        require(_currency == gmx || _currency == usdc, "Staker: currency is not supported");
        require(markets[_token][_currency] == address(0), "Staker: market is already set");
        markets[_token][_currency] = _market;
    }

    function reserveMarket(address _token, address _currency, address _market, uint256 _at) external onlyAdmin {
        require(_market != address(0), "Market: market is the zero address");
        require(_token == GMXkey || _token == esGMXkey || _token == MPkey, "Staker: token is not supported");
        require(_currency == gmx || _currency == usdc, "Staker: currency is not supported");
        require(_at >= IConfig(config).getUpgradeableAt(), "Market: at should be later");
        marketReserved[_token][_currency] = Reserved(_market, _at);

        emit MarketReserved(_market, _at);
    }

    // Sets reserved Market contract.
    function setMarket(address _token, address _currency) external onlyAdmin {
        Reserved memory _marketReserved = marketReserved[_token][_currency];
        require(_marketReserved.at != 0 && _marketReserved.at <= block.timestamp, "Market: market is not yet available");
        markets[_token][_currency] = _marketReserved.to;
    }

    // - external functions called by other key protocol contracts - //

    function stakeAndLock(address account, address token, uint256 amount) external onlyMarket(token) nonReentrant whenNotPaused {
        require(_isStakable(token), "Staker: token is not stakable");
        require(amount > 0, "Staker: amount is 0");

        // update totalSharesByPeriod
        _updateTotalSharesByPeriod(token);

        // update userSharesByPeriod
        _updateUserSharesByPeriod(token, account);

        totalBalance[token] += amount;
        unchecked {
            userBalance[account][token] += amount;
            lockedBalance[account][token] += amount;
        }

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(account, token, amount);
        emit Locked(account, token, amount);
    }

    function unlockAndUnstake(address account, address token, uint256 amount) external onlyMarket(token) nonReentrant {
        require(_isStakable(token), "Staker: token is not stakable");
        require(amount > 0, "Staker: amount is 0");

        uint256 _lockedBalance = lockedBalance[account][token];
        require(amount <= _lockedBalance, "Staker: insufficient locked balance");

        // update totalSharesByPeriod
        _updateTotalSharesByPeriod(token);

        // update userSharesByPeriod
        _updateUserSharesByPeriod(token, account);

        unchecked {
            totalBalance[token] -= amount;
            userBalance[account][token] -= amount;
            lockedBalance[account][token] = _lockedBalance - amount;
        }

        IERC20(token).safeTransfer(msg.sender, amount);

        emit Unlocked(account, token, amount);
        emit Unstaked(account, token, amount);
    }

    function _isAmountUnstakable(address token, uint256 _userBalance, uint256 _amount) internal override view returns (bool) {
        return _userBalance >= _amount + lockedBalance[msg.sender][token];
    }
}
