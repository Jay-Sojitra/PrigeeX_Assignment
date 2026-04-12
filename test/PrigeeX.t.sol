// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/PrigeeX.sol";

contract PrigeeXTest is Test {
    PrigeeX public token;
    address public owner;
    address public alice;
    address public bob;

    uint256 constant INITIAL_SUPPLY = 1_000_000 ether;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        owner = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        token = new PrigeeX(INITIAL_SUPPLY);
    }

    function test_InitialState() public view {
        assertEq(token.name(), "PrigeeX");
        assertEq(token.symbol(), "PGX");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY);
        assertEq(token.owner(), owner);
    }

    function test_Transfer() public {
        uint256 amount = 1000 ether;

        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, alice, amount);

        token.transfer(alice, amount);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - amount);
    }

    function test_TransferFrom() public {
        uint256 amount = 1000 ether;

        token.approve(alice, amount);

        vm.prank(alice);
        token.transferFrom(owner, bob, amount);

        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - amount);
    }

    function test_Approve() public {
        uint256 amount = 1000 ether;

        vm.expectEmit(true, true, false, true);
        emit Approval(owner, alice, amount);

        token.approve(alice, amount);

        assertEq(token.allowance(owner, alice), amount);
    }

    function test_Mint_OnlyOwner() public {
        uint256 mintAmount = 500 ether;

        token.mint(alice, mintAmount);

        assertEq(token.balanceOf(alice), mintAmount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY + mintAmount);
    }

    function test_Mint_RevertWhenNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        token.mint(alice, 100 ether);
    }

    function test_Burn_OnlyOwner() public {
        uint256 burnAmount = 500 ether;

        token.burn(owner, burnAmount);

        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - burnAmount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY - burnAmount);
    }

    function test_Burn_RevertWhenNotOwner() public {
        token.transfer(alice, 1000 ether);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        token.burn(alice, 100 ether);
    }

    function test_Burn_RevertWhenInsufficientBalance() public {
        vm.expectRevert();
        token.burn(alice, 100 ether);
    }

    function testFuzz_Transfer(uint256 amount) public {
        amount = bound(amount, 0, INITIAL_SUPPLY);

        token.transfer(alice, amount);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY - amount);
    }

    function testFuzz_Mint(uint256 amount) public {
        amount = bound(amount, 0, type(uint128).max);

        token.mint(alice, amount);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.totalSupply(), INITIAL_SUPPLY + amount);
    }
}
