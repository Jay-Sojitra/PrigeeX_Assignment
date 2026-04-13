# PrigeeX DEX Assignment

A Foundry-based project featuring the PrigeeX (PGX) ERC-20 token and a staking contract.

## Contracts

### PrigeeX Token (PGX)
- **Standard**: ERC-20
- **Features**: Configurable supply, owner-controlled mint/burn
- **Decimals**: 18

### PrigeeXStaking
- **Features**: Stake/withdraw PGX tokens, claim rewards, emergency withdraw
- **Reward Model**: Owner-funded reward pool (flexible and transparent)
- **Security**: ReentrancyGuard protection

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Sepolia ETH for deployment (get from [Sepolia Faucet](https://sepoliafaucet.com/))

## Installation

```bash
# Clone the repository
git clone <your-repo-url>
cd dex_assignment

# Install dependencies
forge install
```

## Build

```bash
forge build
```

## Test

```bash
# Run all tests
forge test

# Run tests with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/PrigeeX.t.sol -vvv
```

## Deployment

### 1. Set up environment variables

```bash
cp .env.example .env
```

Edit `.env` with your values:
- `SEPOLIA_RPC_URL`: Your Alchemy/Infura Sepolia RPC URL
- `PRIVATE_KEY`: Your deployer wallet private key (without 0x)
- `ETHERSCAN_API_KEY`: For contract verification

### 2. Deploy to Sepolia

```bash
source .env

forge script script/Deploy.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

## Deployed Contract Addresses (Sepolia)

| Contract | Address | Etherscan |
|----------|---------|-----------|
| PrigeeX (PGX) | `0x828B8fAF6c38eB666dFA8c1F22b106ca1FCecf0c` | [View](https://sepolia.etherscan.io/address/0x828b8faf6c38eb666dfa8c1f22b106ca1fcecf0c) |
| PrigeeXStaking | `0xDD8A20b1ABbD84a52d02Dc623E756E880FB13b6b` | [View](https://sepolia.etherscan.io/address/0xdd8a20b1abbd84a52d02dc623e756e880fb13b6b) |

## Frontend Integration

### Getting ABIs

After building, ABIs are located in:
- `out/PrigeeX.sol/PrigeeX.json`
- `out/PrigeeXStaking.sol/PrigeeXStaking.json`

### ethers.js v6 Example

```javascript
import { ethers } from 'ethers';
import PrigeeXABI from './abi/PrigeeX.json';
import StakingABI from './abi/PrigeeXStaking.json';

const provider = new ethers.BrowserProvider(window.ethereum);
const signer = await provider.getSigner();

// Contract addresses (replace with deployed addresses)
const PGX_ADDRESS = '0x...';
const STAKING_ADDRESS = '0x...';

const token = new ethers.Contract(PGX_ADDRESS, PrigeeXABI.abi, signer);
const staking = new ethers.Contract(STAKING_ADDRESS, StakingABI.abi, signer);

// Approve and stake tokens
const stakeAmount = ethers.parseEther('100');
await token.approve(STAKING_ADDRESS, stakeAmount);
await staking.stake(stakeAmount);

// Check staked balance
const stakedBalance = await staking.getStake(await signer.getAddress());
console.log('Staked:', ethers.formatEther(stakedBalance), 'PGX');

// Check pending rewards
const pendingRewards = await staking.pendingRewards(await signer.getAddress());
console.log('Pending Rewards:', ethers.formatEther(pendingRewards), 'PGX');

// Claim rewards
await staking.claimRewards();

// Withdraw tokens
await staking.withdraw(stakeAmount);

// Emergency withdraw (forfeits pending rewards)
await staking.emergencyWithdraw();
```

### viem Example

```typescript
import { createPublicClient, createWalletClient, http, parseEther, formatEther } from 'viem';
import { sepolia } from 'viem/chains';
import PrigeeXABI from './abi/PrigeeX.json';
import StakingABI from './abi/PrigeeXStaking.json';

const PGX_ADDRESS = '0x...' as const;
const STAKING_ADDRESS = '0x...' as const;

const publicClient = createPublicClient({
  chain: sepolia,
  transport: http(),
});

// Read staked balance
const stakedBalance = await publicClient.readContract({
  address: STAKING_ADDRESS,
  abi: StakingABI.abi,
  functionName: 'getStake',
  args: [userAddress],
});

console.log('Staked:', formatEther(stakedBalance), 'PGX');
```

### Event Listeners

```javascript
// Listen for Staked events
staking.on('Staked', (user, amount) => {
  console.log(`${user} staked ${ethers.formatEther(amount)} PGX`);
});

// Listen for Withdrawn events
staking.on('Withdrawn', (user, amount) => {
  console.log(`${user} withdrew ${ethers.formatEther(amount)} PGX`);
});

// Listen for Rewards CLAIMED events
staking.on('RewardsClaimed', (user, amount) => {
  console.log(`${user} claimed ${ethers.formatEther(amount)} PGX rewards`);
});

// Listen for Rewards FUNDED events
staking.on('RewardsFunded', (funder, amount) => {
  console.log(`${funder} funded ${ethers.formatEther(amount)} PGX to reward pool`);
});

// Listen for EmergencyWithdraw events
staking.on('EmergencyWithdraw', (user, amount) => {
  console.log(`${user} emergency withdrew ${ethers.formatEther(amount)} PGX`);
});
```

### Funding Reward Pool (For Admin)

```javascript
// Owner or anyone can fund the reward pool
const rewardAmount = ethers.parseEther('10000'); // 10,000 PGX
await token.approve(STAKING_ADDRESS, rewardAmount);
await staking.fundRewards(rewardAmount);

// Check available reward balance
const rewardBalance = await staking.getRewardBalance();
console.log('Available Rewards:', ethers.formatEther(rewardBalance), 'PGX');
```

## Contract Functions

### PrigeeX Token

| Function | Access | Description |
|----------|--------|-------------|
| `transfer(to, amount)` | Public | Transfer tokens |
| `approve(spender, amount)` | Public | Approve spending |
| `mint(to, amount)` | Owner | Mint new tokens |
| `burn(from, amount)` | Owner | Burn tokens |

### PrigeeXStaking

| Function | Access | Description |
|----------|--------|-------------|
| `stake(amount)` | Public | Stake PGX tokens |
| `withdraw(amount)` | Public | Withdraw staked tokens |
| `claimRewards()` | Public | Claim pending rewards |
| `fundRewards(amount)` | Public | Fund reward pool (requires approval) |
| `emergencyWithdraw()` | Public | Withdraw all (forfeits rewards) |
| `getStake(account)` | View | Get staked balance |
| `pendingRewards(account)` | View | Get pending rewards |
| `earned(account)` | View | Get total earned rewards (including unclaimed) |
| `getRewardBalance()` | View | Get available reward balance |
| `setRewardRate(rate)` | Owner | Set reward rate |

## Quick Start

### For Users

```javascript
// 1. Approve staking contract
await token.approve(STAKING_ADDRESS, ethers.parseEther('1000'));

// 2. Stake tokens
await staking.stake(ethers.parseEther('1000'));

// 3. Wait for rewards to accumulate...

// 4. Check rewards
const rewards = await staking.earned(userAddress);
console.log('You can claim:', ethers.formatEther(rewards), 'PGX');

// 5. Claim rewards
await staking.claimRewards();

// 6. Withdraw staked tokens when needed
await staking.withdraw(ethers.parseEther('500'));
```

### For Admins

```javascript
// 1. Set reward rate (e.g., 10 PGX per second)
await staking.setRewardRate(ethers.parseEther('10'));

// 2. Fund reward pool
await token.approve(STAKING_ADDRESS, ethers.parseEther('100000'));
await staking.fundRewards(ethers.parseEther('100000'));

// Reward distribution is automatic - users claim when ready
```

## License

MIT
