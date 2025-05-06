// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/PasifikaMembership.sol";
import "../src/PasifikaTreasury.sol";
import "../src/PasifikaMoneyTransfer.sol";
import "../src/ArbitrumTokenAdapter.sol";

contract PasifikaMembershipTest is Test {
    PasifikaMembership public membership;
    PasifikaTreasury public treasury;
    PasifikaMoneyTransfer public moneyTransfer;
    ArbitrumTokenAdapter public tokenAdapter;

    address public deployer;
    address public member1;
    address public member2;
    address public member3;
    address public treasuryWallet;

    uint256 public membershipFee = 0.0001 ether;

    function setUp() public {
        // Create test accounts
        deployer = makeAddr("deployer");
        member1 = makeAddr("member1");
        member2 = makeAddr("member2");
        member3 = makeAddr("member3");
        treasuryWallet = makeAddr("treasuryWallet");

        // Fund accounts
        vm.deal(deployer, 100 ether);
        vm.deal(member1, 1 ether);
        vm.deal(member2, 1 ether);
        vm.deal(member3, 1 ether);

        vm.startPrank(deployer);

        // Deploy token adapter for Arbitrum
        tokenAdapter = new ArbitrumTokenAdapter(deployer);

        // Deploy treasury with deployer as admin
        treasury = new PasifikaTreasury(deployer);

        // Deploy membership contract with deployer as admin
        membership = new PasifikaMembership(payable(address(treasury)));

        // Grant proper roles to membership contract in treasury
        treasury.grantRole(treasury.DEFAULT_ADMIN_ROLE(), deployer);
        treasury.grantRole(treasury.ADMIN_ROLE(), deployer);
        treasury.grantRole(treasury.TREASURER_ROLE(), deployer);
        treasury.grantRole(treasury.SPENDER_ROLE(), deployer);
        treasury.grantRole(treasury.SPENDER_ROLE(), address(membership));
        treasury.addFeeCollector(address(membership));

        // Grant proper roles to deployer in membership
        membership.grantRole(membership.DEFAULT_ADMIN_ROLE(), deployer);
        membership.grantRole(membership.ADMIN_ROLE(), deployer);
        membership.grantRole(membership.MEMBERSHIP_MANAGER_ROLE(), deployer);
        membership.grantRole(membership.PROFIT_SHARING_MANAGER_ROLE(), deployer);

        // Deploy money transfer
        moneyTransfer = new PasifikaMoneyTransfer(
            payable(address(tokenAdapter)), payable(treasuryWallet), payable(address(treasury))
        );

        // Setup money transfer
        moneyTransfer.grantRole(moneyTransfer.DEFAULT_ADMIN_ROLE(), deployer);
        moneyTransfer.grantRole(moneyTransfer.FEE_MANAGER_ROLE(), deployer);
        moneyTransfer.grantRole(moneyTransfer.PAUSER_ROLE(), deployer);

        treasury.addFeeCollector(address(moneyTransfer));
        treasury.grantRole(treasury.SPENDER_ROLE(), address(moneyTransfer));

        moneyTransfer.initializeTreasury();
        moneyTransfer.setMembershipContract(payable(address(membership)));

        // Fund treasury with ETH for profit sharing tests
        treasury.depositFunds{value: 10 ether}("Initial funding");

        vm.stopPrank();
    }

    function testJoinMembership() public {
        // Check initial member count
        assertEq(membership.getMemberCount(), 0, "Should start with 0 members");

        // Join membership
        vm.prank(member1);
        membership.joinMembership{value: membershipFee}();

        // Verify
        assertTrue(membership.isMember(member1), "Member1 should be registered as a member");
        assertEq(membership.getMemberCount(), 1, "Should have 1 member");
    }

    function testGrantMembership() public {
        // Grant membership
        vm.prank(deployer);
        membership.grantMembership(member2);

        // Verify
        assertTrue(membership.isMember(member2), "Member2 should be registered as a member");
        assertEq(membership.getMemberCount(), 1, "Should have 1 member");
    }

    function testRevokeMembership() public {
        // Grant membership
        vm.prank(deployer);
        membership.grantMembership(member2);

        // Verify
        assertTrue(membership.isMember(member2), "Member2 should be registered as a member");

        // Revoke membership
        vm.prank(deployer);
        membership.revokeMembership(member2);

        // Verify
        assertTrue(membership.isMember(member2), "Member2 should still be a member");
        assertFalse(membership.getMemberDetails(member2).active, "Member2 should be inactive");
    }

    function testRestoreMembership() public {
        // Grant and revoke
        vm.startPrank(deployer);
        membership.grantMembership(member2);
        membership.revokeMembership(member2);
        vm.stopPrank();

        // Verify
        assertFalse(membership.getMemberDetails(member2).active, "Member2 should be inactive");

        // Restore
        vm.prank(deployer);
        membership.restoreMembership(member2);

        // Verify
        assertTrue(membership.getMemberDetails(member2).active, "Member2 should be active again");
    }

    function testInitiateProfitSharing() public {
        // Setup - add some members
        vm.startPrank(deployer);
        membership.grantMembership(member1);
        membership.grantMembership(member2);
        membership.grantMembership(member3);
        vm.stopPrank();

        // Record initial balances
        uint256 initialTreasuryBalance = address(treasury).balance;
        uint256 initialMembershipBalance = address(membership).balance;

        // Initiate profit sharing
        vm.prank(deployer);
        membership.initiateProfitSharing();

        // Verify
        assertTrue(membership.profitSharingInProgress(), "Profit sharing should be in progress");
        assertGt(address(membership).balance, initialMembershipBalance, "Membership should have received ETH");
    }

    function testClaimProfitShare() public {
        // Setup - use explicit years instead of relying on block.timestamp
        // Warp to the beginning of 1971 (using timestamps)
        uint256 year1971 = 31536000; // Seconds since epoch for 1971
        vm.warp(year1971);

        // Calculate the current year and previous year
        uint256 currentYear = 1971;
        uint256 previousYear = 1970;

        vm.startPrank(deployer);
        membership.grantMembership(member1);
        membership.grantMembership(member2);

        // First, warp to previous year (1970)
        vm.warp(31536000 / 2); // Middle of 1970

        // Record transactions for previous year (1970)
        for (uint256 i = 0; i < 100; i++) {
            membership.recordTransaction(member1, 0.01 ether); // Total 1 ETH
        }

        // Warp back to 1971
        vm.warp(year1971);

        // Debug: Check transaction counts and volume for the previous year
        uint256 txCount = membership.yearlyTransactionCount(member1, previousYear);
        uint256 txVolume = membership.yearlyTransactionVolume(member1, previousYear);
        console.log("Member1 previous year (1970) transaction count:", txCount);
        console.log("Member1 previous year (1970) transaction volume:", txVolume);
        console.log("Previous year:", previousYear);
        console.log("Current year:", currentYear);
        console.log("Required transaction count:", membership.requiredTransactionCount());
        console.log("Required transaction volume:", membership.requiredTransactionVolume());
        console.log("Is eligible for previous year:", membership.isEligibleForProfitSharing(member1, previousYear));

        // Initiate profit sharing (this will set currentProfitSharingYear to currentYear)
        membership.initiateProfitSharing();
        vm.stopPrank();

        // Record initial balance
        uint256 initialBalance = member1.balance;

        // Claim share (this will check eligibility for currentProfitSharingYear - 1, which is previousYear)
        vm.prank(member1);
        membership.claimProfitShare();

        // Verify
        assertGt(member1.balance, initialBalance, "Member should have received ETH");
        assertTrue(
            membership.hasClaimed(member1, membership.currentProfitSharingYear()), "Member should be marked as claimed"
        );
    }
}
