// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/FeeManager.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

// Simple test token with minting capability
contract TestToken is ERC20, AccessControl, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }
    
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }
    
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
    
    function _update(address from, address to, uint256 value) 
        internal 
        override 
        whenNotPaused 
    {
        super._update(from, to, value);
    }
}

contract FeeManagerTest is Test {
    FeeManager public feeManager;
    TestToken public testToken;
    
    address public admin = address(1);
    address public treasury = address(2);
    address public communityFund = address(3);
    address public marketplace = address(4);
    address public creator = address(5);
    address public payer = address(6);
    address public paymentReceiver = address(7);
    address public collection = address(8);
    
    // Set initial balances
    uint256 public initialBalance = 100 ether;
    
    function setUp() public {
        // Set a fixed timestamp for testing
        vm.warp(1000000000);
        
        // Deploy mock ERC20 token
        vm.startPrank(admin);
        testToken = new TestToken("Test Token", "TEST");
        
        // Deploy FeeManager contract
        feeManager = new FeeManager(treasury, communityFund);
        
        // Set up roles
        feeManager.grantRole(feeManager.MARKETPLACE_ROLE(), marketplace);
        
        // Deal ether to test accounts
        vm.deal(payer, initialBalance);
        vm.deal(marketplace, initialBalance);
        
        // Mint test tokens
        testToken.mint(payer, initialBalance);
        testToken.mint(marketplace, initialBalance);
        
        // Set accepted token
        feeManager.setAcceptedToken(address(testToken));
        
        vm.stopPrank();
        
        // Approve token spending
        vm.startPrank(payer);
        testToken.approve(marketplace, type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(marketplace);
        testToken.approve(address(feeManager), type(uint256).max);
        vm.stopPrank();
    }
    
    function testDeployment() public view {
        // Verify contract deployment
        assert(address(feeManager) != address(0));
        
        // Verify role assignments
        assert(feeManager.hasRole(feeManager.DEFAULT_ADMIN_ROLE(), admin));
        assert(feeManager.hasRole(feeManager.FEE_ADMIN_ROLE(), admin));
        assert(feeManager.hasRole(feeManager.TREASURY_ROLE(), admin));
        assert(feeManager.hasRole(feeManager.MARKETPLACE_ROLE(), marketplace));
        
        // Verify addresses
        assertEq(feeManager.treasuryAddress(), treasury);
        assertEq(feeManager.communityFundAddress(), communityFund);
        assertEq(feeManager.acceptedTokenAddress(), address(testToken));
        assert(feeManager.acceptsNativeToken());
    }
    
    function testUpdateAddresses() public {
        address newTreasury = address(10);
        address newCommunityFund = address(11);
        
        vm.startPrank(admin);
        
        // Update treasury address
        feeManager.updateTreasuryAddress(newTreasury);
        assertEq(feeManager.treasuryAddress(), newTreasury);
        
        // Update community fund address
        feeManager.updateCommunityFundAddress(newCommunityFund);
        assertEq(feeManager.communityFundAddress(), newCommunityFund);
        
        vm.stopPrank();
    }
    
    function testFeeCalculation() public view {
        // Standard sale
        (
            uint256 feeAmount,
            uint256 creatorRoyalty,
            uint256 communityFund,
            uint256 platformFee
        ) = feeManager.calculateFee(
            1 ether,
            FeeManager.FeeType.StandardSale,
            payer,
            address(0)
        );
        
        // For a standard sale: 2.5% total (1% platform, 1% creator, 0.5% community)
        assertEq(feeAmount, 0.025 ether);
        assertEq(creatorRoyalty, 0.01 ether);
        assertEq(communityFund, 0.005 ether);
        assertEq(platformFee, 0.01 ether);
        
        // Verify total adds up
        assertEq(creatorRoyalty + communityFund + platformFee, feeAmount);
    }
    
    function testUpdateFeeConfiguration() public {
        vm.startPrank(admin);
        
        // Update fee configuration for standard sales
        feeManager.updateFeeConfiguration(
            FeeManager.FeeType.StandardSale,
            300, // 3% total
            150,  // 1.5% creator
            50,   // 0.5% community
            100,  // 1% platform
            true
        );
        
        (
            uint256 feeAmount,
            uint256 creatorRoyalty,
            uint256 communityFund,
            uint256 platformFee
        ) = feeManager.calculateFee(
            1 ether,
            FeeManager.FeeType.StandardSale,
            payer,
            address(0)
        );
        
        // Verify updated fees
        assertEq(feeAmount, 0.03 ether);
        assertEq(creatorRoyalty, 0.015 ether);
        assertEq(communityFund, 0.005 ether);
        assertEq(platformFee, 0.01 ether);
        
        vm.stopPrank();
    }
    
    function testVolumeDiscounts() public {
        vm.startPrank(admin);
        
        // Set up a custom discount tier
        feeManager.setVolumeDiscountTier(2 ether, 1000); // 10% discount at 2 ETH
        
        vm.stopPrank();
        
        // Process a transaction to build up spending
        vm.startPrank(marketplace);
        feeManager.processFee{value: 0.025 ether}(
            1 ether,
            FeeManager.FeeType.StandardSale,
            payer,
            paymentReceiver,
            creator,
            address(0)
        );
        
        // Process another transaction to go over the discount threshold
        feeManager.processFee{value: 0.025 ether}(
            1 ether,
            FeeManager.FeeType.StandardSale,
            payer,
            paymentReceiver,
            creator,
            address(0)
        );
        
        // Now payer has spent 2 ETH, should get a discount
        (
            uint256 feeAmount,
            ,
            ,
            
        ) = feeManager.calculateFee(
            1 ether,
            FeeManager.FeeType.StandardSale,
            payer,
            address(0)
        );
        
        // 2.5% base fee with 10% discount = 2.25%
        assertEq(feeAmount, 0.0225 ether);
        
        vm.stopPrank();
    }
    
    function testCommunityFeeOverride() public {
        vm.startPrank(admin);
        
        // Set a community fee override for a specific collection
        feeManager.setCommunityFeeOverride(collection, 200); // 2% community fee
        
        vm.stopPrank();
        
        // Calculate fee with the override
        (
            uint256 feeAmount,
            uint256 creatorRoyaltyAmount,
            uint256 communityFundAmount,
            uint256 platformFeeAmount
        ) = feeManager.calculateFee(
            1 ether,
            FeeManager.FeeType.StandardSale,
            payer,
            collection
        );
        
        // Log the values for debugging
        console.log("Fee amount:", feeAmount);
        console.log("Creator royalty:", creatorRoyaltyAmount);
        console.log("Community fund:", communityFundAmount);
        console.log("Platform fee:", platformFeeAmount);
        
        // The total fee amount should be 2.5% (0.025 ether)
        assertEq(feeAmount, 0.025 ether, "Fee amount incorrect");
        
        // When community fee override (2%) plus creator royalty (1%) exceeds total fee (2.5%),
        // the contract should scale them proportionally
        // Creator should get 1/3 of the fee and community fund should get 2/3 of the fee
        assertApproxEqAbs(communityFundAmount, 16667000000000000, 1000, "Community fund amount incorrect");
        assertApproxEqAbs(creatorRoyaltyAmount, 8333000000000000, 1000, "Creator royalty amount incorrect");
        
        // Platform fee should be zero since all fees go to creator/community
        assertEq(platformFeeAmount, 0, "Platform fee should be zero");
        
        // The total of all fees should equal the fee amount
        assertEq(creatorRoyaltyAmount + communityFundAmount + platformFeeAmount, feeAmount, "Fee distribution doesn't add up");
    }
    
    function testProcessFeeWithNativeToken() public {
        uint256 transactionAmount = 1 ether;
        uint256 expectedFeeAmount = 0.025 ether;
        
        uint256 treasuryBalanceBefore = treasury.balance;
        uint256 communityFundBalanceBefore = communityFund.balance;
        uint256 creatorBalanceBefore = creator.balance;
        
        vm.startPrank(marketplace);
        
        // Process a fee with native token
        uint256 transactionId = feeManager.processFee{value: expectedFeeAmount}(
            transactionAmount,
            FeeManager.FeeType.StandardSale,
            payer,
            paymentReceiver,
            creator,
            address(0)
        );
        
        vm.stopPrank();
        
        // Verify fee transaction record
        FeeManager.FeeTransaction memory transaction = feeManager.getFeeTransaction(transactionId);
        assertEq(transaction.transactionId, transactionId);
        assertEq(transaction.payer, payer);
        assertEq(transaction.paymentReceiver, paymentReceiver);
        assertEq(transaction.totalAmount, transactionAmount);
        assertEq(transaction.feeAmount, expectedFeeAmount);
        assertEq(transaction.processed, true);
        
        // Verify balances increased
        assertEq(treasury.balance - treasuryBalanceBefore, 0.01 ether);  // Platform fee
        assertEq(communityFund.balance - communityFundBalanceBefore, 0.005 ether);  // Community fund
        assertEq(creator.balance - creatorBalanceBefore, 0.01 ether);  // Creator royalty
    }
    
    function testProcessFeeWithERC20Token() public {
        uint256 transactionAmount = 1 ether;
        
        uint256 treasuryTokenBalanceBefore = testToken.balanceOf(treasury);
        uint256 communityFundTokenBalanceBefore = testToken.balanceOf(communityFund);
        uint256 creatorTokenBalanceBefore = testToken.balanceOf(creator);
        
        vm.startPrank(marketplace);
        
        // Disable native token to force ERC20 usage
        vm.stopPrank();
        vm.startPrank(admin);
        feeManager.setNativeTokenAcceptance(false);
        vm.stopPrank();
        vm.startPrank(marketplace);
        
        // Process a fee with ERC20 token
        uint256 transactionId = feeManager.processFee(
            transactionAmount,
            FeeManager.FeeType.StandardSale,
            payer,
            paymentReceiver,
            creator,
            address(0)
        );
        
        vm.stopPrank();
        
        // Verify fee transaction record
        FeeManager.FeeTransaction memory transaction = feeManager.getFeeTransaction(transactionId);
        assertEq(transaction.transactionId, transactionId);
        assertEq(transaction.processed, true);
        
        // Expected fee amounts
        uint256 expectedPlatformFee = 0.01 ether;
        uint256 expectedCommunityFee = 0.005 ether;
        uint256 expectedCreatorRoyalty = 0.01 ether;
        
        // Verify token balances increased
        assertEq(testToken.balanceOf(treasury) - treasuryTokenBalanceBefore, expectedPlatformFee);
        assertEq(testToken.balanceOf(communityFund) - communityFundTokenBalanceBefore, expectedCommunityFee);
        assertEq(testToken.balanceOf(creator) - creatorTokenBalanceBefore, expectedCreatorRoyalty);
    }
    
    function testPauseFunctionality() public {
        vm.startPrank(admin);
        
        // Pause the contract
        feeManager.pause();
        
        // Try to process a fee when paused - should revert
        vm.stopPrank();
        vm.startPrank(marketplace);
        vm.expectRevert(); // Generic expectRevert
        feeManager.processFee{value: 0.025 ether}(
            1 ether,
            FeeManager.FeeType.StandardSale,
            payer,
            paymentReceiver,
            creator,
            address(0)
        );
        
        // Unpause the contract
        vm.stopPrank();
        vm.startPrank(admin);
        feeManager.unpause();
        
        // Try to process a fee after unpausing - should succeed
        vm.stopPrank();
        vm.startPrank(marketplace);
        uint256 transactionId = feeManager.processFee{value: 0.025 ether}(
            1 ether,
            FeeManager.FeeType.StandardSale,
            payer,
            paymentReceiver,
            creator,
            address(0)
        );
        
        // Verify transaction was processed
        FeeManager.FeeTransaction memory transaction = feeManager.getFeeTransaction(transactionId);
        assertEq(transaction.processed, true);
        
        vm.stopPrank();
    }
    
    function testWithdrawExcessFunds() public {
        // Send some ETH to the contract
        vm.deal(address(feeManager), 1 ether);
        
        uint256 treasuryBalanceBefore = treasury.balance;
        
        vm.startPrank(admin);
        
        // Withdraw excess funds
        feeManager.withdrawExcessFunds(0.5 ether);
        
        vm.stopPrank();
        
        // Verify treasury balance increased
        assertEq(treasury.balance - treasuryBalanceBefore, 0.5 ether);
    }
    
    function testWithdrawExcessTokens() public {
        // Mint some tokens to the contract
        vm.startPrank(admin);
        testToken.mint(address(feeManager), 1 ether);
        
        uint256 treasuryTokenBalanceBefore = testToken.balanceOf(treasury);
        
        // Withdraw excess tokens
        feeManager.withdrawExcessTokens(address(testToken), 0.5 ether);
        
        vm.stopPrank();
        
        // Verify treasury token balance increased
        assertEq(testToken.balanceOf(treasury) - treasuryTokenBalanceBefore, 0.5 ether);
    }
}
