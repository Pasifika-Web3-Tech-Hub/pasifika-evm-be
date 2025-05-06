// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./ArbitrumTokenAdapter.sol";
import "./PasifikaMembership.sol";
import "./PasifikaTreasury.sol";
import "./PasifikaArbitrumNode.sol";

/**
 * @title PasifikaMoneyTransfer
 * @dev Handles money transfers between users on Pasifika platform
 * Supports direct transfers, scheduled transfers, conditional transfers
 * Features fee management with membership discounts
 * Optimized for Arbitrum network using native ETH
 */
contract PasifikaMoneyTransfer is AccessControl, Pausable, ReentrancyGuard {
    // Simple counter implementation to replace OpenZeppelin Counters
    struct Counter {
        uint256 _value; // default: 0
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function increment(Counter storage counter) internal {
        counter._value += 1;
    }

    function decrement(Counter storage counter) internal {
        counter._value = counter._value - 1;
    }

    function reset(Counter storage counter) internal {
        counter._value = 0;
    }

    // Roles
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // Transaction types
    enum TransactionType {
        Direct,
        Scheduled,
        Conditional
    }

    // Transaction status
    enum TransactionStatus {
        Pending,
        Completed,
        Cancelled,
        Disputed
    }

    // Condition types for conditional transfers
    enum ConditionType {
        None,
        TimeDelay,
        MultiSig,
        DocumentVerification,
        ExternalOracle
    }

    // Transaction struct
    struct Transaction {
        uint256 id;
        address sender;
        address receiver;
        uint256 amount;
        uint256 fee;
        TransactionType transactionType;
        TransactionStatus status;
        uint256 createdAt;
        uint256 executedAt;
        ConditionType conditionType;
        bytes conditionData;
        string memo;
        bool isDisputed;
        address[] approvers;
        mapping(address => bool) hasApproved;
        uint256 requiredApprovals;
    }

    // Scheduled transfer structure
    struct ScheduledTransfer {
        address sender;
        address recipient;
        uint256 amount;
        uint256 interval; // Time in seconds between transfers
        uint256 nextExecutionTime;
        uint256 remainingTransfers; // 0 means indefinite
        bool active;
        string memo;
    }

    // Community collection structure
    struct CommunityCollection {
        address creator;
        string purpose;
        uint256 goal;
        uint256 collected;
        uint256 deadline;
        bool active;
    }

    // Remittance record
    struct RemittanceRecord {
        uint256 transactionId;
        string senderInfo; // IPFS hash to sender KYC/verification
        string receiverInfo; // IPFS hash to receiver information
        string paymentDetails; // Additional payment details specific to remittance
        string countryCode; // ISO country code for destination
        uint256 localCurrencyAmount; // Amount in local currency (in smallest unit)
        string localCurrencyCode; // Currency code (e.g., USD, EUR)
        uint256 exchangeRate; // Exchange rate used (in basis points)
    }

    // Transaction record for simplified view
    struct TransactionRecord {
        address sender;
        address recipient;
        uint256 amount;
        uint256 fee;
        uint256 timestamp;
        string memo;
        TransactionType transactionType;
        TransactionStatus status;
    }

    // Core adapter for tier benefits
    ArbitrumTokenAdapter public arbitrumTokenAdapter;

    // Membership contract for fee discounts
    PasifikaMembership public membershipContract;

    // Node contract for validator nodes
    PasifikaArbitrumNode public nodeContract;

    // Treasury contract
    PasifikaTreasury public treasury;

    // Recipient address => amount
    mapping(address => uint256) public pendingWithdrawals;

    // Sender => recipient => last transfer time
    mapping(address => mapping(address => uint256)) public lastTransferTime;

    // User => total sent in last 24 hours
    mapping(address => uint256) public dailySentAmount;
    mapping(address => uint256) public dailySentTimestamp;

    // Daily limit
    uint256 public dailyLimit = 500 ether; // 500 ETH daily limit by default

    // Base fee percent in basis points (100 = 1%)
    uint256 public baseFeePercent = 100; // 1% base fee

    // Member fee percent in basis points (50 = 0.5%)
    uint256 public memberFeePercent = 50; // 0.5% for members

    // Validator fee percent in basis points (25 = 0.25%)
    uint256 public validatorFeePercent = 25; // 0.25% for validators

    // Tier discounts (tier level => discount percentage in basis points)
    mapping(uint256 => uint256) public tierDiscounts;

    // Min and max fee amounts
    uint256 public minFee = 0.0001 ether; // Minimum fee 0.0001 ETH
    uint256 public maxFee = 1 ether; // Maximum fee 1 ETH

    // Transaction counter
    Counter private _transactionIdCounter;

    // Scheduled transfer counter
    Counter private _scheduledTransferIdCounter;

    // Community collection counter
    Counter private _communityCollectionIdCounter;

    // Transaction mappings
    mapping(uint256 => Transaction) private _transactions;

    // Remittance records
    mapping(uint256 => RemittanceRecord) private _remittanceRecords;

    // Scheduled transfer mapping
    mapping(uint256 => ScheduledTransfer) public scheduledTransfers;

    // Community collection mapping
    mapping(uint256 => CommunityCollection) public communityCollections;

    // User transaction history
    mapping(address => uint256[]) private _userSentTransactions;
    mapping(address => uint256[]) private _userReceivedTransactions;

    // Events
    event TransactionCreated(
        uint256 indexed transactionId,
        address indexed sender,
        address indexed receiver,
        uint256 amount,
        TransactionType transactionType
    );
    event TransactionCompleted(uint256 indexed transactionId, uint256 timestamp);
    event TransactionCancelled(uint256 indexed transactionId, uint256 timestamp);
    event TransactionDisputed(uint256 indexed transactionId, string reason);
    event FeeUpdated(uint256 baseFee, uint256 memberFee, uint256 validatorFee);
    event TreasuryUpdated(address indexed newTreasury);
    event MembershipContractUpdated(address indexed newMembershipContract);
    event NodeContractUpdated(address indexed newNodeContract);
    event FundsWithdrawn(address indexed recipient, uint256 amount);
    event ScheduledTransferCreated(
        uint256 indexed transferId,
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint256 interval,
        uint256 repetitions
    );
    event ScheduledTransferCancelled(uint256 indexed transferId);
    event CommunityCollectionCreated(
        uint256 indexed collectionId, address indexed creator, string purpose, uint256 goal, uint256 deadline
    );
    event ContributionMade(uint256 indexed collectionId, address indexed contributor, uint256 amount);
    event RemittanceCreated(uint256 indexed transactionId, string countryCode, string currencyCode);

    /**
     * @dev Constructor for PasifikaMoneyTransfer
     * @param _arbitrumTokenAdapter Address of Arbitrum Token Adapter
     * @param _treasuryWallet Address for treasury wallet
     * @param _treasury Address of treasury contract
     */
    constructor(address payable _arbitrumTokenAdapter, address payable _treasuryWallet, address payable _treasury) {
        require(_arbitrumTokenAdapter != address(0), "PasifikaMoneyTransfer: zero address");
        require(_treasuryWallet != address(0), "PasifikaMoneyTransfer: zero address");

        // Initialize token adapter
        arbitrumTokenAdapter = ArbitrumTokenAdapter(_arbitrumTokenAdapter);

        // Set treasury wallet
        treasuryWallet = _treasuryWallet;

        // Set treasury contract if provided
        if (_treasury != address(0)) {
            treasury = PasifikaTreasury(_treasury);
        }

        // Grant admin role to deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FEE_MANAGER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);

        // Initialize the counter
        increment(_transactionIdCounter);

        // Set tier discounts - discount percentages for each tier level
        // Note: Tier 0 (Guest) gets no discount (1% fee)
        tierDiscounts[1] = 50; // Tier 1: Member - 50% discount (0.5% fee)
        tierDiscounts[2] = 75; // Tier 2: Member Node Operator - 75% discount (0.25% fee)
    }

    /**
     * @dev Initialize a new transaction record
     * @param transactionId ID of the new transaction
     * @param sender Sender address
     * @param recipient Recipient address
     * @param amount Transaction amount
     * @param fee Transaction fee
     * @param txType Transaction type
     * @param memo Transaction memo
     */
    function _initializeTransaction(
        uint256 transactionId,
        address sender,
        address recipient,
        uint256 amount,
        uint256 fee,
        TransactionType txType,
        string memory memo
    ) internal {
        _transactions[transactionId].id = transactionId;
        _transactions[transactionId].sender = sender;
        _transactions[transactionId].receiver = recipient;
        _transactions[transactionId].amount = amount;
        _transactions[transactionId].fee = fee;
        _transactions[transactionId].transactionType = txType;
        _transactions[transactionId].status = TransactionStatus.Pending;
        _transactions[transactionId].createdAt = block.timestamp;
        _transactions[transactionId].executedAt = 0;
        _transactions[transactionId].conditionType = ConditionType.None;
        _transactions[transactionId].memo = memo;
        _transactions[transactionId].isDisputed = false;
        _transactions[transactionId].requiredApprovals = 0;
    }

    /**
     * @dev Transfer ETH to a recipient
     * @param recipient Address of the recipient
     * @param amount Amount to transfer in wei
     * @param memo Transaction memo
     * @return uint256 ID of the transaction
     */
    function transfer(address recipient, uint256 amount, string memory memo)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        require(recipient != address(0), "PasifikaMoneyTransfer: invalid recipient");
        require(recipient != msg.sender, "PasifikaMoneyTransfer: cannot send to self");
        require(amount > 0, "PasifikaMoneyTransfer: amount must be positive");
        require(msg.value >= amount, "PasifikaMoneyTransfer: insufficient funds");

        // Calculate fee
        uint256 fee = calculateFee(amount, msg.sender);
        uint256 amountAfterFee = amount - fee;

        // Record the transfer
        pendingWithdrawals[recipient] += amountAfterFee;

        // Send fee to treasury
        if (fee > 0) {
            // Use the depositFees function in the treasury
            treasury.depositFees{ value: fee }("Money transfer fee");
        }

        // Update last transfer time
        lastTransferTime[msg.sender][recipient] = block.timestamp;

        // Record transaction for profit sharing eligibility (if membership contract is set)
        if (address(membershipContract) != address(0)) {
            try PasifikaMembership(membershipContract).recordTransaction(msg.sender, amount) { } catch { }
        }

        // Create transaction record
        uint256 transactionId = current(_transactionIdCounter);
        increment(_transactionIdCounter);

        // Initialize the transaction
        _initializeTransaction(transactionId, msg.sender, recipient, amountAfterFee, fee, TransactionType.Direct, memo);

        // Add to user's transactions
        _userSentTransactions[msg.sender].push(transactionId);
        _userReceivedTransactions[recipient].push(transactionId);

        emit TransactionCreated(transactionId, msg.sender, recipient, amountAfterFee, TransactionType.Direct);

        return transactionId;
    }

    // Rest of contract methods unchanged

    /**
     * @dev Calculate fee based on user's tier
     * @param amount Amount to calculate fee for
     * @param sender Address of the sender
     * @return uint256 Fee amount in wei
     */
    function calculateFee(uint256 amount, address sender) public view returns (uint256) {
        uint256 feePercent = baseFeePercent; // Default fee percent (1%)

        // Check if sender has a tier in the adapter
        if (address(arbitrumTokenAdapter) != address(0)) {
            uint256 tier = arbitrumTokenAdapter.getUserTier(sender);

            // Apply tier discount if applicable
            if (tier > 0 && tierDiscounts[tier] > 0) {
                // Calculate discounted fee percent
                uint256 discount = (baseFeePercent * tierDiscounts[tier]) / 100;
                feePercent = baseFeePercent - discount;
            }
        }

        // Calculate fee amount
        uint256 feeAmount = (amount * feePercent) / 10000;

        // Ensure fee is within limits
        if (feeAmount < minFee) {
            feeAmount = minFee;
        } else if (feeAmount > maxFee) {
            feeAmount = maxFee;
        }

        return feeAmount;
    }

    /**
     * @dev Allow receiving ETH
     */
    receive() external payable { }

    /**
     * @dev Withdraw pending funds
     * Allows a user to withdraw any ETH that has been sent to them
     */
    function withdrawFunds() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "PasifikaMoneyTransfer: no funds to withdraw");

        // Reset pending withdrawal before sending to prevent reentrancy attacks
        pendingWithdrawals[msg.sender] = 0;

        // Send the funds
        (bool success,) = msg.sender.call{ value: amount }("");
        require(success, "PasifikaMoneyTransfer: transfer failed");

        emit FundsWithdrawn(msg.sender, amount);
    }

    /**
     * @dev Set the membership contract
     * @param _membershipContract Address of the PasifikaMembership contract
     */
    function setMembershipContract(address payable _membershipContract) external onlyRole(ADMIN_ROLE) {
        require(_membershipContract != address(0), "PasifikaMoneyTransfer: zero address");
        membershipContract = PasifikaMembership(_membershipContract);
        emit MembershipContractUpdated(_membershipContract);
    }

    /**
     * @dev Set the node contract
     * @param _nodeContract Address of the PasifikaArbitrumNode contract
     */
    function setNodeContract(address payable _nodeContract) external onlyRole(ADMIN_ROLE) {
        require(_nodeContract != address(0), "PasifikaMoneyTransfer: zero address");
        nodeContract = PasifikaArbitrumNode(_nodeContract);
        emit NodeContractUpdated(_nodeContract);
    }

    /**
     * @dev Initialize the treasury integration
     * This is called once after deployment to register the money transfer contract as fee collector
     */
    function initializeTreasury() external onlyRole(ADMIN_ROLE) {
        // Request to be added as a fee collector
        treasury.addFeeCollector(address(this));
    }

    /**
     * @dev Set the base fee percentage (for non-members)
     * @param _feePercent Fee percentage in basis points (100 = 1%)
     */
    function setBaseFeePercent(uint256 _feePercent) external onlyRole(FEE_MANAGER_ROLE) {
        require(_feePercent <= 1000, "PasifikaMoneyTransfer: fee too high"); // Maximum 10%
        baseFeePercent = _feePercent;
    }

    /**
     * @dev Set the member fee percentage
     * @param _feePercent Fee percentage in basis points (50 = 0.5%)
     */
    function setMemberFeePercent(uint256 _feePercent) external onlyRole(FEE_MANAGER_ROLE) {
        require(_feePercent <= baseFeePercent, "PasifikaMoneyTransfer: member fee must be lower than base fee");
        memberFeePercent = _feePercent;
    }

    /**
     * @dev Set the validator fee percentage
     * @param _feePercent Fee percentage in basis points (25 = 0.25%)
     */
    function setValidatorFeePercent(uint256 _feePercent) external onlyRole(FEE_MANAGER_ROLE) {
        require(_feePercent <= memberFeePercent, "PasifikaMoneyTransfer: validator fee must be lower than member fee");
        validatorFeePercent = _feePercent;
    }

    // Treasury wallet
    address payable public treasuryWallet;
}
