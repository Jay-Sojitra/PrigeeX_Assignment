# PrigeeX DEX Project - Complete Explanation

## Project Overview

This project implements a basic DEX staking system with two smart contracts:
1. **PrigeeX (PGX)** - An ERC-20 token with admin controls
2. **PrigeeXStaking** - A staking contract for PGX tokens

---

## Deployment Status: SUCCESS

### Sepolia Testnet Deployment

| Item | Status | Details |
|------|--------|---------|
| PrigeeX Token | Deployed | `0x828B8fAF6c38eB666dFA8c1F22b106ca1FCecf0c` |
| PrigeeXStaking | Deployed | `0xDD8A20b1ABbD84a52d02Dc623E756E880FB13b6b` |
| Token Verification | Verified | [Etherscan](https://sepolia.etherscan.io/address/0x828b8faf6c38eb666dfa8c1f22b106ca1fcecf0c) |
| Staking Verification | Verified | [Etherscan](https://sepolia.etherscan.io/address/0xdd8a20b1abbd84a52d02dc623e756e880fb13b6b) |
| Network | Sepolia | Chain ID: 11155111 |
| Block | 10638998 | Both contracts deployed in same block |
| Gas Used | 2,237,495 | Total for both contracts |
| Cost | ~0.0000096 ETH | At 0.004274244 gwei gas price |

---

## Contract #1: PrigeeX Token (PGX)

### File: `src/PrigeeX.sol`

### Purpose
A standard ERC-20 token with additional owner-controlled minting and burning capabilities.

### Inheritance
```
PrigeeX
├── ERC20 (OpenZeppelin)
│   └── Standard token functionality (transfer, approve, balanceOf, etc.)
└── Ownable (OpenZeppelin)
    └── Owner-only access control
```

### Key Features

| Feature | Description |
|---------|-------------|
| Name | "PrigeeX" |
| Symbol | "PGX" |
| Decimals | 18 (standard) |
| Initial Supply | 1,000,000 PGX (configurable) |
| Mintable | Yes (owner only) |
| Burnable | Yes (owner only) |

### Functions Explained

#### Constructor
```solidity
constructor(uint256 initialSupply) ERC20("PrigeeX", "PGX") Ownable(msg.sender)
```
- Sets token name and symbol
- Transfers ownership to deployer
- Mints `initialSupply` tokens to deployer

#### mint(address to, uint256 amount)
```solidity
function mint(address to, uint256 amount) external onlyOwner
```
- **Access**: Owner only
- **Purpose**: Create new tokens and send to any address
- **Use case**: Reward distribution, liquidity provision

#### burn(address from, uint256 amount)
```solidity
function burn(address from, uint256 amount) external onlyOwner
```
- **Access**: Owner only
- **Purpose**: Destroy tokens from any address
- **Use case**: Token supply management, penalties

---

## Contract #2: PrigeeXStaking

### File: `src/PrigeeXStaking.sol`

### Purpose
Allow users to stake PGX tokens with placeholder reward logic for future implementation.

### Inheritance
```
PrigeeXStaking
├── Ownable (OpenZeppelin)
│   └── Owner-only admin functions
└── ReentrancyGuard (OpenZeppelin)
    └── Protection against reentrancy attacks
```

### Security Features

| Feature | Implementation |
|---------|----------------|
| Reentrancy Protection | `nonReentrant` modifier on all state-changing functions |
| Safe Transfers | Uses `SafeERC20` library for token transfers |
| Custom Errors | Gas-efficient error handling |
| Input Validation | Zero amount checks |

### State Variables

```solidity
IERC20 public immutable stakingToken;         // PGX token address (immutable)
IERC20 public immutable rewardToken;          // Reward token address (can be PGX)
mapping(address => uint256) balanceOf;         // User -> staked amount
uint256 public totalStaked;                    // Total tokens in contract

// Reward Distribution (Accumulator Pattern - same as Aave/SushiSwap)
uint256 public rewardRate;                     // Rewards per second for ALL stakers
uint256 public periodFinish;                   // When current reward period ends
uint256 public rewardPerTokenStored;           // Global accumulator: rewards per token
uint256 public lastUpdateTime;                 // Last time accumulator was updated
uint256 public rewardBalance;                  // Available rewards in contract
mapping(address => uint256) userRewardPerTokenPaid;  // User's snapshot of accumulator
mapping(address => uint256) rewards;           // User's pending claimable rewards
```

### Functions Explained

#### stake(uint256 amount)
```solidity
function stake(uint256 amount) external nonReentrant updateReward(msg.sender)
```
- **Flow**:
  1. `updateReward` modifier runs FIRST (saves pending rewards)
  2. Validates amount > 0
  3. Updates user's staked balance
  4. Updates total staked
  5. Transfers tokens from user to contract
  6. Emits `Staked` event
- **Requirements**: User must approve contract first
- **Key**: Rewards are saved BEFORE balance changes (no reward loss)

#### withdraw(uint256 amount)
```solidity
function withdraw(uint256 amount) external nonReentrant updateReward(msg.sender)
```
- **Flow**:
  1. `updateReward` modifier runs FIRST (saves pending rewards)
  2. Validates amount > 0
  3. Checks user has enough staked
  4. Reduces user's staked balance
  5. Updates total staked
  6. Transfers tokens back to user
  7. Emits `Withdrawn` event
- **Note**: Does NOT auto-claim rewards (users claim separately for flexibility)
- **Key**: Rewards are saved BEFORE balance changes (no reward loss)

#### claimRewards()
```solidity
function claimRewards() external nonReentrant updateReward(msg.sender)
```
- **Purpose**: Claim pending rewards for the caller
- **Flow**:
  1. `updateReward` modifier runs FIRST (calculates latest rewards)
  2. Reads rewards from `rewards[msg.sender]` mapping
  3. Validates rewards > 0
  4. Checks sufficient reward balance in contract
  5. Decrements reward balance
  6. Zeros out user's rewards mapping
  7. Transfers reward tokens to user
  8. Emits `RewardsClaimed` event
- **Requirements**: Must have pending rewards AND funded reward pool

#### fundRewards(uint256 amount)
```solidity
function fundRewards(uint256 amount) external nonReentrant
```
- **Purpose**: Anyone can fund the reward pool
- **Flow**:
  1. Validates amount > 0
  2. Updates reward balance
  3. Transfers reward tokens from funder to contract
  4. Emits `RewardsFunded` event
- **Requirements**: Funder must approve tokens first
- **Note**: Can be called by anyone (not just owner) for flexibility

#### emergencyWithdraw()
```solidity
function emergencyWithdraw() external nonReentrant updateReward(msg.sender)
```
- **Purpose**: Withdraw ALL staked tokens immediately
- **Flow**:
  1. `updateReward` modifier runs FIRST
  2. Gets user's full staked balance
  3. Zeros out pending rewards (forfeited)
  4. Zeros out user's staked balance
  5. Updates total staked
  6. Transfers staked tokens back to user
  7. Emits `EmergencyWithdraw` event
- **Trade-off**: Forfeits any pending rewards
- **Use case**: Emergency situations, contract migration
- **Standard Practice**: Returns only user's staked principal (no rewards)

#### getStake(address account)
```solidity
function getStake(address account) external view returns (uint256)
```
- **Purpose**: View function to check staked balance
- **Gas**: Free (view function)

#### setRewardRate(uint256 _rewardRate)
```solidity
function setRewardRate(uint256 _rewardRate) external onlyOwner updateReward(address(0))
```
- **Access**: Owner only
- **Purpose**: Configure reward rate (rewards per second)
- **CRITICAL**: Calls `updateReward(address(0))` BEFORE changing rate to checkpoint accumulator
- **Flow**:
  1. Updates global accumulator with OLD rate
  2. Updates lastUpdateTime
  3. Changes rewardRate to new value
  4. Sets periodFinish to 1 year from now
  5. Emits `RewardRateUpdated` event
- **Why checkpoint?**: Prevents retroactive reward recalculation when rate changes

#### pendingRewards(address account)
```solidity
function pendingRewards(address account) public view returns (uint256)
```
- **Purpose**: Calculate total earned rewards (including unclaimed)
- **Formula**: `(balanceOf × (rewardPerToken - userRewardPerTokenPaid)) / 1e18 + rewards`
- **Note**: This is alias for `earned()` - returns total accumulated rewards

#### earned(address account)
```solidity
function earned(address account) public view returns (uint256)
```
- **Purpose**: Calculate earned rewards using accumulator pattern
- **Formula**: `(balance × (currentAccumulator - userSnapshot)) / 1e18 + savedRewards`
- **Example**: If user staked 1000 tokens and accumulator increased from 0 to 0.5, they earned 500 tokens

#### rewardPerToken()
```solidity
function rewardPerToken() public view returns (uint256)
```
- **Purpose**: Global accumulator - tracks rewards earned per staked token
- **Formula**: `rewardPerTokenStored + (rewardRate × timeElapsed × 1e18) / totalStaked`
- **Key**: This value only INCREASES over time, never resets
- **Used By**: All reward calculations

#### updateReward(address account) [Modifier]
```solidity
modifier updateReward(address account)
```
- **Purpose**: Save pending rewards before balance changes
- **Flow**:
  1. Updates global `rewardPerTokenStored` accumulator
  2. Updates `lastUpdateTime`
  3. Calculates user's earned rewards
  4. Saves to `rewards[account]` mapping
  5. Updates `userRewardPerTokenPaid[account]` snapshot
- **Critical**: This prevents reward loss on multiple stakes/withdrawals

#### getRewardBalance()
```solidity
function getRewardBalance() external view returns (uint256)
```
- **Purpose**: View available reward tokens in contract
- **Gas**: Free (view function)

### Events

| Event | When Emitted |
|-------|--------------|
| `Staked(address user, uint256 amount)` | User stakes tokens |
| `Withdrawn(address user, uint256 amount)` | User withdraws tokens |
| `RewardsClaimed(address user, uint256 amount)` | User claims rewards |
| `EmergencyWithdraw(address user, uint256 amount)` | User emergency withdraws |
| `RewardRateUpdated(uint256 newRate)` | Owner changes reward rate |
| `RewardsFunded(address funder, uint256 amount)` | Someone funds reward pool |

### Custom Errors

| Error | When Thrown |
|-------|-------------|
| `ZeroAmount()` | Stake/withdraw/fund amount is 0 |
| `InsufficientStakedBalance()` | Withdraw more than staked |
| `ZeroRewards()` | No pending rewards to claim |
| `InsufficientRewardBalance()` | Contract has insufficient reward tokens |

---

## Test Coverage

### Test Results: 80/80 PASSED

```
Ran 11 tests for test/PrigeeX.t.sol:PrigeeXTest
Ran 69 tests for test/PrigeeXStaking.t.sol:PrigeeXStakingTest
```

### Token Tests (PrigeeX.t.sol)

| Test | What It Verifies |
|------|------------------|
| `test_InitialState` | Name, symbol, decimals, supply, owner are correct |
| `test_Transfer` | Standard transfer works, balances update, event emits |
| `test_TransferFrom` | Approved transfers work correctly |
| `test_Approve` | Approval updates allowance, event emits |
| `test_Mint_OnlyOwner` | Owner can mint new tokens |
| `test_Mint_RevertWhenNotOwner` | Non-owner cannot mint |
| `test_Burn_OnlyOwner` | Owner can burn tokens |
| `test_Burn_RevertWhenNotOwner` | Non-owner cannot burn |
| `test_Burn_RevertWhenInsufficientBalance` | Cannot burn more than balance |
| `testFuzz_Transfer` | Fuzz test: random transfer amounts work |
| `testFuzz_Mint` | Fuzz test: random mint amounts work |

### Staking Tests (PrigeeXStaking.t.sol)

| Category | Tests | Description |
|----------|-------|-------------|
| **Initialization** | 1 | Contract setup verification |
| **Basic Staking** | 4 | Stake, zero amount, insufficient balance, multiple users |
| **Basic Withdraw** | 4 | Partial, full, zero amount, insufficient balance |
| **Accumulator Pattern** | 3 | Multiple stakes don't lose rewards, multi-user fair distribution, withdraw+restake preserves rewards |
| **Claim Rewards** | 4 | Basic claim, zero rewards, insufficient balance, multiple claims |
| **Fund Rewards** | 4 | Basic fund, zero amount, multiple funds, anyone can fund |
| **Emergency Withdraw** | 3 | Basic, zero balance, forfeits rewards |
| **Reward Rate** | 2 | Set rate, not owner |
| **⭐ Rate Change Checkpoint** | **3** | **Rate drop preserves past, rate raise doesn't inflate past, multi-user with Bob claiming first** |
| **⭐ Multi-User Scenarios** | **11** | **3 users staggered entry, equal/unequal stakes, partial withdraw + new entry, 4-user complex interleaving, full exit + re-enter, claim midway doesn't affect others** |
| **⭐ Rate Change + Multi-User** | **4** | **Rate increase forward-only, rate decrease preserves past, multiple rapid rate changes, rate=0 stops accrual** |
| **Reward Calculation** | 7 | No stakers, increases over time, calculates correctly, period boundaries |
| **Edge Cases** | 7 | Minimal stake (1 wei), large stake no overflow, zero duration, very large time warp |
| **Fuzz Tests** | 12 | Random stake amounts, withdraw amounts, earn rewards with various inputs |
| **Total** | **69** | **Comprehensive coverage of all scenarios** |

---

## Project Structure

```
dex_assignment/
├── src/
│   ├── PrigeeX.sol           # ERC-20 token contract
│   └── PrigeeXStaking.sol    # Staking contract
├── test/
│   ├── PrigeeX.t.sol         # Token tests (11 tests)
│   └── PrigeeXStaking.t.sol  # Staking tests (18 tests)
├── script/
│   └── Deploy.s.sol          # Deployment script
├── lib/
│   ├── forge-std/            # Foundry testing library
│   └── openzeppelin-contracts/ # OpenZeppelin contracts
├── broadcast/                 # Deployment transaction logs
├── out/                       # Compiled contracts + ABIs
├── foundry.toml              # Foundry configuration
├── .env.example              # Environment variables template
├── README.md                 # Setup and usage guide
└── EXPLANATION.md            # This file
```

---

## How the Staking Flow Works

```
┌─────────────────────────────────────────────────────────────────┐
│                         USER FLOW                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  1. Owner sets reward rate                                       │
│     └── staking.setRewardRate(10 ether) // 10 PGX/s              │
│     └── periodFinish = now + 365 days                            │
│                                                                  │
│  2. Owner/Anyone funds reward pool                               │
│     └── token.approve(stakingContract, 100000)                   │
│     └── staking.fundRewards(100000)                              │
│     └── rewardBalance = 100000                                   │
│                                                                  │
│  3. User stakes tokens                                           │
│     └── token.approve(stakingContract, 1000)                     │
│     └── staking.stake(1000)                                      │
│     └── updateReward saves any pending rewards FIRST             │
│     └── balanceOf[user] = 1000                                   │
│     └── userRewardPerTokenPaid[user] = current accumulator       │
│     └── Event: Staked(user, 1000)                                │
│                                                                  │
│  4. Time passes... (global accumulator increases)                │
│     └── rewardPerTokenStored increases over time                 │
│     └── Each user earns: balance × (current - snapshot)          │
│                                                                  │
│  5. User checks earned rewards                                   │
│     └── staking.earned(user) // Total accumulated                │
│                                                                  │
│  6. User claims rewards (can do multiple times)                  │
│     └── staking.claimRewards()                                   │
│     └── Reward tokens: Contract → User                           │
│     └── rewards[user] = 0 (claimed)                              │
│     └── rewardBalance decreases                                  │
│     └── Event: RewardsClaimed(user, amount)                      │
│                                                                  │
│  7. User can stake MORE without losing rewards!                  │
│     └── staking.stake(500)                                       │
│     └── updateReward saves pending rewards to rewards[user]      │
│     └── balanceOf[user] = 1500                                   │
│     └── Previous rewards SAFE in rewards[user]!                  │
│                                                                  │
│  8. User withdraws staked tokens (principal)                     │
│     └── staking.withdraw(500)                                    │
│     └── balanceOf[user] = 1000                                   │
│     └── Event: Withdrawn(user, 500)                              │
│                                                                  │
│  OR Emergency withdraw (all at once, forfeits rewards)           │
│     └── staking.emergencyWithdraw()                              │
│     └── Returns only staked principal, rewards forfeited         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Security Considerations

### Implemented Protections

1. **Reentrancy Guard**: All external functions that transfer tokens use `nonReentrant`
2. **SafeERC20**: Prevents issues with non-standard ERC20 tokens
3. **Input Validation**: Zero amount checks prevent wasteful transactions
4. **Access Control**: Owner-only functions protected by `onlyOwner`
5. **Immutable Token Address**: Cannot be changed after deployment
6. **Reward Balance Safety**: Claims check available reward balance before transfer
7. **Accumulator Pattern**: Rewards saved BEFORE balance changes (no loss on multiple stakes)

### Reward Distribution Model

**Chosen Approach: Global Accumulator Pattern (Aave/SushiSwap Standard)**

This project uses the **battle-tested accumulator pattern**, which is:
- ✅ Used by Aave ($10B+ TVL), SushiSwap, Curve, Synthetix
- ✅ Gas efficient (O(1) regardless of user count)
- ✅ Accurate reward calculation for all scenarios
- ✅ No reward loss on multiple stakes/withdrawals
- ✅ Fair proportional distribution based on stake amount and time

**How it works:**
1. Global `rewardPerTokenStored` accumulator increases over time
2. Each user has a snapshot (`userRewardPerTokenPaid`) tracking their starting point
3. Rewards = `balance × (currentAccumulator - userSnapshot) + savedRewards`
4. `updateReward` modifier saves pending rewards BEFORE any balance change
5. Owner sets `rewardRate` (total PGX/second for ALL stakers)
6. Owner/anyone funds `rewardBalance` (how long pool can sustain)

**Reward Distribution:**
- Rewards are **proportional to stake amount**
- Example: If Alice stakes 1000 PGX and Bob stakes 2000 PGX
  - Total pool: 100 PGX/second
  - Alice earns: 33.33 PGX/s (33.3% of pool)
  - Bob earns: 66.67 PGX/s (66.7% of pool)

**Alternative approaches considered:**
- Per-user timestamps (❌ Loses rewards on multiple stakes - original bug)
- Auto-minting on claim (❌ Inflationary, complex)
- Equal rewards per user (❌ Unfair, sybil-vulnerable)

### Potential Improvements for Production

1. **Time-locked Admin Functions**: Add timelock for sensitive operations
2. **Pausable**: Add ability to pause staking in emergencies
3. **Slashing**: Add penalties for early withdrawal if needed
4. **Upgradability**: Consider proxy pattern for future updates
5. **Advanced Reward Distribution**: Implement MasterChef-style reward accounting

---

## Verification Checklist

| Item | Status |
|------|--------|
| Token deploys with correct name/symbol | PASS |
| Token initial supply minted to deployer | PASS |
| Only owner can mint/burn | PASS |
| Staking contract links to token | PASS |
| Users can stake tokens | PASS |
| Users can withdraw tokens | PASS |
| Users can claim rewards | PASS |
| Reward pool can be funded | PASS |
| Emergency withdraw works | PASS |
| Emergency withdraw forfeits rewards | PASS |
| Multiple stakes don't lose rewards (accumulator) | PASS |
| Withdraw+restake preserves rewards | PASS |
| Fair proportional reward distribution | PASS |
| Rate change checkpoints before modifying | PASS |
| Rate increase only affects future rewards | PASS |
| Rate decrease preserves past rewards | PASS |
| Multiple rapid rate changes work correctly | PASS |
| Events emit correctly | PASS |
| Access control enforced | PASS |
| Reentrancy protection active | PASS |
| Math.mulDiv prevents overflow | PASS |
| All 80 tests pass | PASS |
| Deployed to Sepolia | PASS |
| Verified on Etherscan | PASS |

---

## Quick Commands Reference

```bash
# Build contracts
forge build

# Run all tests
forge test

# Run tests with gas report
forge test --gas-report

# Run specific test
forge test --match-test test_Stake -vvv

# Deploy to Sepolia
source .env && forge script script/Deploy.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast --verify

# Get ABI
cat out/PrigeeX.sol/PrigeeX.json | jq '.abi'
```

---

## Contract Interaction Examples

### Using Cast (Foundry CLI)

```bash
# Check token balance
cast call 0x828B8fAF6c38eB666dFA8c1F22b106ca1FCecf0c \
  "balanceOf(address)" <your-address> --rpc-url $SEPOLIA_RPC_URL

# Check staked balance
cast call 0xDD8A20b1ABbD84a52d02Dc623E756E880FB13b6b \
  "getStake(address)" <your-address> --rpc-url $SEPOLIA_RPC_URL

# Approve staking contract
cast send 0x828B8fAF6c38eB666dFA8c1F22b106ca1FCecf0c \
  "approve(address,uint256)" 0xDD8A20b1ABbD84a52d02Dc623E756E880FB13b6b 1000000000000000000 \
  --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL

# Stake tokens
cast send 0xDD8A20b1ABbD84a52d02Dc623E756E880FB13b6b \
  "stake(uint256)" 1000000000000000000 \
  --private-key $PRIVATE_KEY --rpc-url $SEPOLIA_RPC_URL
```

---

## Summary

This project successfully implements:

1. **PrigeeX (PGX) Token**: A fully functional ERC-20 token with owner-controlled mint/burn
2. **PrigeeXStaking**: A professional staking contract using the **accumulator pattern** (same as Aave/SushiSwap):
   - Stake/withdraw PGX tokens
   - **Claim rewards** with no loss on multiple stakes
   - **Rate change checkpoint** prevents retroactive reward miscalculation
   - Emergency withdraw (forfeits rewards)
   - Reward rate configuration
   - Owner-funded reward pool
3. **Comprehensive Tests**: 80 tests covering all scenarios including:
   - Multiple stakes without reward loss
   - Withdraw+restake preserving rewards
   - Fair proportional distribution
   - **Rate change correctness** (increase/decrease/multiple changes)
   - **Multi-user scenarios** (3-4 users staggered entry)
   - **Claim order independence** (Bob claiming first doesn't affect Alice)
   - Fuzz testing for edge cases
   - Overflow protection with Math.mulDiv
4. **Sepolia Deployment**: Both contracts deployed and verified on Etherscan
5. **Documentation**: Complete README with setup instructions, frontend integration examples, and quick start guides

All 5 task requirements have been completed successfully.
