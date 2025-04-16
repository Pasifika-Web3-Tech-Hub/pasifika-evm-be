// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/PSFToken.sol";

error AccessControlUnauthorizedAccount(address account, bytes32 role);
error EnforcedPause();

contract PSFTokenTest is Test {
    PSFToken token;
    address admin = address(1);
    address minter = address(2);
    address burner = address(3);
    address treasury = address(4);
    address noia = address(5);
    address edwin = address(6);

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
        token.mint(noia, 100 ether);
        assertEq(token.balanceOf(noia), 100 ether);
        assertEq(token.totalSupply(), 100 ether);
    }

    function testMintOverMaxSupplyReverts() public {
        console.log(minter);
        console.logBytes32(token.MINTER_ROLE());
        console.logBool(token.hasRole(token.MINTER_ROLE(), minter));
        // Ensure minter has the role
        if (!token.hasRole(token.MINTER_ROLE(), minter)) {
            vm.prank(admin);
            token.grantRole(token.MINTER_ROLE(), minter);
        }
        console.logBool(token.hasRole(token.MINTER_ROLE(), minter)); // After granting
        vm.startPrank(minter);
        token.mint(noia, token.MAX_SUPPLY());
        vm.expectRevert("PSFToken: max supply exceeded");
        token.mint(noia, 1);
        vm.stopPrank();
    }

    function testMintByNonMinterReverts() public {
        vm.expectRevert();
        token.mint(noia, 1 ether);
    }

    function testBurn() public {
        vm.prank(minter);
        token.mint(noia, 50 ether);
        vm.prank(noia);
        token.burn(20 ether);
        assertEq(token.balanceOf(noia), 30 ether);
    }

    function testBurnFromByBurner() public {
        vm.prank(minter);
        token.mint(noia, 100 ether);
        vm.prank(noia);
        token.approve(burner, 40 ether);
        vm.prank(burner);
        token.burnFrom(noia, 40 ether);
        assertEq(token.balanceOf(noia), 60 ether);
    }

    function testBurnFromByNonBurnerReverts() public {
        vm.prank(minter);
        token.mint(noia, 100 ether);
        vm.prank(noia);
        token.approve(edwin, 10 ether);
        vm.expectRevert();
        vm.prank(edwin);
        token.burnFrom(noia, 10 ether);
    }

    function testPauseAndUnpause() public {
        vm.prank(admin);
        token.pause();
        vm.expectRevert(EnforcedPause.selector);
        vm.prank(minter);
        token.mint(noia, 1 ether);

        vm.prank(admin);
        token.unpause();
        vm.prank(minter);
        token.mint(noia, 1 ether);
        assertEq(token.balanceOf(noia), 1 ether);
    }

    function testStakeAndUnstake() public {
        vm.prank(minter);
        token.mint(noia, 100 ether);

        vm.prank(noia);
        token.approve(address(token), 100 ether);

        vm.warp(1 hours); // ensure time is not zero
        vm.prank(noia);
        uint256 stakeId = token.stake(50 ether, 1 days);
        assertEq(token.balanceOf(noia), 50 ether);
        assertEq(token.balanceOf(address(token)), 50 ether);

        // Try to unstake before time
        vm.prank(noia);
        vm.expectRevert("PSFToken: stake still locked");
        token.unstake(stakeId);

        // Fast forward time
        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(noia);
        token.unstake(stakeId);
        assertEq(token.balanceOf(noia), 100 ether);
    }

    function testVestingLifecycle() public {
        console.log(admin);
        vm.prank(minter);
        token.mint(admin, 100 ether);
        console.log(token.balanceOf(admin)); // Log admin's balance after mint
        console.log("token address", address(token));
        vm.startPrank(admin);
        token.transfer(address(token), 100 ether); // Pre-fund the contract
        token.createVestingSchedule(noia, 100 ether, 1 days, 10 days, true);
        vm.stopPrank();

        // Before cliff: nothing releasable
        assertEq(token.calculateReleasableAmount(noia), 0);

        // After cliff, partial vesting
        vm.warp(block.timestamp + 2 days);
        uint256 releasable = token.calculateReleasableAmount(noia);
        assertGt(releasable, 0);

        vm.prank(noia);
        token.releaseVestedTokens(noia);
        assertEq(token.balanceOf(noia), releasable);

        vm.prank(admin);
        token.revokeVestingSchedule(noia);
        // All tokens accounted for
        assertEq(token.balanceOf(admin) + token.balanceOf(noia), 100 ether);
    }

    function testUnauthorizedVestingReverts() public {
        vm.expectRevert();
        token.createVestingSchedule(noia, 10 ether, 1, 10, true);
    }

    function testTotalStakedAmountAndWeight() public {
        vm.prank(minter);
        token.mint(noia, 100 ether);
        vm.prank(noia);
        token.approve(address(token), 100 ether);

        vm.prank(noia);
        token.stake(10 ether, 30 days);
        vm.prank(noia);
        token.stake(20 ether, 60 days);

        assertEq(token.totalStakedAmount(noia), 30 ether);
        assertGt(token.getStakingWeight(noia), 30 ether);
    }
}