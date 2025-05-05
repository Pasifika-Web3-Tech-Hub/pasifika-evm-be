// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/PasifikaMoneyTransfer.sol";
import "../src/ArbitrumTokenAdapter.sol";
import "../src/PasifikaArbitrumNode.sol";
import "../src/PasifikaTreasury.sol";
import "../src/PasifikaMembership.sol";

contract PasifikaMoneyTransferTest is Test {
    PasifikaMoneyTransfer public moneyTransfer;
    ArbitrumTokenAdapter public tokenAdapter;
    PasifikaArbitrumNode public arbitrumNode;
    PasifikaTreasury public treasury;
    PasifikaMembership public membership;

    address public deployer;
    address public treasuryWallet;
    address public recipient;

    uint256 public initialBalance = 10 ether;
    uint256 public treasuryInitialBalance = 5 ether;

    function setUp() public {
        // Create test accounts with meaningful names
        deployer = makeAddr("deployer");
        treasuryWallet = makeAddr("treasuryWallet");
        recipient = makeAddr("recipient");

        // Give deployer and other accounts some ETH
        vm.deal(deployer, initialBalance);
        vm.deal(recipient, 0.1 ether);

        vm.startPrank(deployer);

        // Deploy token adapter for Arbitrum
        tokenAdapter = new ArbitrumTokenAdapter(deployer);

        // Deploy Arbitrum node
        arbitrumNode = new PasifikaArbitrumNode(deployer);

        // Deploy treasury and grant necessary roles
        treasury = new PasifikaTreasury(deployer);

        // Ensure deployer has all necessary roles in treasury
        treasury.grantRole(treasury.DEFAULT_ADMIN_ROLE(), deployer);
        treasury.grantRole(treasury.ADMIN_ROLE(), deployer);
        treasury.grantRole(treasury.TREASURER_ROLE(), deployer);
        treasury.grantRole(treasury.SPENDER_ROLE(), deployer);

        // Fund treasury with ETH
        treasury.depositFunds{value: treasuryInitialBalance}("Initial treasury funding");

        // Deploy membership and grant necessary roles
        membership = new PasifikaMembership(payable(address(treasury)));

        // Ensure membership has proper roles in treasury
        treasury.grantRole(treasury.SPENDER_ROLE(), address(membership));
        treasury.addFeeCollector(address(membership));

        // Grant deployer all necessary roles in membership
        membership.grantRole(membership.DEFAULT_ADMIN_ROLE(), deployer);
        membership.grantRole(membership.ADMIN_ROLE(), deployer);
        membership.grantRole(membership.MEMBERSHIP_MANAGER_ROLE(), deployer);
        membership.grantRole(membership.PROFIT_SHARING_MANAGER_ROLE(), deployer);

        // Deploy money transfer
        moneyTransfer = new PasifikaMoneyTransfer(
            payable(address(tokenAdapter)), payable(treasuryWallet), payable(address(treasury))
        );

        // Grant roles for money transfer
        moneyTransfer.grantRole(moneyTransfer.DEFAULT_ADMIN_ROLE(), deployer);
        moneyTransfer.grantRole(moneyTransfer.FEE_MANAGER_ROLE(), deployer);
        moneyTransfer.grantRole(moneyTransfer.PAUSER_ROLE(), deployer);

        // Setup money transfer
        treasury.addFeeCollector(address(moneyTransfer));
        treasury.grantRole(treasury.SPENDER_ROLE(), address(moneyTransfer));

        moneyTransfer.initializeTreasury();

        // Set fees on money transfer
        moneyTransfer.setBaseFeePercent(100); // 1%
        moneyTransfer.setMemberFeePercent(50); // 0.5%
        moneyTransfer.setValidatorFeePercent(25); // 0.25%
        moneyTransfer.setMembershipContract(payable(address(membership)));
        moneyTransfer.setNodeContract(payable(address(arbitrumNode)));

        vm.stopPrank();
    }

    function testDirectTransfer() public {
        // Setup
        uint256 transferAmount = 1 ether;
        vm.deal(deployer, initialBalance);

        // Execute transfer
        vm.startPrank(deployer);
        uint256 txId = moneyTransfer.transfer{value: transferAmount}(recipient, transferAmount, "Test transfer");
        vm.stopPrank();

        // Validate - don't check status as transaction completes immediately
        // Just check that transaction ID is valid
        assertGt(txId, 0, "Transaction ID should be greater than 0");

        // Calculate expected fee (1%)
        uint256 expectedFee = transferAmount * 100 / 10000; // 1% fee
        uint256 expectedRecipientAmount = transferAmount - expectedFee;

        // Check recipient balance (handled in pendingWithdrawals)
        assertEq(
            moneyTransfer.pendingWithdrawals(recipient),
            expectedRecipientAmount,
            "Recipient should have pending withdrawal"
        );

        // Recipient should be able to withdraw funds
        uint256 recipientBalanceBefore = recipient.balance;
        vm.startPrank(recipient);
        moneyTransfer.withdrawFunds();
        vm.stopPrank();

        // Check recipient got their funds
        assertEq(
            recipient.balance - recipientBalanceBefore,
            expectedRecipientAmount,
            "Recipient should have received correct amount"
        );
    }

    function testMemberDiscount() public {
        // Setup
        uint256 transferAmount = 1 ether;
        vm.deal(deployer, initialBalance);

        // Make deployer a member (Tier 2 - Node Operator with 75% discount)
        vm.startPrank(deployer);
        tokenAdapter.assignTier(deployer, 2); // Set as tier 2 (Node Operator)
        vm.stopPrank();

        // Execute transfer with member discount
        vm.startPrank(deployer);
        moneyTransfer.transfer{value: transferAmount}(recipient, transferAmount, "Member transfer");
        vm.stopPrank();

        // Calculate expected fee (0.25% for tier 2 node operators - 75% discount)
        uint256 expectedFee = transferAmount * 25 / 10000; // 0.25% fee
        uint256 expectedRecipientAmount = transferAmount - expectedFee;

        // Check recipient amount
        assertEq(
            moneyTransfer.pendingWithdrawals(recipient),
            expectedRecipientAmount,
            "Recipient should have correct pending withdrawal with member discount"
        );
    }

    function testFeeDistribution() public {
        // Setup
        uint256 transferAmount = 1 ether;
        vm.deal(deployer, initialBalance);

        // Get initial treasury balance
        uint256 initialTreasuryBalance = address(treasury).balance;

        // Execute transfer
        vm.startPrank(deployer);
        moneyTransfer.transfer{value: transferAmount}(recipient, transferAmount, "Test fee distribution");
        vm.stopPrank();

        // Calculate expected fee
        uint256 expectedFee = transferAmount * 100 / 10000; // 1% fee

        // Check treasury received fees
        uint256 treasuryBalance = address(treasury).balance;
        assertEq(treasuryBalance, initialTreasuryBalance + expectedFee, "Treasury should have received fees");
    }
}
