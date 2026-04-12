Hello, my fellow XBase Community. In today’s lesson, we will create a generic simple staking smart contract. You could modify staking features based on your project’s use case from this fundamental standpoint. This contract is inspired by Solidity By Example and we will explain how this works.

First of all, We will create a contract called StakingRewards and we need to initialize these variables.

contract StakingRewards {
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardsToken;

    address public owner;
    // Duration of rewards to be paid out (in seconds)
    uint public poolDuration;
    // Timestamp of when the rewards finish
    uint public poolEndDate;
    // Minimum of last updated time and reward finish time
    uint public updatedAt;
    // Reward to be paid out per second
    uint public rewardRate;
    // Sum of (reward rate * dt * 1e18 / total supply)
    uint public rewardPerTokenStored;
    // User address => rewardPerTokenStored
    mapping(address => uint) public userRewardPerTokenPaid;
    // User address => rewards to be claimed
    mapping(address => uint) public rewards;
    // Total staked
    uint public totalSupply;
    // User address => staked amount
    mapping(address => uint) public balanceOf;
}
The constructor takes two arguments, _stakingToken and _rewardToken, which are addresses of two ERC20 tokens. The owner variable is set to the address of the contract deployer, which is obtained from the msg.sender global variable.

constructor(address _stakingToken, address _rewardToken) {
    owner = msg.sender;
    stakingToken = IERC20(_stakingToken);
    rewardsToken = IERC20(_rewardToken);
}
The updateReward modifier updates the reward information for a given account before executing a function. This modifier updates the rewardPerTokenStored and updatedAt variables, which are used to calculate the rewards earned by an account. If the account is not the zero address, the modifier also updates the rewards and userRewardPerTokenPaid variables for that account.

The lastTimeRewardApplicable function returns the minimum of the current block timestamp and the end date of the staking pool. This function is used to calculate the rewards earned by an account.

The rewardPerToken function calculates the reward per token earned by an account. If the total supply of tokens is zero, the function returns the stored reward per token.

modifier updateReward(address _account) {
    rewardPerTokenStored = rewardPerToken();
    updatedAt = lastTimeRewardApplicable();
    if (_account != address(0)) {
        rewards[_account] = earned(_account);
        userRewardPerTokenPaid[_account] = rewardPerTokenStored;
    }
    _;
}
The lastTimeRewardApplicable() function returns the minimum value between the pool end date and the current block timestamp.

Next, we will create a rewardPerToken()Function. The function first checks if the total supply of tokens in the pool is zero. If it is, then it returns the stored reward per token value. Otherwise, it calculates the new reward per token value by adding the product of the reward rate, the time since the last update, and 1e18 (a scaling factor to convert to the token's decimals) divided by the total supply to the stored reward per token value.

function rewardPerToken() public view returns (uint) {
  if (totalSupply == 0) {
    return rewardPerTokenStored;
  }
  return rewardPerTokenStored + (rewardRate * (lastTimeRewardApplicable() - updatedAt) * 1e18) / totalSupply;
}
Then we will start to write the staking (Deposit) function. The function takes in a single parameter _amount, which represents the amount of tokens to be staked. The function first checks that the _amount is greater than zero, and if it is not, it throws an error message.

Write on Medium
If the _amount is greater than zero, the function then transfers the _amount tokens from the sender's address to the contract's address using the transferFrom function of the stakingToken contract. This ensures that the contract has control over the tokens that are being staked. The function then updates the balance of the sender's address by adding the _amount to the balanceOf mapping, which keeps track of the balance of each address in the staking pool. The totalSupply variable is also updated by adding the _amount to it, which keeps track of the total number of tokens staked in the pool.

function stake(uint _amount) external updateReward(msg.sender) {
    require(_amount > 0, "amount = 0");
    stakingToken.transferFrom(msg.sender, address(this), _amount);
    balanceOf[msg.sender] += _amount;
    totalSupply += _amount;
}
In the next part, We will write the basic withdraw function. The function takes in a single parameter _amount, which represents the amount of tokens to be withdrawn. The function first checks that the _amount is greater than zero, and if it is not, it throws an error message.

If the _amount is greater than zero, the function then subtracts the _amount from the balanceOf mapping for the sender's address, which keeps track of the balance of each address in the staking pool. The totalSupply variable is also updated by subtracting the _amount from it, which keeps track of the total number of tokens staked in the pool.

Finally, the function transfers the _amount of tokens from the contract's address to the sender's address using the transfer function of the stakingToken contract. This ensures that the user receives the tokens they are withdrawing.

function withdraw(uint _amount) external updateReward(msg.sender) {
    require(_amount > 0, "amount = 0");
    balanceOf[msg.sender] -= _amount;
    totalSupply -= _amount;
    stakingToken.transfer(msg.sender, _amount);
}
Now let’s create an earned function.This function takes in an _account address as input and returns the amount of rewards that the account has earned.

The function first calculates the amount of rewards earned based on the balance of the account and the difference between the current reward per token and the reward per token that the user has already been paid. The reward per token is calculated by dividing the total rewards by the total supply of tokens. The difference between the current reward per token and the user’s reward per token paid is then multiplied by the user’s balance and divided by 1e18, which is a scaling factor used to convert the result to the correct decimal places.

The function then adds the amount of rewards that the account has already received to the calculated amount of rewards earned. The rewards are stored in the rewards mapping, which maps addresses to the amount of rewards they have earned.

function earned(address _account) public view returns (uint) {
    return
        ((balanceOf[_account] *
            (rewardPerToken() - userRewardPerTokenPaid[_account])) / 1e18) +
        rewards[_account];
}
Next, We will create a function for staker to claim their reward. The function first retrieves the reward for the caller from the rewards mapping and stores it in a local variable called reward. If the reward is greater than zero, the function sets the reward for the caller to zero and transfers the reward tokens to the caller's address using the transfer() function of the rewardsToken contract.

function getReward() external updateReward(msg.sender) {
    uint reward = rewards[msg.sender];
    if (reward > 0) {
        rewards[msg.sender] = 0;
        rewardsToken.transfer(msg.sender, reward);
    }
}
We will also need a function to set the duration of the function. First, we take _duration as an argument. then we need to assert that the reward duration is finished first.

function setRewardsDuration(uint _duration) external onlyOwner {
    require(poolEndDate < block.timestamp, "reward duration not finished");
    poolDuration = _duration;
}
function _min(uint x, uint y) private pure returns (uint) {
    return x <= y ? x : y;
}
This function is called notifyRewardAmount and it takes in a single parameter _amount which is the amount of rewards to be distributed to stakers. The function first checks if the current block timestamp is greater than or equal to the poolEndDate. If it is, then the rewardRate is set to _amount divide by poolDuration. If not, it calculates the remaining rewards by subtracting the current block timestamp from the poolEndDate and multiplying it by the current rewardRate. The new rewardRate is then calculated by adding the _amount to the remaining rewards and dividing it by poolDuration.

The function then checks if the rewardRate is greater than zero and if the reward amount is less than or equal to the balance of the contract's rewardsToken balance. If these conditions are not met, the function will revert.

Finally, the poolEndDate is updated to the current block timestamp plus the poolDuration, and the updatedAt timestamp is also updated to the current block timestamp.

In conclusion. Thank you for the time to read our blog. These are the basic functionality for staking contracts. If you need to modify or want to update the features based on your project use case, Please don’t hesitate to write us an email at xbasefinance@gmail.com
