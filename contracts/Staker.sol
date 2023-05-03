// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

import "./interfaces/IERC20.sol";
import "./interfaces/IRewards.sol";
import "./interfaces/IStaker.sol";
import "./common/Adminable.sol";
import "./common/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./common/Pausable.sol";

/**
 * @title Staker
 * @author Key Finance
 * @notice Staker is a contract that allows users to stake GMXkey and MPkey tokens.
 */
contract Staker is IStaker, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // key protocol contracts
    address public immutable GMXkey;
    address public immutable MPkey;
    address public rewards;

    // state variables
    mapping(address => mapping(address => uint256)) public balance;
    mapping(address => uint256) public totalBalance;

    constructor(address _admin, address _GMXkey, address _MPkey) Pausable(_admin) {
        require(_GMXkey != address(0), "Staker: GMXkey is the zero address");
        require(_MPkey != address(0), "Staker: MPkey is the zero address");
        GMXkey = _GMXkey;
        MPkey = _MPkey;
    }

    // - config functions - //
    
    /**
     * @notice Sets the rewards contract address
     * @param _rewards Aaddress of the rewards contract
     */
    function setRewards(address _rewards) external onlyAdmin {
        require(_rewards != address(0), "Staker: _rewards is the zero address");
        require(rewards == address(0), "Staker: rewards is already set");
        rewards = _rewards;
    }

    // - external state-changing functions - //

    /**
     * @notice Stakes GMXkey or MPkey tokens.
     * @param account Account to stake for.
     * @param token Token to stake.
     * @param amount Amount to unstake.
     */
    function stake(address account, address token, uint256 amount) external nonReentrant whenNotPaused {
        require(account != address(0), "Staker: account is the zero address");
        require(_isStakable(token), "Staker: token is not stakable");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IRewards(rewards).updateRewards(account, token);
        totalBalance[token] += amount;
        unchecked {
            balance[token][account] += amount;
        }

        emit Staked(msg.sender, account, token, amount);
    }

    /**
     * @notice Unstakes GMXkey or MPkey tokens.
     * @param account Account that will receive unstaked tokens.
     * @param token Token to unstake.
     * @param amount Amount to unstake.
     */
    function unstake(address account, address token, uint256 amount) external nonReentrant {
        require(account != address(0), "Staker: account is the zero address");
        require(_isStakable(token), "Staker: token is not stakable");

        uint256 userBalance = balance[token][msg.sender];
        require(userBalance >= amount, "Staker: insufficient balance");

        IRewards(rewards).updateRewards(msg.sender, token);
        unchecked {
            balance[token][msg.sender] = userBalance - amount;
            totalBalance[token] -= amount;
        }
        IERC20(token).safeTransfer(account, amount);

        emit Unstaked(msg.sender, account, token, amount);
    }

    // - internal functions - //

    /**
     * @notice Checks if the token is stakeable.
     * @param token Token address to check.
     */
    function _isStakable(address token) internal view returns (bool) {
        return token == GMXkey || token == MPkey;
    }
}
