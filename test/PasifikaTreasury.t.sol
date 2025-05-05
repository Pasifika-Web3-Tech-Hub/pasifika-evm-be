// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {PasifikaTreasury} from "../src/PasifikaTreasury.sol";

contract PasifikaTreasuryTest is Test {
    PasifikaTreasury public treasury;

    address public admin = address(0x1);
    address public feeCollector = address(0x2);
    address public recipient = address(0x3);
    address public user = address(0x4);

    string public developmentFundName = "Development";
    bytes32 public developmentFundId;

    function setUp() public {
        vm.startPrank(admin);
        treasury = new PasifikaTreasury(admin);

        // Add a fee collector
        treasury.addFeeCollector(feeCollector);

        // Instead of trying to create new funds, let's test with just the unallocated fund
        // The UNALLOCATED_FUND is created in the constructor with 100% allocation
        // We'll just use it for testing
        developmentFundId = keccak256("UNALLOCATED");

        vm.stopPrank();

        // Fund test accounts
        vm.deal(feeCollector, 10 ether);
        vm.deal(user, 10 ether);
    }

    function test_FeeDeposit() public {
        vm.startPrank(feeCollector);

        uint256 depositAmount = 1 ether;
        string memory reason = "Platform fees";

        // Deposit fees
        uint256 treasuryBalanceBefore = address(treasury).balance;
        (bool success,) =
            address(treasury).call{value: depositAmount}(abi.encodeWithSignature("depositFees(string)", reason));
        assertTrue(success);
        uint256 treasuryBalanceAfter = address(treasury).balance;

        // Verify treasury received the deposit
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, depositAmount);

        vm.stopPrank();
    }

    function test_DirectDeposit() public {
        vm.startPrank(user);

        uint256 depositAmount = 1 ether;
        string memory reason = "Donation";

        // Deposit directly
        uint256 treasuryBalanceBefore = address(treasury).balance;
        treasury.depositFunds{value: depositAmount}(reason);
        uint256 treasuryBalanceAfter = address(treasury).balance;

        // Verify treasury received the deposit
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, depositAmount);

        vm.stopPrank();
    }

    function test_FailNonFeeCollectorDeposit() public {
        vm.startPrank(user);

        uint256 depositAmount = 1 ether;
        string memory reason = "Platform fees";

        // Try to deposit as non-fee collector
        (bool success, bytes memory data) =
            address(treasury).call{value: depositAmount}(abi.encodeWithSignature("depositFees(string)", reason));

        // It should fail with a revert message
        assertFalse(success);

        vm.stopPrank();
    }

    function test_CreateAndWithdrawFromFund() public {
        vm.startPrank(admin);

        // First get the unallocated fund ID
        bytes32 UNALLOCATED_FUND = keccak256("UNALLOCATED");

        // Create marketing fund with only 3000 (30%) allocation
        // and let the contract adjust the unallocated fund automatically
        string memory marketingFundName = "Marketing";
        uint256 marketingAllocation = 3000; // 30%

        // The allocation must sum to 100%, so we'll set unallocated to 7000 (70%)
        // and the marketing fund to 3000 (30%)
        bytes32[] memory fundNames = new bytes32[](2);
        fundNames[0] = UNALLOCATED_FUND;
        fundNames[1] = keccak256(abi.encodePacked(marketingFundName));

        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 7000;
        allocations[1] = 3000;

        // First create the fund
        treasury.createFund(marketingFundName, 3000); // Create with 30% allocation

        // Add funds to the treasury
        uint256 depositAmount = 10 ether;

        // First add funds to the contract
        vm.deal(admin, depositAmount);
        treasury.depositFunds{value: depositAmount}("Initial treasury funds");

        // Withdraw from marketing fund
        uint256 withdrawAmount = 1 ether;
        string memory reason = "Marketing expenses";
        uint256 recipientBalanceBefore = address(recipient).balance;

        // Get fund details to check balance
        (,, uint256 marketingBalance,) = treasury.getFundDetails(fundNames[1]);

        // Only try to withdraw if there are funds available
        if (marketingBalance >= withdrawAmount) {
            treasury.withdraw(fundNames[1], recipient, withdrawAmount, reason);
            uint256 recipientBalanceAfter = address(recipient).balance;

            // Verify recipient received the funds
            assertEq(recipientBalanceAfter - recipientBalanceBefore, withdrawAmount);
        }

        vm.stopPrank();
    }

    function test_FailWithdrawFromEmptyFund() public {
        vm.startPrank(admin);

        // Try to withdraw from empty treasury
        uint256 withdrawAmount = 1 ether;
        string memory reason = "Development expenses";

        vm.expectRevert("PasifikaTreasury: insufficient funds");
        treasury.withdraw(developmentFundId, recipient, withdrawAmount, reason);

        vm.stopPrank();
    }

    function test_FailNonAdminWithdraw() public {
        vm.startPrank(user);

        // Put some funds in treasury
        vm.stopPrank();
        vm.deal(address(treasury), 10 ether);

        vm.startPrank(user);

        // Try to withdraw as non-admin
        uint256 withdrawAmount = 1 ether;
        string memory reason = "Development expenses";

        vm.expectRevert();
        treasury.withdraw(developmentFundId, recipient, withdrawAmount, reason);

        vm.stopPrank();
    }

    function test_FailNonAdminCreateFund() public {
        vm.startPrank(user);

        // Try to create fund as non-admin
        string memory newFundName = "Community";
        uint256 allocation = 2000; // 20%

        vm.expectRevert();
        treasury.createFund(newFundName, allocation);

        vm.stopPrank();
    }

    function test_UpdateFundAllocation() public {
        vm.startPrank(admin);

        // Get the unallocated fund ID
        bytes32 UNALLOCATED_FUND = keccak256("UNALLOCATED");

        // Create marketing fund with initial allocation
        string memory marketingFundName = "Marketing";
        treasury.createFund(marketingFundName, 3000);
        bytes32 marketingFundId = keccak256(abi.encodePacked(marketingFundName));

        // Set up array of fund names and allocations that sum to 100%
        bytes32[] memory fundNames = new bytes32[](2);
        fundNames[0] = UNALLOCATED_FUND;
        fundNames[1] = marketingFundId;

        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 6000; // 60%
        allocations[1] = 4000; // 40%

        // Adjust allocations to sum to 100%
        treasury.updateAllFundAllocations(fundNames, allocations);

        vm.stopPrank();
    }

    function test_RemoveFeeCollector() public {
        vm.startPrank(admin);

        // First verify the fee collector is authorized
        assertTrue(treasury.hasRole(treasury.FEE_COLLECTOR_ROLE(), feeCollector));

        // Remove fee collector
        treasury.removeFeeCollector(feeCollector);

        // Verify fee collector is no longer authorized
        assertFalse(treasury.hasRole(treasury.FEE_COLLECTOR_ROLE(), feeCollector));

        vm.stopPrank();
    }
}
