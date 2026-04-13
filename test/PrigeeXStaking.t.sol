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
    address public charlie;
    address public dave;

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
        charlie = makeAddr("charlie");
        dave = makeAddr("dave");

        token = new PrigeeX(INITIAL_SUPPLY);
        // Use PGX as both staking and reward token
        staking = new PrigeeXStaking(address(token), address(token));

        IERC20(address(token)).safeTransfer(alice, 50_000 ether);
        IERC20(address(token)).safeTransfer(bob, 50_000 ether);
        IERC20(address(token)).safeTransfer(charlie, 50_000 ether);
        IERC20(address(token)).safeTransfer(dave, 50_000 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  SECTION 1: INITIALIZATION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_InitialState() public view {
        assertEq(address(staking.stakingToken()), address(token));
        assertEq(address(staking.rewardToken()), address(token));
        assertEq(staking.totalStaked(), 0);
        assertEq(staking.rewardRate(), 0);
        assertEq(staking.rewardBalance(), 0);
        assertEq(staking.rewardPerTokenStored(), 0);
        assertEq(staking.owner(), owner);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  SECTION 2: BASIC STAKING TESTS
    // ═══════════════════════════════════════════════════════════════════════

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

    // ═══════════════════════════════════════════════════════════════════════
    //  SECTION 3: BASIC WITHDRAW TESTS
    // ═══════════════════════════════════════════════════════════════════════

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
        assertEq(token.balanceOf(alice), 50_000 ether - STAKE_AMOUNT + withdrawAmount);
    }

    function test_Withdraw_Full() public {
        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        staking.withdraw(STAKE_AMOUNT);
        vm.stopPrank();

        assertEq(staking.balanceOf(alice), 0);
        assertEq(staking.totalStaked(), 0);
        assertEq(token.balanceOf(alice), 50_000 ether);
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

    // ═══════════════════════════════════════════════════════════════════════
    //  SECTION 4: ACCUMULATOR PATTERN CORRECTNESS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Multiple stakes by same user should NOT lose accumulated rewards
    function test_MultipleStakes_AccumulateRewardsCorrectly() public {
        uint256 rewardRate = 10 ether; // 10 PGX per second
        staking.setRewardRate(rewardRate);

        uint256 rewardFund = 5000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        // Alice stakes 1000 PGX at current time
        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // Wait 100 seconds
        vm.warp(block.timestamp + 100);

        // Alice's earned: 1000 * (10 * 100 * 1e18 / 1000) / 1e18 = 1000 PGX
        uint256 earnedAfter100s = staking.earned(alice);
        assertEq(earnedAfter100s, 1000 ether, "Rewards after 100s should be 1000 PGX");

        // Alice stakes 500 MORE PGX (should NOT lose previous rewards!)
        vm.startPrank(alice);
        token.approve(address(staking), 500 ether);
        staking.stake(500 ether);
        vm.stopPrank();

        // Wait another 100 seconds
        vm.warp(block.timestamp + 100);

        // Period 1: 1000 PGX (saved in rewards mapping)
        // Period 2: 1500 * 10 * 100 / 1500 = 1000 PGX
        // Total: 2000 PGX
        uint256 totalEarned = staking.earned(alice);
        assertGe(totalEarned, 1999 ether, "Total earned should be ~2000 PGX (NOT just 1000)");
        assertLe(totalEarned, 2000 ether, "Total earned should not exceed 2000 PGX");
    }

    /// @notice Two users staking at different times should get proportional rewards
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

        uint256 aliceEarned = staking.earned(alice);
        assertGt(aliceEarned, 0, "Alice should have earned rewards before Bob joined");

        // Wait another 100 seconds
        vm.warp(block.timestamp + 100);

        uint256 aliceTotal = staking.earned(alice);
        uint256 bobTotal = staking.earned(bob);

        // Alice: 1000 (period 1) + 500 (period 2) = 1500 PGX
        // Bob: 500 PGX (period 2 only)
        assertGt(aliceTotal, bobTotal, "Alice should have more rewards (staked longer)");
    }

    /// @notice Withdraw then re-stake should preserve already-earned rewards
    function test_WithdrawAndRestake_AccumulateRewardsCorrectly() public {
        uint256 rewardRate = 10 ether;
        staking.setRewardRate(rewardRate);

        uint256 rewardFund = 5000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        vm.startPrank(alice);
        token.approve(address(staking), 2000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);

        uint256 earnedBefore = staking.earned(alice);
        assertEq(earnedBefore, 1000 ether, "Should earn 1000 PGX in first 100s");

        // Alice withdraws 500 PGX
        vm.prank(alice);
        staking.withdraw(500 ether);

        vm.warp(block.timestamp + 100);

        // Period 1: 1000 PGX (1000 stake, 100s, 1000 total)
        // Period 2: 500 * (10 * 100 * 1e18 / 500) / 1e18 = 1000 PGX
        // Total: 2000 PGX
        uint256 earnedAfter = staking.earned(alice);
        assertEq(earnedAfter, 2000 ether, "Should earn rewards from both periods");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  SECTION 5: CLAIM REWARDS TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_ClaimRewards() public {
        uint256 rewardRate = 1 ether;
        staking.setRewardRate(rewardRate);

        uint256 rewardFund = 1000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);

        uint256 expectedRewards = staking.earned(alice);
        assertGt(expectedRewards, 0);

        uint256 balanceBefore = token.balanceOf(alice);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit RewardsClaimed(alice, expectedRewards);
        staking.claimRewards();

        assertEq(token.balanceOf(alice), balanceBefore + expectedRewards);
        assertEq(staking.rewards(alice), 0);
        assertEq(staking.rewardBalance(), rewardFund - expectedRewards);
    }

    function test_ClaimRewards_RevertZeroRewards() public {
        vm.prank(alice);
        vm.expectRevert(PrigeeXStaking.ZeroRewards.selector);
        staking.claimRewards();
    }

    function test_ClaimRewards_RevertInsufficientRewardBalance() public {
        uint256 rewardRate = 100 ether;
        staking.setRewardRate(rewardRate);

        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 1000);

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

        assertEq(firstReward, secondReward, "Multiple claims should give equal rewards for equal periods");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  SECTION 6: FUND REWARDS TESTS
    // ═══════════════════════════════════════════════════════════════════════

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
        vm.startPrank(alice);
        token.approve(address(staking), 500 ether);
        staking.fundRewards(500 ether);
        vm.stopPrank();

        assertEq(staking.rewardBalance(), 500 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  SECTION 7: EMERGENCY WITHDRAW TESTS
    // ═══════════════════════════════════════════════════════════════════════

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
        assertEq(token.balanceOf(alice), 50_000 ether);
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

        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);
        uint256 pendingBefore = staking.earned(alice);
        assertGt(pendingBefore, 0);

        vm.prank(alice);
        staking.emergencyWithdraw();

        assertEq(staking.rewards(alice), 0);
        assertEq(staking.balanceOf(alice), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  SECTION 8: REWARD RATE BASIC TESTS
    // ═══════════════════════════════════════════════════════════════════════

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

    // ═══════════════════════════════════════════════════════════════════════
    //  SECTION 9: RATE CHANGE CHECKPOINT TESTS
    //  ⚠️  BUG: setRewardRate() does NOT call _updateReward(address(0))
    //       before modifying the rate. This means rewardPerTokenStored is
    //       NOT snapshotted at the old rate, causing retroactive
    //       recalculation of ALL past rewards at the NEW rate.
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice CRITICAL: rate drop retroactively recalculates (BUG DEMONSTRATION)
    /// @dev setRewardRate does not checkpoint → past rewards computed at new rate
    ///      Expected: 1000 PGX (100s × 10/s). Actual: 100 PGX (100s × 1/s).
    function test_SetRewardRate_CheckpointsRewardsBeforeRateChange() public {
        staking.setRewardRate(10 ether);

        uint256 rewardFund = 10_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // 100 seconds at rate=10 → expect 1000 PGX
        vm.warp(block.timestamp + 100);

        // Owner drops rate to 1 PGX/s — should NOT retroactively reduce past rewards
        staking.setRewardRate(1 ether);

        uint256 earned = staking.earned(alice);
        // BUG: earned = 100 PGX (retroactively uses new rate=1 on past 100s)
        // CORRECT: earned should be 1000 PGX (100s × 10/s at old rate)
        assertEq(earned, 1000 ether, "Rate change must not retroactively alter past rewards");
    }

    /// @notice CRITICAL: raising the rate retroactively inflates past rewards (BUG DEMONSTRATION)
    /// @dev Expected: 100 PGX (100s × 1/s). Actual: 10000 PGX (100s × 100/s).
    function test_SetRewardRate_RaiseDoesNotInflatePastRewards() public {
        staking.setRewardRate(1 ether);

        uint256 rewardFund = 50_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // 100 seconds at rate=1 → expect 100 PGX
        vm.warp(block.timestamp + 100);

        // Owner raises rate to 100 PGX/s
        staking.setRewardRate(100 ether);

        uint256 earned = staking.earned(alice);
        // BUG: earned = 10000 PGX (retroactively uses new rate=100)
        // CORRECT: earned should be 100 PGX (100s × 1/s)
        assertEq(earned, 100 ether, "Rate increase must not retroactively inflate past rewards");
    }

    /// @notice CRITICAL: multi-user scenario with rate change mid-stream (BUG DEMONSTRATION)
    /// @dev Alice staked during old rate, Bob stakes after rate change. Without
    ///      checkpoint, Alice's period-1 rewards are computed at the new rate.
    function test_SetRewardRate_CheckpointsBeforeChanging() public {
        uint256 rewardRate1 = 10 ether;
        uint256 rewardRate2 = 20 ether;

        uint256 rewardFund = 10_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        staking.setRewardRate(rewardRate1);

        // Alice stakes 1000 PGX
        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        // 100 seconds at rate=10
        vm.warp(block.timestamp + 100);

        // Owner changes rate to 20 (without checkpoint = BUG)
        staking.setRewardRate(rewardRate2);

        // Bob stakes after rate change
        vm.startPrank(bob);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        // 100 more seconds at rate=20
        vm.warp(block.timestamp + 100);

        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 bobBalanceBefore = token.balanceOf(bob);

        vm.prank(alice);
        staking.claimRewards();

        vm.prank(bob);
        staking.claimRewards();

        uint256 aliceRewardsReceived = token.balanceOf(alice) - aliceBalanceBefore;
        uint256 bobRewardsReceived = token.balanceOf(bob) - bobBalanceBefore;

        // Alice SHOULD get: 1000 (100s × 10/s alone) + 1000 (100s × 20/s ÷ 2) = 2000
        // BUG: Alice gets 3000 because period-1 is recalculated at rate=20
        assertEq(aliceRewardsReceived, 2000 ether, "Alice should receive 2000 PGX (old + new rate)");

        // Bob SHOULD get: 1000 (100s × 20/s ÷ 2)
        assertEq(bobRewardsReceived, 1000 ether, "Bob should receive 1000 PGX (new rate only)");

        // Verify reward balance accounting
        uint256 totalRewardsClaimed = aliceRewardsReceived + bobRewardsReceived;
        assertEq(staking.rewards(alice), 0, "Alice rewards mapping should be zeroed");
        assertEq(staking.rewards(bob), 0, "Bob rewards mapping should be zeroed");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  SECTION 10: MULTI-USER COMPREHENSIVE SCENARIOS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Scenario: 3 users stake at different times, verify proportional rewards
    /// Timeline:
    ///   T=0:   Alice stakes 1000 (total=1000, Alice=100% of rewards)
    ///   T=100: Bob stakes 2000   (total=3000, Alice=33%, Bob=67%)
    ///   T=200: Charlie stakes 1000 (total=4000, Alice=25%, Bob=50%, Charlie=25%)
    ///   T=300: Everyone claims
    function test_ThreeUsers_StaggeredEntry() public {
        staking.setRewardRate(12 ether); // 12 PGX/s (divisible by 3 and 4)

        uint256 rewardFund = 50_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        // T=0: Alice stakes 1000
        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // T=100: Bob stakes 2000
        vm.warp(block.timestamp + 100);
        vm.startPrank(bob);
        token.approve(address(staking), 2000 ether);
        staking.stake(2000 ether);
        vm.stopPrank();

        // T=200: Charlie stakes 1000
        vm.warp(block.timestamp + 100);
        vm.startPrank(charlie);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // T=300: Everyone checks earnings
        vm.warp(block.timestamp + 100);

        uint256 aliceEarned = staking.earned(alice);
        uint256 bobEarned = staking.earned(bob);
        uint256 charlieEarned = staking.earned(charlie);

        // Alice:
        //   Period 1 (0-100): 12 * 100 * 1000/1000 = 1200 PGX (alone)
        //   Period 2 (100-200): 12 * 100 * 1000/3000 = 400 PGX
        //   Period 3 (200-300): 12 * 100 * 1000/4000 = 300 PGX
        //   Total: 1900 PGX
        assertEq(aliceEarned, 1900 ether, "Alice: 3 periods, first alone");

        // Bob:
        //   Period 2 (100-200): 12 * 100 * 2000/3000 = 800 PGX
        //   Period 3 (200-300): 12 * 100 * 2000/4000 = 600 PGX
        //   Total: 1400 PGX
        assertEq(bobEarned, 1400 ether, "Bob: 2 periods, larger stake");

        // Charlie:
        //   Period 3 (200-300): 12 * 100 * 1000/4000 = 300 PGX
        //   Total: 300 PGX
        assertEq(charlieEarned, 300 ether, "Charlie: 1 period, quarter share");

        // Total distributed should equal total rate * time = 12 * 300 = 3600 PGX
        uint256 totalEarned = aliceEarned + bobEarned + charlieEarned;
        assertEq(totalEarned, 3600 ether, "Total rewards must equal rate * elapsed time");
    }

    /// @notice Scenario: 2 users stake equal amounts → rewards split 50/50
    function test_TwoUsers_EqualStake_EqualRewards() public {
        staking.setRewardRate(10 ether);

        uint256 rewardFund = 10_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        // Both stake at the same time
        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 200);

        uint256 aliceEarned = staking.earned(alice);
        uint256 bobEarned = staking.earned(bob);

        // 10 PGX/s * 200s = 2000 PGX total, split equally
        assertEq(aliceEarned, 1000 ether, "Alice should get 50%");
        assertEq(bobEarned, 1000 ether, "Bob should get 50%");
    }

    /// @notice Scenario: Unequal stakes → proportionally distributed rewards
    /// Alice stakes 3000, Bob stakes 1000 → 75%/25% split
    function test_TwoUsers_UnequalStake_ProportionalRewards() public {
        staking.setRewardRate(8 ether); // 8 PGX/s (easily divisible by 4)

        uint256 rewardFund = 10_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        vm.startPrank(alice);
        token.approve(address(staking), 3000 ether);
        staking.stake(3000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);

        uint256 aliceEarned = staking.earned(alice);
        uint256 bobEarned = staking.earned(bob);

        // Total: 8 * 100 = 800 PGX
        // Alice: 800 * 3000/4000 = 600 PGX
        // Bob: 800 * 1000/4000 = 200 PGX
        assertEq(aliceEarned, 600 ether, "Alice 75% share");
        assertEq(bobEarned, 200 ether, "Bob 25% share");
    }

    /// @notice Scenario: User exits partially, another enters → shares shift
    /// T=0: Alice stakes 2000 (100%)
    /// T=100: Alice withdraws 1000, Bob stakes 1000 (each 50%)
    /// T=200: Check
    function test_TwoUsers_PartialWithdrawAndNewEntry() public {
        staking.setRewardRate(10 ether);

        uint256 rewardFund = 10_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        // T=0: Alice stakes 2000
        vm.startPrank(alice);
        token.approve(address(staking), 2000 ether);
        staking.stake(2000 ether);
        vm.stopPrank();

        // T=100: Alice withdraws 1000, Bob joins with 1000
        vm.warp(block.timestamp + 100);

        vm.prank(alice);
        staking.withdraw(1000 ether);

        vm.startPrank(bob);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // T=200: Check rewards
        vm.warp(block.timestamp + 100);

        uint256 aliceEarned = staking.earned(alice);
        uint256 bobEarned = staking.earned(bob);

        // Alice:
        //   Period 1 (0-100): 10 * 100 * 2000/2000 = 1000 PGX
        //   Period 2 (100-200): 10 * 100 * 1000/2000 = 500 PGX
        //   Total: 1500 PGX
        assertEq(aliceEarned, 1500 ether, "Alice: full period + half period");

        // Bob:
        //   Period 2 (100-200): 10 * 100 * 1000/2000 = 500 PGX
        assertEq(bobEarned, 500 ether, "Bob: half of period 2");
    }

    /// @notice Scenario: User fully exits and re-enters later
    /// T=0: Alice stakes 1000
    /// T=100: Alice fully withdraws (earned but unclaimed rewards should persist!)
    /// T=200: Alice re-stakes 1000
    /// T=300: Alice checks total earned
    function test_FullExitAndReenter() public {
        staking.setRewardRate(10 ether);

        uint256 rewardFund = 10_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        // T=0: Alice stakes 1000
        vm.startPrank(alice);
        token.approve(address(staking), 2000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // T=100: Alice fully withdraws (1000 earned)
        vm.warp(block.timestamp + 100);
        uint256 earnedAtExit = staking.earned(alice);
        assertEq(earnedAtExit, 1000 ether, "Should earn 1000 before exit");

        vm.prank(alice);
        staking.withdraw(1000 ether);

        // Rewards should still be in rewards mapping
        assertEq(staking.rewards(alice), 1000 ether, "Unclaimed rewards persist after withdraw");
        assertEq(staking.balanceOf(alice), 0, "Stake balance should be zero");

        // T=200: Alice re-stakes (no rewards during gap because balance=0 & totalStaked might be 0)
        vm.warp(block.timestamp + 100);

        vm.prank(alice);
        staking.stake(1000 ether);

        // T=300: 100 more seconds staking
        vm.warp(block.timestamp + 100);

        uint256 totalEarned = staking.earned(alice);
        // Period 1: 1000 PGX (saved in rewards mapping)
        // Gap (100-200): 0 PGX (no stake)
        // Period 3 (200-300): 10 * 100 * 1000/1000 = 1000 PGX
        // Total: 2000 PGX
        assertEq(totalEarned, 2000 ether, "Old rewards + new staking period");
    }

    /// @notice Scenario: 4 users stake/withdraw at different times, claim at end
    /// Complex interleaving to verify accumulator under stress
    function test_FourUsers_ComplexInterleaving() public {
        staking.setRewardRate(20 ether); // 20 PGX/s

        uint256 rewardFund = 100_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        // T=0: Alice stakes 1000, Bob stakes 1000 (total=2000)
        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // T=100: Charlie stakes 2000 (total=4000)
        vm.warp(block.timestamp + 100);
        vm.startPrank(charlie);
        token.approve(address(staking), 2000 ether);
        staking.stake(2000 ether);
        vm.stopPrank();

        // T=200: Bob withdraws (total=3000)
        vm.warp(block.timestamp + 100);
        vm.prank(bob);
        staking.withdraw(1000 ether);

        // T=300: Dave stakes 3000 (total=6000)
        vm.warp(block.timestamp + 100);
        vm.startPrank(dave);
        token.approve(address(staking), 3000 ether);
        staking.stake(3000 ether);
        vm.stopPrank();

        // T=400: Everyone checks
        vm.warp(block.timestamp + 100);

        uint256 aliceE = staking.earned(alice);
        uint256 bobE = staking.earned(bob);
        uint256 charlieE = staking.earned(charlie);
        uint256 daveE = staking.earned(dave);

        // Period 1 (0-100): total=2000, rate=20 → 2000 PGX total
        //   Alice: 1000/2000 * 2000 = 1000
        //   Bob: 1000/2000 * 2000 = 1000
        // Period 2 (100-200): total=4000, rate=20 → 2000 PGX total
        //   Alice: 1000/4000 * 2000 = 500
        //   Bob: 1000/4000 * 2000 = 500
        //   Charlie: 2000/4000 * 2000 = 1000
        // Period 3 (200-300): total=3000, rate=20 → 2000 PGX total
        //   Alice: 1000/3000 * 2000 = 666.66…
        //   Bob: 0 (withdrawn)
        //   Charlie: 2000/3000 * 2000 = 1333.33…
        // Period 4 (300-400): total=6000, rate=20 → 2000 PGX total
        //   Alice: 1000/6000 * 2000 = 333.33…
        //   Charlie: 2000/6000 * 2000 = 666.66…
        //   Dave: 3000/6000 * 2000 = 1000

        // Alice total: 1000 + 500 + 666.66 + 333.33 ≈ 2500
        // Bob total: 1000 + 500 = 1500
        // Charlie total: 1000 + 1333.33 + 666.66 ≈ 3000
        // Dave total: 1000

        // Verify total distributes correctly (total = 20 * 400 = 8000 PGX)
        uint256 totalEarned = aliceE + bobE + charlieE + daveE;
        // Allow 1 wei per period boundary for rounding
        assertGe(totalEarned, 7999 ether, "Total must be ~8000 PGX");
        assertLe(totalEarned, 8000 ether, "Total must not exceed 8000 PGX");

        // Bob: periods 1 and 2 only = 1500
        // Dave: period 4 only, 50% share = 1000
        // Allow tiny rounding from mulDiv
        assertEq(bobE, 1500 ether, "Bob: periods 1 and 2 only");
        assertApproxEqAbs(daveE, 1000 ether, 1e15, "Dave: period 4 only, 50% share");
    }

    /// @notice Scenario: Claim then continue staking. After claiming, more
    /// rewards continue to accrue as if nothing happened.
    function test_ClaimAndContinueStaking_RewardsKeepAccruing() public {
        staking.setRewardRate(10 ether);

        uint256 rewardFund = 10_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // Period 1: 100s → 1000 PGX
        vm.warp(block.timestamp + 100);
        vm.prank(alice);
        staking.claimRewards();

        // Period 2: 100s → 1000 PGX
        vm.warp(block.timestamp + 100);
        uint256 earnedAfterClaim = staking.earned(alice);
        assertEq(earnedAfterClaim, 1000 ether, "Rewards accrue normally after claiming");
    }

    /// @notice Scenario: All users emergency-withdraw. totalStaked becomes 0.
    /// New user staking should restart rewards cleanly.
    function test_AllUsersEmergencyWithdraw_ThenNewStaker() public {
        staking.setRewardRate(10 ether);

        uint256 rewardFund = 10_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        // Alice and Bob stake
        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);

        // Both emergency withdraw
        vm.prank(alice);
        staking.emergencyWithdraw();
        vm.prank(bob);
        staking.emergencyWithdraw();

        assertEq(staking.totalStaked(), 0, "Total staked should be 0 after all exit");

        // Time passes while nobody is staking
        vm.warp(block.timestamp + 100);

        // Charlie enters fresh
        vm.startPrank(charlie);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // 100 more seconds
        vm.warp(block.timestamp + 100);
        uint256 charlieEarned = staking.earned(charlie);

        // Charlie should earn 10 * 100 = 1000 PGX for their period
        assertEq(charlieEarned, 1000 ether, "Charlie earns normally after others exit");
    }

    /// @notice Scenario: Alice claims rewards midway, then Bob joins.
    /// Alice's claim should not affect Bob's future rewards.
    function test_ClaimMidway_DoesNotAffectOtherUsers() public {
        staking.setRewardRate(10 ether);

        uint256 rewardFund = 10_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        // T=0: Alice stakes 1000
        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // T=100: Alice claims her 1000 PGX
        vm.warp(block.timestamp + 100);
        vm.prank(alice);
        staking.claimRewards();

        // T=100: Bob stakes 1000
        vm.startPrank(bob);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // T=200: Both check earnings
        vm.warp(block.timestamp + 100);

        uint256 aliceEarned = staking.earned(alice);
        uint256 bobEarned = staking.earned(bob);

        // Alice: 10 * 100 * 1000/2000 = 500 PGX (post-claim accrual)
        // Bob: 10 * 100 * 1000/2000 = 500 PGX
        assertEq(aliceEarned, 500 ether, "Alice earns 500 after claim (shared with Bob)");
        assertEq(bobEarned, 500 ether, "Bob earns 500 (same period as Alice)");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  SECTION 11: REWARD RATE CHANGE — MULTI-USER BEFORE/AFTER BEHAVIOR
    //  ⚠️  These tests document the EXPECTED correct behavior. They FAIL
    //       due to the checkpoint bug in setRewardRate.
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Rate increase: both users should benefit from increase only GOING FORWARD
    /// T=0: rate=5, Alice & Bob stake 1000 each
    /// T=100: rate raised to 20
    /// T=200: verify each gets 250 (old) + 1000 (new) = 1250
    ///
    /// BUG: Without checkpoint, earned = 2000 each (all 200s computed at rate=20)
    function test_RateIncrease_TwoUsers_OnlyForward() public {
        staking.setRewardRate(5 ether);

        uint256 rewardFund = 50_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        // Both stake 1000 at T=0
        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // T=100: 100s at rate=5 → 500 total → 250 each
        vm.warp(block.timestamp + 100);

        uint256 aliceBefore = staking.earned(alice);
        uint256 bobBefore = staking.earned(bob);
        assertEq(aliceBefore, 250 ether, "Pre-change: Alice=250");
        assertEq(bobBefore, 250 ether, "Pre-change: Bob=250");

        // Rate raised to 20
        staking.setRewardRate(20 ether);

        // Verify immediately after rate change, earned should be UNCHANGED
        uint256 aliceAfterChange = staking.earned(alice);
        uint256 bobAfterChange = staking.earned(bob);
        // BUG: these will be 1000 each (100s recalculated at rate=20)
        assertEq(aliceAfterChange, 250 ether, "Immediately after change: Alice still 250");
        assertEq(bobAfterChange, 250 ether, "Immediately after change: Bob still 250");

        // T=200: 100 more seconds at rate=20 → 2000 total → 1000 each
        vm.warp(block.timestamp + 100);

        uint256 aliceTotal = staking.earned(alice);
        uint256 bobTotal = staking.earned(bob);
        // Expected: 250 + 1000 = 1250 each
        // BUG: 2000 each (all 200s at rate=20)
        assertEq(aliceTotal, 1250 ether, "Alice: old rate + new rate");
        assertEq(bobTotal, 1250 ether, "Bob: old rate + new rate");
    }

    /// @notice Rate decrease: users should keep rewards earned at old rate
    /// T=0: rate=20, Alice & Bob stake 1000 each
    /// T=100: rate dropped to 2
    /// T=200: each should get 1000 (old) + 100 (new) = 1100
    ///
    /// BUG: Without checkpoint, earned = 200 each (all 200s at rate=2)
    function test_RateDecrease_TwoUsers_PreservePast() public {
        staking.setRewardRate(20 ether);

        uint256 rewardFund = 50_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // T=100: each earned 1000
        vm.warp(block.timestamp + 100);
        assertEq(staking.earned(alice), 1000 ether, "Pre-change: Alice=1000");

        // Rate dropped
        staking.setRewardRate(2 ether);

        // Immediately: should still be 1000 each
        // BUG: will be 100 each (retroactive)
        assertEq(staking.earned(alice), 1000 ether, "After drop: Alice keeps 1000");
        assertEq(staking.earned(bob), 1000 ether, "After drop: Bob keeps 1000");

        // T=200: +100s at rate=2 → 200 total → 100 each
        vm.warp(block.timestamp + 100);
        assertEq(staking.earned(alice), 1100 ether, "Alice: 1000+100");
        assertEq(staking.earned(bob), 1100 ether, "Bob: 1000+100");
    }

    /// @notice Multiple rapid rate changes with stakers present
    /// T=0: rate=10, Alice stakes 1000
    /// T=50: rate changed to 5
    /// T=100: rate changed to 20
    /// T=150: check Alice's total
    function test_MultipleRateChanges_SingleUser() public {
        staking.setRewardRate(10 ether);

        uint256 rewardFund = 50_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // T=50: rate changes from 10→5
        vm.warp(block.timestamp + 50);
        // Expected earned: 50 * 10 = 500 PGX
        staking.setRewardRate(5 ether);

        // T=100: rate changes from 5→20
        vm.warp(block.timestamp + 50);
        // Expected earned: 500 + 50*5 = 750 PGX
        staking.setRewardRate(20 ether);

        // T=150
        vm.warp(block.timestamp + 50);
        // Expected total: 500 + 250 + 50*20 = 1750 PGX
        // BUG: Without checkpoints, all 150s are computed at rate=20 → 3000 PGX
        uint256 earned = staking.earned(alice);
        assertEq(earned, 1750 ether, "Multi-rate: 500+250+1000");
    }

    /// @notice Rate set to 0 should stop reward accrual immediately
    /// T=0: rate=10, Alice stakes 1000
    /// T=100: rate set to 0
    /// T=200: earned should be frozen at 1000
    function test_RateSetToZero_StopsAccrual() public {
        staking.setRewardRate(10 ether);

        uint256 rewardFund = 50_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);
        staking.setRewardRate(0);

        // BUG: Without checkpoint, all past rewards are re-computed at rate=0 → 0 PGX
        uint256 earnedAtStop = staking.earned(alice);
        assertEq(earnedAtStop, 1000 ether, "Rewards at stop should be 1000");

        // More time passes — should NOT earn more
        vm.warp(block.timestamp + 100);
        uint256 earnedLater = staking.earned(alice);
        assertEq(earnedLater, 1000 ether, "No more rewards after rate=0");
    }

    /// @notice Rate change between two users with different stake sizes
    /// T=0: rate=10, Alice stakes 3000, Bob stakes 1000 (total=4000)
    /// T=100: rate → 40
    /// T=200: check
    function test_RateChange_UnequalStakes() public {
        staking.setRewardRate(10 ether);

        uint256 rewardFund = 50_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        vm.startPrank(alice);
        token.approve(address(staking), 3000 ether);
        staking.stake(3000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // T=100: rate=10 → total=1000, Alice=750, Bob=250
        vm.warp(block.timestamp + 100);
        assertEq(staking.earned(alice), 750 ether, "Pre-change Alice: 750");
        assertEq(staking.earned(bob), 250 ether, "Pre-change Bob: 250");

        staking.setRewardRate(40 ether);

        // Immediately after: should remain unchanged
        // BUG: retroactive recalc → Alice=3000, Bob=1000
        assertEq(staking.earned(alice), 750 ether, "Post-change immediate Alice: still 750");
        assertEq(staking.earned(bob), 250 ether, "Post-change immediate Bob: still 250");

        // T=200: 100s at rate=40 → 4000 total → Alice 3000, Bob 1000
        vm.warp(block.timestamp + 100);
        // Alice: 750 + 3000 = 3750
        // Bob: 250 + 1000 = 1250
        assertEq(staking.earned(alice), 3750 ether, "Alice: old + new");
        assertEq(staking.earned(bob), 1250 ether, "Bob: old + new");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  SECTION 12: REWARD CALCULATION VIEW FUNCTION TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function test_RewardPerToken_NoStakers() public view {
        assertEq(staking.rewardPerToken(), 0);
    }

    function test_RewardPerToken_IncreasesOverTime() public {
        staking.setRewardRate(1 ether);

        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);
        uint256 rptAfter = staking.rewardPerToken();
        assertGt(rptAfter, 0, "rewardPerToken should be > 0 after time passes");
    }

    function test_Earned_NoRewardsForZeroStake() public view {
        assertEq(staking.earned(alice), 0);
    }

    function test_Earned_CalculatesCorrectly() public {
        staking.setRewardRate(1 ether);

        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);

        // 1000 * (1 * 100 * 1e18 / 1000) / 1e18 = 100
        uint256 earned = staking.earned(alice);
        assertEq(earned, 100 ether, "Should earn 100 PGX in 100 seconds");
    }

    function test_LastTimeRewardApplicable_BeforePeriodSet() public view {
        assertEq(staking.lastTimeRewardApplicable(), 0);
    }

    function test_LastTimeRewardApplicable_AfterPeriodFinish() public {
        staking.setRewardRate(1 ether);
        uint256 endTime = staking.periodFinish();

        vm.warp(endTime + 100);
        assertEq(staking.lastTimeRewardApplicable(), endTime);
    }

    function test_RewardPerToken_StopsAfterPeriodFinish() public {
        staking.setRewardRate(1 ether);
        uint256 endTime = staking.periodFinish();

        vm.startPrank(alice);
        token.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        vm.warp(endTime);
        uint256 rptAtFinish = staking.rewardPerToken();

        vm.warp(endTime + 100);
        uint256 rptAfter = staking.rewardPerToken();

        assertEq(rptAtFinish, rptAfter, "rewardPerToken should not increase after periodFinish");
    }

    function test_GetRewardBalance() public {
        assertEq(staking.getRewardBalance(), 0);

        token.approve(address(staking), 500 ether);
        staking.fundRewards(500 ether);

        assertEq(staking.getRewardBalance(), 500 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  SECTION 13: EDGE CASES & BOUNDARY CONDITIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Staking 1 wei should work and earn proportional rewards
    function test_MinimalStake_1Wei() public {
        staking.setRewardRate(1 ether);

        uint256 rewardFund = 1000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        vm.startPrank(alice);
        token.approve(address(staking), 1);
        staking.stake(1);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);

        // Sole staker → earns all rewards: 1 * 100 = 100 PGX
        uint256 earned = staking.earned(alice);
        assertEq(earned, 100 ether, "Even 1 wei stake should earn all rewards when sole staker");
    }

    /// @notice Large stake amounts should not overflow
    function test_LargeStake_NoOverflow() public {
        // Give alice a huge amount
        token.mint(alice, 1e30);

        staking.setRewardRate(1 ether);

        uint256 rewardFund = 1000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        vm.startPrank(alice);
        token.approve(address(staking), 1e30);
        staking.stake(1e30);
        vm.stopPrank();

        vm.warp(block.timestamp + 1000);

        // Should not revert
        uint256 earned = staking.earned(alice);
        assertGt(earned, 0, "Large stake should still earn rewards");
    }

    /// @notice Staking when reward rate is zero should earn nothing
    function test_StakeWithZeroRate_NoRewards() public {
        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 1000);

        assertEq(staking.earned(alice), 0, "No rewards when rate=0");
    }

    /// @notice Warp to exact periodFinish should cap rewards
    function test_RewardsCapAtPeriodFinish() public {
        staking.setRewardRate(1 ether);
        uint256 endTime = staking.periodFinish();

        uint256 maxRewards = 1 ether * 365 days;
        token.mint(owner, maxRewards);
        token.approve(address(staking), maxRewards);
        staking.fundRewards(maxRewards);

        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // At period finish
        vm.warp(endTime);
        uint256 earnedAtEnd = staking.earned(alice);

        // After period finish (should NOT increase)
        vm.warp(endTime + 1000);
        uint256 earnedPastEnd = staking.earned(alice);

        assertEq(earnedAtEnd, earnedPastEnd, "Rewards frozen after periodFinish");
    }

    /// @notice Multiple users all emergency withdraw — rewards pool stays intact
    function test_EmergencyWithdraw_DoesNotDrainRewardPool() public {
        staking.setRewardRate(10 ether);

        uint256 rewardFund = 10_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);

        vm.prank(alice);
        staking.emergencyWithdraw();
        vm.prank(bob);
        staking.emergencyWithdraw();

        // Reward balance in contract should remain (forfeited by users)
        assertEq(staking.rewardBalance(), rewardFund, "Reward pool intact after emergency withdraws");
    }

    /// @notice No time passes between stake and withdraw → zero rewards
    function test_ImmediateWithdraw_ZeroRewards() public {
        staking.setRewardRate(10 ether);

        uint256 rewardFund = 10_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        staking.withdraw(1000 ether);
        vm.stopPrank();

        assertEq(staking.earned(alice), 0, "No time = no rewards");
        assertEq(staking.rewards(alice), 0, "Rewards mapping should be 0");
    }

    /// @notice Adding stake in the same block should not double-count time
    function test_SameBlock_DoubleStake() public {
        staking.setRewardRate(10 ether);

        uint256 rewardFund = 10_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        vm.startPrank(alice);
        token.approve(address(staking), 2000 ether);
        staking.stake(1000 ether);
        staking.stake(1000 ether); // Same block
        vm.stopPrank();

        assertEq(staking.balanceOf(alice), 2000 ether);
        assertEq(staking.earned(alice), 0, "Same block: no time elapsed, no rewards");

        vm.warp(block.timestamp + 100);
        // 2000 staked, 10/s, 100s → 1000 PGX
        assertEq(staking.earned(alice), 1000 ether, "Post-block: correctly computed");
    }

    /// @notice Funding rewards after users have been staking should not
    /// affect already-computed rewards; it only affects claimability.
    function test_FundingAfterAccrual_NoEffectOnEarned() public {
        staking.setRewardRate(10 ether);
        // Don't fund yet!

        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);

        uint256 earnedBeforeFund = staking.earned(alice);
        assertEq(earnedBeforeFund, 1000 ether, "Earned calculated even without fundedYou");

        // Now fund
        token.approve(address(staking), 5000 ether);
        staking.fundRewards(5000 ether);

        uint256 earnedAfterFund = staking.earned(alice);
        assertEq(earnedAfterFund, 1000 ether, "Funding doesn't change earned amount");

        // But now Alice can actually claim
        vm.prank(alice);
        staking.claimRewards();
        assertEq(staking.rewards(alice), 0, "Successfully claimed after funding");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  SECTION 14: COMPREHENSIVE MULTI-USER CLAIMING TESTS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Multiple users claim at different times — each gets correct amount
    function test_StaggeredClaims_CorrectAmounts() public {
        staking.setRewardRate(10 ether);

        uint256 rewardFund = 50_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        // Both stake 1000 at T=0
        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // T=100: Alice claims (500 each accrued)
        vm.warp(block.timestamp + 100);
        uint256 aliceBalBefore = token.balanceOf(alice);
        vm.prank(alice);
        staking.claimRewards();
        uint256 aliceClaimed1 = token.balanceOf(alice) - aliceBalBefore;
        assertEq(aliceClaimed1, 500 ether, "Alice claim 1: 500 PGX");

        // T=200: Both claim (another 500 each accrued)
        vm.warp(block.timestamp + 100);
        aliceBalBefore = token.balanceOf(alice);
        uint256 bobBalBefore = token.balanceOf(bob);

        vm.prank(alice);
        staking.claimRewards();
        vm.prank(bob);
        staking.claimRewards();

        uint256 aliceClaimed2 = token.balanceOf(alice) - aliceBalBefore;
        uint256 bobClaimed = token.balanceOf(bob) - bobBalBefore;

        assertEq(aliceClaimed2, 500 ether, "Alice claim 2: 500 PGX");
        assertEq(bobClaimed, 1000 ether, "Bob claim: 1000 PGX (200s of 500/s)");
    }

    /// @notice One user claims frequently, another never claims — same total
    function test_FrequentVsNoClaim_SameTotal() public {
        staking.setRewardRate(10 ether);

        uint256 rewardFund = 50_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        uint256 aliceInitBal = token.balanceOf(alice);
        uint256 bobInitBal = token.balanceOf(bob);

        // Alice claims every 50 seconds for 200 seconds
        for (uint256 i = 0; i < 4; i++) {
            vm.warp(block.timestamp + 50);
            vm.prank(alice);
            staking.claimRewards();
        }

        // Bob claims once at T=200
        vm.prank(bob);
        staking.claimRewards();

        uint256 aliceTotalReceived = token.balanceOf(alice) - aliceInitBal;
        uint256 bobTotalReceived = token.balanceOf(bob) - bobInitBal;

        // Both should have received the same total: 10 * 200 / 2 = 1000 PGX each
        assertEq(aliceTotalReceived, bobTotalReceived, "Claim frequency doesn't affect total rewards");
        assertEq(aliceTotalReceived, 1000 ether, "Each gets 1000 PGX");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  SECTION 15: EMERGENCY WITHDRAW MULTI-USER INTERACTIONS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice One user emergency-exits, other user's rewards should increase
    /// (their share of future rewards goes to 100%)
    function test_EmergencyWithdraw_BoostsRemainingUserRewards() public {
        staking.setRewardRate(10 ether);

        uint256 rewardFund = 10_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        // Both stake 1000
        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // T=100: Both earned 500 each
        vm.warp(block.timestamp + 100);
        assertEq(staking.earned(alice), 500 ether, "Pre-exit: Alice=500");
        assertEq(staking.earned(bob), 500 ether, "Pre-exit: Bob=500");

        // Alice emergency exits
        vm.prank(alice);
        staking.emergencyWithdraw();

        // Alice forfeits rewards
        assertEq(staking.rewards(alice), 0, "Alice forfeited");
        assertEq(staking.totalStaked(), 1000 ether, "Only Bob remains");

        // T=200: Bob gets 100% of rewards in period 2
        vm.warp(block.timestamp + 100);
        uint256 bobTotal = staking.earned(bob);
        // Bob: 500 (period 1) + 10 * 100 = 1500 PGX
        assertEq(bobTotal, 1500 ether, "Bob gets all rewards after Alice exits");
    }

    /// @notice Emergency withdraw does not affect the reward earned count for other users
    function test_EmergencyWithdraw_OtherUserRewardsUntouched() public {
        staking.setRewardRate(10 ether);

        uint256 rewardFund = 10_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 100);

        uint256 bobEarnedBefore = staking.earned(bob);

        // Alice emergency-exits
        vm.prank(alice);
        staking.emergencyWithdraw();

        // Bob's earned should be unchanged by Alice's exit
        uint256 bobEarnedAfter = staking.earned(bob);
        assertEq(bobEarnedBefore, bobEarnedAfter, "Bob's earned unchanged by Alice's emergency exit");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  SECTION 16: TIME GAP SCENARIOS
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Gap between period finish and new rate setting.
    /// Rewards should NOT accrue during the gap.
    function test_GapBetweenPeriods_NoRewards() public {
        staking.setRewardRate(10 ether);
        uint256 endTime = staking.periodFinish();

        // Mint extra tokens to owner so we can fund a full year at 10/s
        uint256 rewardFund = 365 days * 10 ether;
        token.mint(owner, rewardFund);
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // Warp to just before period finish
        vm.warp(endTime - 100);
        uint256 earnedBeforeEnd = staking.earned(alice);

        // Warp past period finish
        vm.warp(endTime + 1000);
        uint256 earnedAfterEnd = staking.earned(alice);

        // Should earn rewards only for last 100s before finish
        assertEq(earnedAfterEnd - earnedBeforeEnd, 1000 ether, "Only 100s of rewards in final window");

        // Earned should be capped (same at endTime vs endTime+1000)
        vm.warp(endTime);
        uint256 earnedAtEnd = staking.earned(alice);
        assertEq(earnedAfterEnd, earnedAtEnd, "Rewards capped at periodFinish");
    }

    /// @notice Very large time warp should not cause issues
    function test_VeryLargeTimeWarp() public {
        staking.setRewardRate(1 ether);

        uint256 rewardFund = 500_000 ether;
        token.approve(address(staking), rewardFund);
        staking.fundRewards(rewardFund);

        vm.startPrank(alice);
        token.approve(address(staking), 1000 ether);
        staking.stake(1000 ether);
        vm.stopPrank();

        // Warp 10 years
        vm.warp(block.timestamp + 365 days * 10);

        // Should not overflow, rewards capped at periodFinish (1 year)
        uint256 earned = staking.earned(alice);
        uint256 maxExpected = 1 ether * 365 days; // 1 year of rewards
        assertEq(earned, maxExpected, "Capped at 1 year of rewards");
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  SECTION 17: FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════

    function testFuzz_Stake(uint256 amount) public {
        amount = bound(amount, 1, 50_000 ether);

        vm.startPrank(alice);
        token.approve(address(staking), amount);
        staking.stake(amount);
        vm.stopPrank();

        assertEq(staking.balanceOf(alice), amount);
        assertEq(staking.totalStaked(), amount);
    }

    function testFuzz_StakeAndWithdraw(uint256 stakeAmount, uint256 withdrawAmount) public {
        stakeAmount = bound(stakeAmount, 1, 50_000 ether);
        withdrawAmount = bound(withdrawAmount, 1, stakeAmount);

        vm.startPrank(alice);
        token.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount);
        staking.withdraw(withdrawAmount);
        vm.stopPrank();

        assertEq(staking.balanceOf(alice), stakeAmount - withdrawAmount);
    }

    function testFuzz_EarnedRewards(uint256 stakeAmount, uint256 duration) public {
        stakeAmount = bound(stakeAmount, 1 ether, 50_000 ether);
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
        uint256 expectedMin = rewardRate * duration * 99 / 100; // 1% tolerance
        uint256 expectedMax = rewardRate * duration * 101 / 100;
        assertGe(earned, expectedMin);
        assertLe(earned, expectedMax);
    }

    /// @notice Fuzz: Two users with random stakes should share rewards proportionally
    function testFuzz_TwoUsers_ProportionalRewards(
        uint256 aliceStake,
        uint256 bobStake,
        uint256 duration
    ) public {
        aliceStake = bound(aliceStake, 1 ether, 10_000 ether);
        bobStake = bound(bobStake, 1 ether, 10_000 ether);
        duration = bound(duration, 10, 5000);

        staking.setRewardRate(10 ether);

        token.approve(address(staking), 10 ether * duration * 2);
        staking.fundRewards(10 ether * duration * 2);

        vm.startPrank(alice);
        token.approve(address(staking), aliceStake);
        staking.stake(aliceStake);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(staking), bobStake);
        staking.stake(bobStake);
        vm.stopPrank();

        vm.warp(block.timestamp + duration);

        uint256 aliceEarned = staking.earned(alice);
        uint256 bobEarned = staking.earned(bob);

        // Total rewards should approximate rate * duration = 10 * duration PGX
        // Allow 1 ether tolerance for mulDiv rounding at all stake sizes
        assertApproxEqAbs(
            aliceEarned + bobEarned,
            10 ether * duration,
            1 ether,
            "Total within rounding tolerance"
        );

        // Proportionality: aliceEarned/bobEarned ≈ aliceStake/bobStake
        // Cross-multiply to avoid division
        if (aliceEarned > 0 && bobEarned > 0) {
            uint256 lhs = aliceEarned * bobStake;
            uint256 rhs = bobEarned * aliceStake;
            uint256 diff = lhs > rhs ? lhs - rhs : rhs - lhs;
            // Tolerance scales with total stakes × duration (rounding per period)
            assertLe(diff, (aliceStake + bobStake) * duration * 2, "Rewards proportional to stake size");
        }
    }

    /// @notice Fuzz: stake → withdraw partial → check rewards stay consistent
    function testFuzz_StakeWithdrawRewards(
        uint256 stakeAmt,
        uint256 withdrawPct,
        uint256 dur1,
        uint256 dur2
    ) public {
        stakeAmt = bound(stakeAmt, 1 ether, 10_000 ether);
        withdrawPct = bound(withdrawPct, 1, 99); // 1-99%
        dur1 = bound(dur1, 10, 5000);
        dur2 = bound(dur2, 10, 5000);

        staking.setRewardRate(1 ether);

        uint256 fundAmt = 1 ether * (dur1 + dur2) * 2;
        token.approve(address(staking), fundAmt);
        staking.fundRewards(fundAmt);

        vm.startPrank(alice);
        token.approve(address(staking), stakeAmt);
        staking.stake(stakeAmt);
        vm.stopPrank();

        vm.warp(block.timestamp + dur1);

        uint256 earnedBefore = staking.earned(alice);

        uint256 withdrawAmt = stakeAmt * withdrawPct / 100;
        if (withdrawAmt == 0) withdrawAmt = 1;
        if (withdrawAmt > stakeAmt) withdrawAmt = stakeAmt;

        vm.prank(alice);
        staking.withdraw(withdrawAmt);

        // Earned should not decrease after withdrawal
        uint256 earnedAfterWithdraw = staking.earned(alice);
        assertGe(earnedAfterWithdraw, earnedBefore, "Earned must not decrease on withdraw");

        vm.warp(block.timestamp + dur2);

        // Earned should continue increasing
        uint256 earnedFinal = staking.earned(alice);
        if (stakeAmt - withdrawAmt > 0) {
            assertGt(earnedFinal, earnedAfterWithdraw, "Rewards accrue with remaining stake");
        }
    }
}
