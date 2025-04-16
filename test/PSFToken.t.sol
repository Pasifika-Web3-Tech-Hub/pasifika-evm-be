// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/PSFToken.sol";

contract PSFTokenTest is Test {
    PSFToken token;
    address admin = address(1);
    address minter = address(2);
    address burner = address(3);
    address treasury = address(4);
    address alice = address(5);
    address bob = address(6);

    function setUp() public {
        vm.startPrank(admin);
        token = new PSFToken();
        // Grant roles to test addresses
        token.grantRole(token.MINTER_ROLE(), minter);
        token.grantRole(token.BURNER_ROLE(), burner);
        token.grantRole(token.TREASURY_ROLE(), treasury);
        vm.stopPrank();
    }

    function testInitialProperties() public {
        assertEq(token.name(), "PASIFIKA Token");
        assertEq(token.symbol(), "PSF");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 0);
        assertEq(token.MAX_SUPPLY(), 1_000_000_000 ether);
    }

    function testMintByMinter() public {
        vm.prank(minter);
        token.mint(alice, 100 ether);
        assertEq(token.balanceOf(alice), 100 ether);
        assertEq(token.totalSupply(), 100 ether);
    }

    function testMintOverMaxSupplyReverts() public {
        vm.prank(minter);
        token.mint(alice, token.MAX_SUPPLY());
        vm.expectRevert("PSFToken: max supply exceeded");
        vm.prank(minter);
        token.mint(alice, 1);
    }

    function testMintByNonMinterReverts() public {
        vm.expectRevert();
        token.mint(alice, 1 ether);
    }

    function testBurn() public {
        vm.prank(minter);
        token.mint(alice, 50 ether);
        vm.prank(alice);
        token.burn(20 ether);
        assertEq(token.balanceOf(alice), 30 ether);
    }

    function testBurnFromByBurner() public {
        vm.prank(minter);
        token.mint(alice, 100 ether);
        vm.prank(alice);
        token.approve(burner, 40 ether);
        vm.prank(burner);
        token.burnFrom(alice, 40 ether);
        assertEq(token.balanceOf(alice), 60 ether);
    }

    function testBurnFromByNonBurnerReverts() public {
        vm.prank(minter);
        token.mint(alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, 10 ether);
        vm.expectRevert();
        vm.prank(bob);
        token.burnFrom(alice, 10 ether);
    }

    function testPauseAndUnpause() public {
        vm.prank(admin);
        token.pause();
        vm.prank(minter);
        vm.expectRevert("Pausable: paused");
        token.mint(alice, 1 ether);

        vm.prank(admin);
        token.unpause();
        vm.prank(minter);
        token.mint(alice, 1 ether);
        assertEq(token.balanceOf(alice), 1 ether);
    }

    function testStakeAndUnstake() public {
        vm.prank(minter);
        token.mint(alice, 100 ether);

        vm.prank(alice);
        token.approve(address(token), 100 ether);

        vm.warp(1 hours); // ensure time is not zero
        vm.prank(alice);
        uint256 stakeId = token.stake(50 ether, 1 days);
        assertEq(token.balanceOf(alice), 50 ether);
        assertEq(token.balanceOf(address(token)), 50 ether);

        // Try to unstake before time
        vm.prank(alice);
        vm.expectRevert("PSFToken: stake still locked");
        token.unstake(stakeId);

        // Fast forward time
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(alice);
        token.unstake(stakeId);
        assertEq(token.balanceOf(alice), 100 ether);
    }

    function testVestingLifecycle() public {
        vm.prank(minter);
        token.mint(admin, 100 ether);

        vm.prank(admin);
        token.approve(address(token), 100 ether);

        // Create vesting for Alice: 100 tokens, 1 day cliff, 10 days vest, revocable
        vm.prank(admin);
        token.createVestingSchedule(alice, 100 ether, 1 days, 10 days, true);

        // Before cliff: nothing releasable
        assertEq(token.calculateReleasableAmount(alice), 0);

        // After cliff, partial vesting
        vm.warp(block.timestamp + 2 days);
        uint256 releasable = token.calculateReleasableAmount(alice);
        assertGt(releasable, 0);

        // Release tokens
        vm.prank(alice);
        token.releaseVestedTokens(alice);
        assertEq(token.balanceOf(alice), releasable);

        // Revoke vesting: admin gets unreleased tokens
        vm.prank(admin);
        token.revokeVestingSchedule(alice);
        // All tokens accounted for
        assertEq(token.balanceOf(admin) + token.balanceOf(alice), 100 ether);
    }

    function testUnauthorizedVestingReverts() public {
        vm.expectRevert();
        token.createVestingSchedule(alice, 10 ether, 1, 10, true);
    }

    function testTotalStakedAmountAndWeight() public {
        vm.prank(minter);
        token.mint(alice, 100 ether);
        vm.prank(alice);
        token.approve(address(token), 100 ether);

        vm.prank(alice);
        token.stake(10 ether, 30 days);
        vm.prank(alice);
        token.stake(20 ether, 60 days);

        assertEq(token.totalStakedAmount(alice), 30 ether);
        assertGt(token.getStakingWeight(alice), 30 ether);
    }
}