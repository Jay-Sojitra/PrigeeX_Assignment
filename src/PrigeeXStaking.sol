// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PrigeeX Staking Contract
 * @notice Allows users to stake PGX tokens and claim rewards using the accumulator pattern
 * @dev Reward distribution follows the Synthetix/SushiSwap MasterChef pattern (industry standard)
 * @dev Uses global rewardPerTokenStored accumulator instead of per-user timestamps
 */
contract PrigeeXStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    // Staking state
    mapping(address => uint256) public balanceOf;
    uint256 public totalStaked;

    // Reward state (accumulator pattern - same as Synthetix/SushiSwap)
    uint256 public rewardRate; // Rewards per second
    uint256 public periodFinish; // When current reward period ends
    uint256 public rewardPerTokenStored; // Global accumulator: total rewards per token staked
    uint256 public lastUpdateTime; // Last time accumulator was updated
    uint256 public rewardBalance; // Available rewards in contract

    // Per-user reward snapshots
    mapping(address => uint256) public userRewardPerTokenPaid; // User's snapshot of accumulator
    mapping(address => uint256) public rewards; // Earned rewards (pending claim)

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 newRate);
    event RewardsFunded(address indexed funder, uint256 amount);

    error ZeroAmount();
    error InsufficientStakedBalance();
    error ZeroRewards();
    error InsufficientRewardBalance();

    /**
     * @notice Initializes the staking contract
     * @param _stakingToken The address of the PrigeeX (PGX) token
     * @param _rewardToken The address of the reward token (can be same as stakingToken)
     */
    constructor(address _stakingToken, address _rewardToken) Ownable(msg.sender) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
    }

    /**
     * @notice Modifier to update rewards before executing a function
     * @dev Updates global accumulator, then calculates and saves pending rewards for account
     */
    modifier updateReward(address account) {
        _updateReward(account);
        _;
    }

    /**
     * @notice Internal function to update reward state
     * @dev Extracted from modifier to reduce bytecode size
     */
    function _updateReward(address account) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    /**
     * @notice Returns the last time applicable for reward calculation
     * @dev Uses min of current time and period finish to prevent over-distribution
     */
    function lastTimeRewardApplicable() public view returns (uint256) {
        return _min(block.timestamp, periodFinish);
    }

    /**
     * @notice Calculates the current reward per token staked (global accumulator)
     * @dev This value only increases over time, never resets
     * @return The accumulated rewards per token since contract inception
     */
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + ((rewardRate * (lastTimeRewardApplicable() - lastUpdateTime) * 1e18) / totalStaked);
    }

    /**
     * @notice Calculates earned rewards for an account
     * @param account The address to calculate rewards for
     * @return The total rewards earned (including already accrued but unclaimed)
     */
    function earned(address account) public view returns (uint256) {
        return ((balanceOf[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) + rewards[account];
    }

    /**
     * @notice Stakes PGX tokens into the contract
     * @param amount The amount of tokens to stake
     * @dev Calls updateReward to save pending rewards BEFORE updating balance
     */
    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();

        balanceOf[msg.sender] += amount;
        totalStaked += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Withdraws staked PGX tokens from the contract
     * @param amount The amount of tokens to withdraw
     * @dev Calls updateReward to save pending rewards BEFORE updating balance
     */
    function withdraw(uint256 amount) external nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();
        if (balanceOf[msg.sender] < amount) revert InsufficientStakedBalance();

        balanceOf[msg.sender] -= amount;
        totalStaked -= amount;
        stakingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Claims pending rewards for the caller
     * @dev Rewards are stored in rewards[msg.sender] mapping, updated by updateReward modifier
     */
    function claimRewards() external nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward == 0) revert ZeroRewards();
        if (reward > rewardBalance) revert InsufficientRewardBalance();

        rewardBalance -= reward;
        rewards[msg.sender] = 0;
        rewardToken.safeTransfer(msg.sender, reward);

        emit RewardsClaimed(msg.sender, reward);
    }

    /**
     * @notice Emergency withdrawal of all staked tokens (forfeits any pending rewards)
     * @dev Forfeits rewards by zeroing them out, returns only staked principal
     */
    function emergencyWithdraw() external nonReentrant updateReward(msg.sender) {
        uint256 amount = balanceOf[msg.sender];
        if (amount == 0) revert ZeroAmount();

        // Forfeit pending rewards
        rewards[msg.sender] = 0;
        balanceOf[msg.sender] = 0;
        totalStaked -= amount;

        stakingToken.safeTransfer(msg.sender, amount);

        emit EmergencyWithdraw(msg.sender, amount);
    }

    /**
     * @notice Funds the reward pool - anyone can deposit reward tokens
     * @param amount The amount of reward tokens to add
     * @dev Calls updateReward with address(0) to update accumulator without user snapshot
     */
    function fundRewards(uint256 amount) external nonReentrant updateReward(address(0)) {
        if (amount == 0) revert ZeroAmount();

        rewardBalance += amount;
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);

        emit RewardsFunded(msg.sender, amount);
    }

    /**
     * @notice Sets the reward rate and starts a new reward period
     * @param _rewardRate The new reward rate (rewards per second)
     * @dev Sets periodFinish to 1 year from now as default
     */
    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        rewardRate = _rewardRate;
        periodFinish = block.timestamp + 365 days; // Default 1 year reward period
        emit RewardRateUpdated(_rewardRate);
    }

    /**
     * @notice Returns the staked balance for a given address
     */
    function getStake(address account) external view returns (uint256) {
        return balanceOf[account];
    }

    /**
     * @notice Returns available reward balance in contract
     */
    function getRewardBalance() external view returns (uint256) {
        return rewardBalance;
    }

    /**
     * @notice Internal minimum function
     */
    function _min(uint256 x, uint256 y) private pure returns (uint256) {
        return x <= y ? x : y;
    }
}
