// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/PasifikaMoneyTransfer.sol";
import "../src/PasifikaTreasury.sol";
import "../src/ArbitrumTokenAdapter.sol";

contract PasifikaBasicRolesTest is Test {
    PasifikaMoneyTransfer public moneyTransfer;
    PasifikaTreasury public treasury;
    ArbitrumTokenAdapter public tokenAdapter;

    address public alice;
    address public bob;

    function setUp() public {
        // Create test accounts
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // Fund accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 10 ether);

        vm.startPrank(alice);

        // Deploy token adapter for Arbitrum
        tokenAdapter = new ArbitrumTokenAdapter(alice);

        // Deploy treasury with alice as admin
        treasury = new PasifikaTreasury(alice);

        // Grant all necessary roles to alice
        treasury.grantRole(treasury.DEFAULT_ADMIN_ROLE(), alice);
        treasury.grantRole(treasury.ADMIN_ROLE(), alice);
        treasury.grantRole(treasury.TREASURER_ROLE(), alice);
        treasury.grantRole(treasury.SPENDER_ROLE(), alice);

        // Deploy money transfer with alice as admin
        moneyTransfer = new PasifikaMoneyTransfer(
            payable(address(tokenAdapter)), // Arbitrum token adapter
            payable(alice), // Treasury wallet
            payable(address(treasury))
        );

        // Add money transfer as a fee collector to treasury
        treasury.addFeeCollector(address(moneyTransfer));

        // Make sure money transfer is granted the SPENDER_ROLE on treasury
        treasury.grantRole(treasury.SPENDER_ROLE(), address(moneyTransfer));

        // Grant roles to alice on money transfer
        moneyTransfer.grantRole(moneyTransfer.DEFAULT_ADMIN_ROLE(), alice);
        moneyTransfer.grantRole(moneyTransfer.FEE_MANAGER_ROLE(), alice);
        moneyTransfer.grantRole(moneyTransfer.PAUSER_ROLE(), alice);

        // Initialize treasury connection
        moneyTransfer.initializeTreasury();

        // Set standard fees
        moneyTransfer.setBaseFeePercent(100); // 1%

        vm.stopPrank();
    }

    // Basic test to check role assignments
    function testRoleAssignments() public {
        assertTrue(treasury.hasRole(treasury.DEFAULT_ADMIN_ROLE(), alice));
        assertTrue(treasury.hasRole(treasury.ADMIN_ROLE(), alice));
        assertTrue(treasury.hasRole(treasury.FEE_COLLECTOR_ROLE(), address(moneyTransfer)));
        assertTrue(treasury.hasRole(treasury.SPENDER_ROLE(), address(moneyTransfer)));

        assertTrue(moneyTransfer.hasRole(moneyTransfer.DEFAULT_ADMIN_ROLE(), alice));
        assertTrue(moneyTransfer.hasRole(moneyTransfer.FEE_MANAGER_ROLE(), alice));
    }

    // Test a simple transfer
    function testBasicTransfer() public {
        // Fund bob further
        vm.deal(bob, 1 ether);

        // Perform transfer from bob to alice
        vm.prank(bob);
        moneyTransfer.transfer{value: 0.5 ether}(alice, 0.5 ether, "Test transfer");

        // Calculate expected received amount
        uint256 fee = 0.5 ether * moneyTransfer.baseFeePercent() / 10000; // 1% default fee
        uint256 expectedReceived = 0.5 ether - fee;

        // Verify alice has pending withdrawal
        assertEq(
            moneyTransfer.pendingWithdrawals(alice), expectedReceived, "Alice should have correct pending withdrawal"
        );

        // Alice withdraws her funds
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        moneyTransfer.withdrawFunds();

        // Verify alice received funds minus fee
        assertEq(alice.balance - aliceBalanceBefore, expectedReceived, "Alice should have received correct amount");
    }
}
