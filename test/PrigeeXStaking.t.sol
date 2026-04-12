// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/PrigeeX.sol";
import "../src/PrigeeXStaking.sol";

contract PrigeeXStakingTest is Test {
    using SafeERC20 for IERC20;

    PrigeeX public token;
    PrigeeXStaking public staking;

    address public owner;
    address public alice;
    address public bob;

    uint256 constant INITIAL_SUPPLY = 1_000_000 ether;
    uint256 constant STAKE_AMOUNT = 1000 ether;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 newRate);
    event RewardsFunded(address indexed funder, uint256 amount);

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        token = new PrigeeX(INITIAL_SUPPLY);
        // Use PGX as both staking and reward token
        staking = new PrigeeXStaking(address(token), address(token));

        IERC20(address(token)).safeTransfer(alice, 10_000 ether);
        IERC20(address(token)).safeTransfer(bob, 10_000 ether);
    }

    // ========== INITIALIZATION TESTS ==========

    function test_InitialState() public view {
        assertEq(address(staking.stakingToken()), address(token));
        assertEq(address(staking.rewardToken()), address(token));
        assertEq(staking.totalStaked(), 0);
        assertEq(staking.rewardRate(), 0);
        assertEq(staking.rewardBalance(), 0);
        assertEq(staking.rewardPerTokenStored(), 0);
        assertEq(staking.owner(), owner);
    }

    // ========== STAKE TESTS ==========

    function test_Stake() public {
        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);

        vm.expectEmit(true, false, false, true);
        emit Staked(alice, STAKE_AMOUNT);

        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        assertEq(staking.balanceOf(alice), STAKE_AMOUNT);
        assertEq(staking.getStake(alice), STAKE_AMOUNT);
        assertEq(staking.totalStaked(), STAKE_AMOUNT);
        assertEq(token.balanceOf(address(staking)), STAKE_AMOUNT);
    }

    function test_Stake_RevertZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(PrigeeXStaking.ZeroAmount.selector);
        staking.stake(0);
    }

    function test_Stake_RevertInsufficientBalance() public {
        vm.startPrank(alice);
        token.approve(address(staking), 100_000 ether);
        vm.expectRevert();
        staking.stake(100_000 ether);
        vm.stopPrank();
    }

    function test_Stake_MultipleUsers() public {
        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(staking), STAKE_AMOUNT * 2);
        staking.stake(STAKE_AMOUNT * 2);
        vm.stopPrank();

        assertEq(staking.balanceOf(alice), STAKE_AMOUNT);
        assertEq(staking.balanceOf(bob), STAKE_AMOUNT * 2);
        assertEq(staking.totalStaked(), STAKE_AMOUNT * 3);
    }

    // ========== WITHDRAW TESTS ==========

    function test_Withdraw() public {
        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);

        uint256 withdrawAmount = STAKE_AMOUNT / 2;

        vm.expectEmit(true, false, false, true);
        emit Withdrawn(alice, withdrawAmount);

        staking.withdraw(withdrawAmount);
        vm.stopPrank();

        assertEq(staking.balanceOf(alice), STAKE_AMOUNT - withdrawAmount);
        assertEq(staking.totalStaked(), STAKE_AMOUNT - withdrawAmount);
        assertEq(token.balanceOf(alice), 10_000 ether - STAKE_AMOUNT + withdrawAmount);
    }

    function test_Withdraw_Full() public {
        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        staking.withdraw(STAKE_AMOUNT);
        vm.stopPrank();

        assertEq(staking.balanceOf(alice), 0);
        assertEq(staking.totalStaked(), 0);
        assertEq(token.balanceOf(alice), 10_000 ether);
    }

    function test_Withdraw_RevertZeroAmount() public {
        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);

        vm.expectRevert(PrigeeXStaking.ZeroAmount.selector);
        staking.withdraw(0);
        vm.stopPrank();
    }

    function test_Withdraw_RevertInsufficientStakedBalance() public {
        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);

        vm.expectRevert(PrigeeXStaking.InsufficientStakedBalance.selector);
        staking.withdraw(STAKE_AMOUNT + 1);
        vm.stopPrank();
    }

    // ========== CRITICAL: ACCUMULATOR PATTERN TESTS ==========

    /// @notice CRITICAL TEST: Multiple stakes should NOT lose rewards
    /// @dev This proves the accumulator pattern works correctly
    function test_MultipleStakes_AccumulateRewardsCorrectly() public {
        uint256 rewardRate = 10 ether; // 10 PGX per second
        staking.setRewardRate(rewardRate);

        // Fund enough rewards: 10 PGX/s * 200s = 2000 PGX
        uint256 rewardFund = 5000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        // Alice stakes 1000 PGX at current time
        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // Wait 100 seconds from NOW
        vm.warp(block.timestamp + 100);

        // Alice's earned rewards: balance * (rpt - userRptPaid) / 1e18 + rewards
        // = 1000 * (10 * 100 * 1e18 / 1000) / 1e18 + 0 = 1000 PGX
        uint256 earnedAfter100s = staking.earned(alice);
        assertEq(earnedAfter100s, 1000 ether, "Rewards after 100s should be 1000 PGX");

        // Alice stakes 500 MORE PGX at current time (should NOT lose previous rewards!)
        vm.startPrank(alice);
        token.approve(address(staking), 500 ether);
        staking.stake(500 ether);
        vm.stopPrank();

        // Wait another 100 seconds from NOW
        vm.warp(block.timestamp + 100);

        // Total earned should be:
        // Period 1 (0-100s): 1000 PGX (saved in rewards mapping)
        // Period 2 (100-200s): 1500 balance * 10 rate * 100s / 1500 total = 1000 PGX
        // Total: 2000 PGX (with tiny rounding)
        uint256 totalEarned = staking.earned(alice);
        assertGe(totalEarned, 1999 ether, "Total earned should be ~2000 PGX (NOT just 1000)");
        assertLe(totalEarned, 2000 ether, "Total earned should not exceed 2000 PGX");
    }

    /// @notice CRITICAL TEST: Multiple users should get fair reward distribution
    function test_MultipleUsers_FairRewardDistribution() public {
        uint256 rewardRate = 10 ether;
        staking.setRewardRate(rewardRate);

        uint256 rewardFund = 10_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        // Alice stakes 1000 PGX
        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // Wait 100 seconds
        vm.warp(block.timestamp + 100);

        // Bob stakes 1000 PGX
        vm.startPrank(bob);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // Alice's earned before Bob joined: 1000 * (10 * 100 * 1e18 / 1000) / 1e18 = 1000 PGX
        uint256 aliceEarned = staking.earned(alice);
        assertGt(aliceEarned, 0, "Alice should have earned rewards before Bob joined");

        // Wait another 100 seconds (both staked)
        vm.warp(block.timestamp + 100);

        // Both should have earned more rewards during period 2
        // Period 2: 2000 total staked, 10 rate, 100s
        // Each gets: 1000 * (10 * 100 * 1e18 / 2000) / 1e18 = 500 PGX each
        uint256 aliceTotal = staking.earned(alice);
        uint256 bobTotal = staking.earned(bob);

        // Alice: 1000 (period 1) + 500 (period 2) = 1500 PGX
        // Bob: 500 PGX (period 2 only)
        assertGt(aliceTotal, bobTotal, "Alice should have more rewards (staked longer)");
    }

    /// @notice CRITICAL TEST: Withdraw then stake again should not lose rewards
    function test_WithdrawAndRestake_AccumulateRewardsCorrectly() public {
        uint256 rewardRate = 10 ether;
        staking.setRewardRate(rewardRate);

        uint256 rewardFund = 5000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        // Alice stakes 1000 PGX
        vm.startPrank(alice);
        token.approve(address(staking), 2000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // Wait 100 seconds
        vm.warp(block.timestamp + 100);

        uint256 earnedBefore = staking.earned(alice);
        assertEq(earnedBefore, 1000 ether, "Should earn 1000 PGX in first 100s");

        // Alice withdraws 500 PGX
        vm.prank(alice);
        staking.withdraw(500 ether);

        // Wait another 100 seconds
        vm.warp(block.timestamp + 100);

        // Alice should have earned rewards from both periods
        // Period 1: 1000 PGX (1000 stake, 100s, 1000 total)
        // Period 2: 500 * (10 * 100 * 1e18 / 500) / 1e18 = 1000 PGX
        // Total: 2000 PGX
        uint256 earnedAfter = staking.earned(alice);
        assertEq(earnedAfter, 2000 ether, "Should earn rewards from both periods");
    }

    // ========== CLAIM REWARDS TESTS ==========

    function test_ClaimRewards() public {
        uint256 rewardRate = 1 ether; // 1 PGX per second
        staking.setRewardRate(rewardRate);

        // Fund reward pool
        uint256 rewardFund = 1000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        // Alice stakes
        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        // Wait 100 seconds
        vm.warp(block.timestamp + 100);

        uint256 expectedRewards = staking.earned(alice);
        assertGt(expectedRewards, 0);

        uint256 balanceBefore = token.balanceOf(alice);

        // Claim rewards
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit RewardsClaimed(alice, expectedRewards);
        staking.claimRewards();

        assertEq(token.balanceOf(alice), balanceBefore + expectedRewards);
        assertEq(staking.rewards(alice), 0); // Rewards mapping should be zeroed
        assertEq(staking.rewardBalance(), rewardFund - expectedRewards);
    }

    function test_ClaimRewards_RevertZeroRewards() public {
        vm.prank(alice);
        vm.expectRevert(PrigeeXStaking.ZeroRewards.selector);
        staking.claimRewards();
    }

    function test_ClaimRewards_RevertInsufficientRewardBalance() public {
        // Set high reward rate but don't fund
        uint256 rewardRate = 100 ether;
        staking.setRewardRate(rewardRate);

        // Alice stakes
        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 1000);

        // Try to claim when pool not funded
        vm.prank(alice);
        vm.expectRevert(PrigeeXStaking.InsufficientRewardBalance.selector);
        staking.claimRewards();
    }

    function test_ClaimRewards_MultipleClaims() public {
        uint256 rewardRate = 1 ether;
        staking.setRewardRate(rewardRate);

        uint256 rewardFund = 2000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        // Alice stakes
        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        // First claim after 100s
        vm.warp(block.timestamp + 100);
        uint256 firstReward = staking.earned(alice);
        vm.prank(alice);
        staking.claimRewards();
        assertGt(firstReward, 0);

        // Second claim after another 100s
        vm.warp(block.timestamp + 100);
        uint256 secondReward = staking.earned(alice);
        vm.prank(alice);
        staking.claimRewards();

        // Both rewards should be equal (same duration, same stake)
        assertEq(firstReward, secondReward, "Multiple claims should give equal rewards for equal periods");
    }

    // ========== FUND REWARDS TESTS ==========

    function test_FundRewards() public {
        uint256 fundAmount = 1000 ether;
        token.approve(address(staking), fundAmount);

        vm.expectEmit(true, false, false, true);
        emit RewardsFunded(owner, fundAmount);

        staking.fundRewards(fundAmount);

        assertEq(staking.rewardBalance(), fundAmount);
        assertEq(token.balanceOf(address(staking)), fundAmount);
    }

    function test_FundRewards_RevertZeroAmount() public {
        vm.expectRevert(PrigeeXStaking.ZeroAmount.selector);
        staking.fundRewards(0);
    }

    function test_FundRewards_MultipleFunds() public {
        token.approve(address(staking), 3000 ether);
        staking.fundRewards(1000 ether);
        staking.fundRewards(2000 ether);

        assertEq(staking.rewardBalance(), 3000 ether);
    }

    function test_FundRewards_AnyoneCanFund() public {
        IERC20(address(token)).safeTransfer(alice, 5000 ether);
        vm.startPrank(alice);
        token.approve(address(staking), 500 ether);
        staking.fundRewards(500 ether);
        vm.stopPrank();

        assertEq(staking.rewardBalance(), 500 ether);
    }

    // ========== EMERGENCY WITHDRAW TESTS ==========

    function test_EmergencyWithdraw() public {
        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);

        vm.expectEmit(true, false, false, true);
        emit EmergencyWithdraw(alice, STAKE_AMOUNT);

        staking.emergencyWithdraw();
        vm.stopPrank();

        assertEq(staking.balanceOf(alice), 0);
        assertEq(staking.totalStaked(), 0);
        assertEq(token.balanceOf(alice), 10_000 ether);
    }

    function test_EmergencyWithdraw_RevertZeroBalance() public {
        vm.prank(alice);
        vm.expectRevert(PrigeeXStaking.ZeroAmount.selector);
        staking.emergencyWithdraw();
    }

    function test_EmergencyWithdraw_ForfeitsRewards() public {
        uint256 rewardRate = 1 ether;
        staking.setRewardRate(rewardRate);
        token.approve(address(staking), 1000 ether);
        staking.fundRewards(1000 ether);

        // Alice stakes
        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        // Time passes, rewards accumulate
        vm.warp(block.timestamp + 100);
        uint256 pendingBefore = staking.earned(alice);
        assertGt(pendingBefore, 0);

        // Emergency withdraw
        vm.prank(alice);
        staking.emergencyWithdraw();

        // Rewards should be forfeited (zeroed out)
        assertEq(staking.rewards(alice), 0);
        assertEq(staking.balanceOf(alice), 0);
    }

    // ========== REWARD RATE TESTS ==========

    function test_SetRewardRate() public {
        uint256 newRate = 1 ether;

        vm.expectEmit(false, false, false, true);
        emit RewardRateUpdated(newRate);

        staking.setRewardRate(newRate);

        assertEq(staking.rewardRate(), newRate);
        assertEq(staking.periodFinish(), block.timestamp + 365 days);
    }

    function test_SetRewardRate_RevertNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        staking.setRewardRate(1 ether);
    }

    // ========== REWARD CALCULATION TESTS ==========

    function test_RewardPerToken_NoStakers() public view {
        assertEq(staking.rewardPerToken(), 0);
    }

    function test_RewardPerToken_IncreasesOverTime() public {
        uint256 rewardRate = 1 ether;
        staking.setRewardRate(rewardRate);

        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        // Wait for rewards to accrue
        vm.warp(block.timestamp + 100);

        uint256 rptAfter = staking.rewardPerToken();
        assertGt(rptAfter, 0, "rewardPerToken should be > 0 after time passes");
    }

    function test_Earned_NoRewardsForZeroStake() public view {
        assertEq(staking.earned(alice), 0);
    }

    function test_Earned_CalculatesCorrectly() public {
        uint256 rewardRate = 1 ether;
        staking.setRewardRate(rewardRate);

        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        // Wait 100 seconds
        vm.warp(block.timestamp + 100);

        // Expected: balanceOf * (rewardPerToken - userRewardPerTokenPaid) / 1e18 + rewards
        // = 1000 * (1 * 100 * 1e18 / 1000) / 1e18 + 0
        // = 1000 * 100 / 1000
        // = 100
        uint256 earned = staking.earned(alice);
        assertEq(earned, 100 ether, "Should earn 100 PGX in 100 seconds");
    }

    function test_LastTimeRewardApplicable_BeforePeriodSet() public view {
        // Before setting reward rate, periodFinish is 0
        // lastTimeRewardApplicable returns min(block.timestamp, 0) = 0
        assertEq(staking.lastTimeRewardApplicable(), 0);
    }

    function test_LastTimeRewardApplicable_AfterPeriodFinish() public {
        staking.setRewardRate(1 ether);
        uint256 endTime = staking.periodFinish();

        // Warp past period finish
        vm.warp(endTime + 100);

        // Should return periodFinish, not block.timestamp
        uint256 lastTime = staking.lastTimeRewardApplicable();
        assertEq(lastTime, endTime);
    }

    function test_RewardPerToken_StopsAfterPeriodFinish() public {
        staking.setRewardRate(1 ether);
        uint256 endTime = staking.periodFinish();

        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        // Check rewardPerToken at period finish
        vm.warp(endTime);
        uint256 rptAtFinish = staking.rewardPerToken();

        // Check rewardPerToken after period finish
        vm.warp(endTime + 100);
        uint256 rptAfter = staking.rewardPerToken();

        // Should be the same (no more rewards after period ends)
        assertEq(rptAtFinish, rptAfter, "rewardPerToken should not increase after periodFinish");
    }

    // ========== REWARD BALANCE VIEW TESTS ==========

    function test_GetRewardBalance() public {
        assertEq(staking.getRewardBalance(), 0);

        token.approve(address(staking), 500 ether);
        staking.fundRewards(500 ether);

        assertEq(staking.getRewardBalance(), 500 ether);
    }

    // ========== FUZZ TESTS ==========

    function testFuzz_Stake(uint256 amount) public {
        amount = bound(amount, 1, 10_000 ether);

        vm.startPrank(alice);
        token.approve(address(staking), amount);
        staking.stake(amount);
        vm.stopPrank();

        assertEq(staking.balanceOf(alice), amount);
        assertEq(staking.totalStaked(), amount);
    }

    function testFuzz_StakeAndWithdraw(uint256 stakeAmount, uint256 withdrawAmount) public {
        stakeAmount = bound(stakeAmount, 1, 10_000 ether);
        withdrawAmount = bound(withdrawAmount, 1, stakeAmount);

        vm.startPrank(alice);
        token.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount);
        staking.withdraw(withdrawAmount);
        vm.stopPrank();

        assertEq(staking.balanceOf(alice), stakeAmount - withdrawAmount);
    }

    function testFuzz_EarnedRewards(uint256 stakeAmount, uint256 duration) public {
        stakeAmount = bound(stakeAmount, 1 ether, 10_000 ether);
        duration = bound(duration, 100, 10000);

        uint256 rewardRate = 1 ether;
        staking.setRewardRate(rewardRate);

        uint256 maxRewards = rewardRate * duration;
        uint256 fundAmount = maxRewards * 2;
        token.approve(address(staking), fundAmount);
        staking.fundRewards(fundAmount);

        vm.startPrank(alice);
        token.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + duration);

        uint256 earned = staking.earned(alice);
        // Should be approximately: stakeAmount * rewardRate * duration / totalStaked
        // With single staker: stakeAmount = totalStaked, so: rewardRate * duration
        uint256 expectedMin = rewardRate * duration * 99 / 100; // 1% tolerance for rounding
        uint256 expectedMax = rewardRate * duration * 101 / 100;
        assertGe(earned, expectedMin);
        assertLe(earned, expectedMax);
    }
}
