// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {PasifikaTreasury} from "../src/PasifikaTreasury.sol";
import {MockToken} from "../src/MockToken.sol";

contract PasifikaTreasuryTest is Test {
    PasifikaTreasury public treasury;
    MockToken public pasifikaToken;
    
    address public admin = address(1);
    address public treasuryManager = address(2);
    address public approver1 = address(3);
    address public approver2 = address(4);
    address public user = address(5);
    address public recipient = address(6);
    address public treasuryWallet = address(7);
    
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10**18;
    uint256 public constant TREASURY_INITIAL_FUNDS = 100_000 * 10**18;
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TREASURY_MANAGER_ROLE = keccak256("TREASURY_MANAGER_ROLE");
    bytes32 public constant APPROVER_ROLE = keccak256("APPROVER_ROLE");
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy token and mint to admin
        pasifikaToken = new MockToken("Pasifika Token", "PSF");
        pasifikaToken.mint(admin, INITIAL_SUPPLY);
        
        // Deploy treasury contract
        treasury = new PasifikaTreasury(pasifikaToken, treasuryWallet);
        
        // Setup roles
        treasury.grantRole(TREASURY_MANAGER_ROLE, treasuryManager);
        treasury.grantRole(APPROVER_ROLE, approver1);
        treasury.grantRole(APPROVER_ROLE, approver2);
        
        // Fund treasury
        pasifikaToken.transfer(address(treasury), TREASURY_INITIAL_FUNDS);
        
        vm.stopPrank();
    }
    
    function testInitialSetup() public {
        assertEq(treasury.getTreasuryBalance(), TREASURY_INITIAL_FUNDS);
        assertEq(address(treasury.pasifikaToken()), address(pasifikaToken));
        assertEq(treasury.treasuryWallet(), treasuryWallet);
        assertEq(treasury.minApprovals(), 2);
        
        assertTrue(treasury.hasRole(ADMIN_ROLE, admin));
        assertTrue(treasury.hasRole(TREASURY_MANAGER_ROLE, admin));
        assertTrue(treasury.hasRole(TREASURY_MANAGER_ROLE, treasuryManager));
        assertTrue(treasury.hasRole(APPROVER_ROLE, approver1));
        assertTrue(treasury.hasRole(APPROVER_ROLE, approver2));
    }
    
    function testCreateCategory() public {
        vm.startPrank(treasuryManager);
        
        uint256 categoryId = treasury.createCategory("Development");
        assertEq(categoryId, 2); // First one is created in constructor
        
        (string memory name, , , , bool active) = treasury.getCategoryDetails(categoryId);
        assertEq(name, "Development");
        assertTrue(active);
        
        vm.stopPrank();
    }
    
    function testUpdateCategory() public {
        vm.startPrank(treasuryManager);
        
        uint256 categoryId = treasury.createCategory("Development");
        treasury.updateCategory(categoryId, "Research & Development", true);
        
        (string memory name, , , , bool active) = treasury.getCategoryDetails(categoryId);
        assertEq(name, "Research & Development");
        assertTrue(active);
        
        // Test deactivation
        treasury.updateCategory(categoryId, "Research & Development", false);
        (name, , , , active) = treasury.getCategoryDetails(categoryId);
        assertFalse(active);
        
        vm.stopPrank();
    }
    
    function testAllocateBudget() public {
        vm.startPrank(treasuryManager);
        
        uint256 categoryId = treasury.createCategory("Development");
        uint256 amount = 10_000 * 10**18;
        
        treasury.allocateBudget(categoryId, amount);
        
        (,uint256 allocated, uint256 spent, uint256 available,) = treasury.getCategoryDetails(categoryId);
        assertEq(allocated, amount);
        assertEq(spent, 0);
        assertEq(available, amount);
        
        vm.stopPrank();
    }
    
    function testProposeSpending() public {
        vm.startPrank(treasuryManager);
        
        uint256 categoryId = treasury.createCategory("Development");
        uint256 allocatedAmount = 10_000 * 10**18;
        uint256 spendAmount = 1_000 * 10**18;
        
        treasury.allocateBudget(categoryId, allocatedAmount);
        
        uint256 spendingId = treasury.proposeSpending(categoryId, spendAmount, payable(recipient));
        assertEq(spendingId, 1);
        
        (
            uint256 propCategoryId,
            uint256 propAmount,
            address propRecipient,
            uint256 approvalCount,
            bool executed,
            bool cancelled
        ) = treasury.getProposalDetails(spendingId);
        
        assertEq(propCategoryId, categoryId);
        assertEq(propAmount, spendAmount);
        assertEq(propRecipient, recipient);
        assertEq(approvalCount, 0);
        assertFalse(executed);
        assertFalse(cancelled);
        
        vm.stopPrank();
    }
    
    function testApproveAndExecuteSpending() public {
        vm.startPrank(treasuryManager);
        
        uint256 categoryId = treasury.createCategory("Development");
        uint256 allocatedAmount = 10_000 * 10**18;
        uint256 spendAmount = 1_000 * 10**18;
        
        treasury.allocateBudget(categoryId, allocatedAmount);
        uint256 spendingId = treasury.proposeSpending(categoryId, spendAmount, payable(recipient));
        
        vm.stopPrank();
        
        // First approver
        vm.prank(approver1);
        treasury.approveSpending(spendingId);
        
        // Get details after first approval
        (
            uint256 propCategoryId,
            uint256 propAmount,
            address propRecipient,
            uint256 approvalCount,
            bool executed,
            bool cancelled
        ) = treasury.getProposalDetails(spendingId);
        assertEq(approvalCount, 1);
        
        // Check if approval was recorded
        assertTrue(treasury.hasApproved(spendingId, approver1));
        assertFalse(treasury.hasApproved(spendingId, approver2));
        
        // Second approver
        vm.prank(approver2);
        treasury.approveSpending(spendingId);
        
        // Get details after second approval
        (
            propCategoryId,
            propAmount,
            propRecipient,
            approvalCount,
            executed,
            cancelled
        ) = treasury.getProposalDetails(spendingId);
        assertEq(approvalCount, 2);
        
        // Execute spending
        uint256 recipientBalanceBefore = pasifikaToken.balanceOf(recipient);
        
        vm.prank(treasuryManager);
        treasury.executeSpending(spendingId);
        
        // Check execution results
        (
            propCategoryId,
            propAmount,
            propRecipient,
            approvalCount,
            executed,
            cancelled
        ) = treasury.getProposalDetails(spendingId);
        assertTrue(executed);
        
        // Check budget category was updated
        (, uint256 allocated, uint256 spent, uint256 available,) = treasury.getCategoryDetails(categoryId);
        assertEq(allocated, allocatedAmount);
        assertEq(spent, spendAmount);
        assertEq(available, allocatedAmount - spendAmount);
        
        // Check recipient received funds
        uint256 recipientBalanceAfter = pasifikaToken.balanceOf(recipient);
        assertEq(recipientBalanceAfter - recipientBalanceBefore, spendAmount);
    }
    
    function testCancelSpending() public {
        vm.startPrank(treasuryManager);
        
        uint256 categoryId = treasury.createCategory("Development");
        uint256 allocatedAmount = 10_000 * 10**18;
        uint256 spendAmount = 1_000 * 10**18;
        
        treasury.allocateBudget(categoryId, allocatedAmount);
        uint256 spendingId = treasury.proposeSpending(categoryId, spendAmount, payable(recipient));
        
        treasury.cancelSpending(spendingId);
        
        (
            uint256 propCategoryId,
            uint256 propAmount,
            address propRecipient,
            uint256 approvalCount,
            bool executed,
            bool cancelled
        ) = treasury.getProposalDetails(spendingId);
        assertFalse(executed);
        assertTrue(cancelled);
        
        vm.stopPrank();
    }
    
    function testDepositFunds() public {
        uint256 amount = 5_000 * 10**18;
        uint256 initialBalance = treasury.getTreasuryBalance();
        
        // Transfer tokens to user for testing deposits
        vm.prank(admin);
        pasifikaToken.transfer(user, amount);
        
        // Approve and deposit from user
        vm.startPrank(user);
        pasifikaToken.approve(address(treasury), amount);
        treasury.depositFunds(amount);
        vm.stopPrank();
        
        // Check treasury balance increased
        assertEq(treasury.getTreasuryBalance(), initialBalance + amount);
    }
    
    function testFailInsufficientApprovals() public {
        vm.startPrank(treasuryManager);
        
        uint256 categoryId = treasury.createCategory("Development");
        uint256 allocatedAmount = 10_000 * 10**18;
        uint256 spendAmount = 1_000 * 10**18;
        
        treasury.allocateBudget(categoryId, allocatedAmount);
        uint256 spendingId = treasury.proposeSpending(categoryId, spendAmount, payable(recipient));
        
        // Only one approval (need 2)
        vm.stopPrank();
        vm.prank(approver1);
        treasury.approveSpending(spendingId);
        
        // Try to execute with insufficient approvals (should fail)
        vm.prank(treasuryManager);
        treasury.executeSpending(spendingId);
    }
    
    function testFailExceedBudget() public {
        vm.startPrank(treasuryManager);
        
        uint256 categoryId = treasury.createCategory("Development");
        uint256 allocatedAmount = 10_000 * 10**18;
        uint256 spendAmount = 15_000 * 10**18; // Greater than allocated
        
        treasury.allocateBudget(categoryId, allocatedAmount);
        
        // Should fail as spend amount exceeds allocated budget
        treasury.proposeSpending(categoryId, spendAmount, payable(recipient));
        
        vm.stopPrank();
    }
    
    function testFailInactiveCategory() public {
        vm.startPrank(treasuryManager);
        
        uint256 categoryId = treasury.createCategory("Development");
        uint256 allocatedAmount = 10_000 * 10**18;
        
        // Deactivate category
        treasury.updateCategory(categoryId, "Development", false);
        
        // Should fail as category is inactive
        treasury.allocateBudget(categoryId, allocatedAmount);
        
        vm.stopPrank();
    }
    
    function testUpdateTreasuryWallet() public {
        address newTreasuryWallet = address(8);
        
        vm.prank(admin);
        treasury.setTreasuryWallet(newTreasuryWallet);
        
        assertEq(treasury.treasuryWallet(), newTreasuryWallet);
    }
    
    function testRecoverTokens() public {
        // Deploy another token for testing recovery
        MockToken testToken = new MockToken("Test Token", "TEST");
        
        uint256 amount = 100 * 10**18;
        address recoveryRecipient = address(9);
        
        // Transfer some test tokens to treasury by mistake
        vm.prank(admin);
        testToken.mint(admin, amount);
        
        vm.prank(admin);
        testToken.transfer(address(treasury), amount);
        
        // Recover the tokens
        vm.prank(admin);
        treasury.recoverTokens(testToken, amount, recoveryRecipient);
        
        // Check recipient received the tokens
        assertEq(testToken.balanceOf(recoveryRecipient), amount);
    }
}
