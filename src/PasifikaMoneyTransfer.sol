// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./ArbitrumTokenAdapter.sol";
import "./PasifikaMembership.sol";
import "./PasifikaTreasury.sol";
import "./PasifikaArbitrumNode.sol";

/**
 * @title PasifikaMoneyTransfer
 * @dev Handles money transfers between users on Pasifika platform
 * Supports direct transfers, scheduled transfers, conditional transfers
 * Features fee management with membership discounts
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

    // Membership contract for member fee discounts
    PasifikaMembership public membershipContract;

    // Node contract for validators
    PasifikaArbitrumNode public nodeContract;

    // Treasury wallet
    address payable public treasuryWallet;

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
    uint256 public dailyTransferLimit = 1000 ether; // 1000 ETH per day

    // Default fee percentages (in basis points - 10000 = 100%)
    uint256 public baseFeePercent = 100; // 1% base fee for guests
    uint256 public memberFeePercent = 50; // 0.5% fee for members
    uint256 public validatorFeePercent = 25; // 0.25% fee for node operators

    // Minimum and maximum fees
    uint256 public minFee = 0.0001 ether;
    uint256 public maxFee = 1 ether;

    // Tier-based fee discounts (in percentage)
    mapping(uint256 => uint256) public tierDiscounts;

    // State variables
    Counter private _transactionIdCounter;
    Counter private _scheduledTransferIdCounter;
    Counter private _communityCollectionIdCounter;

    // Transaction mappings
    mapping(uint256 => Transaction) private _transactions;
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
        address indexed recipient,
        uint256 amount,
        TransactionType transactionType
    );
    event Transfer(address indexed from, address indexed to, uint256 amount, string message);
    event TransactionCompleted(
        uint256 indexed id, address indexed sender, address indexed receiver, uint256 amount, uint256 fee
    );
    event TransactionCancelled(uint256 indexed id, address indexed sender, address indexed receiver);
    event TransactionDisputed(uint256 indexed id, address indexed sender, address indexed receiver, string reason);
    event TransactionApproved(uint256 indexed id, address indexed approver);
    event FeeUpdated(uint256 newBaseFeePercent, uint256 newMemberFeePercent, uint256 newValidatorFeePercent);
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
    event ScheduledTransferUpdated(uint256 indexed transferId, bool active);
    event ScheduledTransferExecuted(
        uint256 indexed transferId, address indexed sender, address indexed recipient, uint256 amount
    );
    event ScheduledTransferCancelled(uint256 indexed transferId);
    event CommunityCollectionCreated(
        uint256 indexed collectionId, address indexed creator, string purpose, uint256 goal, uint256 deadline
    );
    event CommunityCollectionContribution(uint256 indexed collectionId, address indexed contributor, uint256 amount);
    event CommunityCollectionPaid(uint256 indexed collectionId, address indexed recipient, uint256 amount);
    event TierDiscountUpdated(uint256 tier, uint256 discount);
    event DailyLimitUpdated(uint256 newLimit);
    event MemberFeePercentUpdated(uint256 newFeePercent);
    event ValidatorFeeUpdated(uint256 newValidatorFeePercent);

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
     * @dev Transfer funds to a recipient
     * @param recipient Address of the recipient
     * @param amount Amount to transfer
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
            treasury.depositFees{value: fee}("Money transfer fee");
        }

        // Update last transfer time
        lastTransferTime[msg.sender][recipient] = block.timestamp;

        // Record transaction for profit sharing eligibility (if membership contract is set)
        if (address(membershipContract) != address(0)) {
            try PasifikaMembership(membershipContract).recordTransaction(msg.sender, amount) {} catch {}
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

    /**
     * @dev Batch transfer funds to multiple recipients
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts to send
     * @param memos Array of messages for each transfer
     * @return Array of transaction IDs
     */
    function batchTransfer(address[] memory recipients, uint256[] memory amounts, string[] memory memos)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256[] memory)
    {
        require(recipients.length > 0, "PasifikaMoneyTransfer: no recipients");
        require(recipients.length == amounts.length, "PasifikaMoneyTransfer: arrays length mismatch");
        require(recipients.length == memos.length, "PasifikaMoneyTransfer: arrays length mismatch");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        require(msg.value >= totalAmount, "PasifikaMoneyTransfer: insufficient funds");

        uint256[] memory transactionIds = new uint256[](recipients.length);

        for (uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            uint256 amount = amounts[i];
            string memory memo = memos[i];

            require(recipient != address(0), "PasifikaMoneyTransfer: invalid recipient");
            require(recipient != msg.sender, "PasifikaMoneyTransfer: cannot send to self");
            require(amount > 0, "PasifikaMoneyTransfer: amount must be positive");

            // Calculate fee
            uint256 fee = calculateFee(amount, msg.sender);
            uint256 amountAfterFee = amount - fee;

            if (fee > 0) {
                // Send fee to treasury
                (bool feeSuccess,) = payable(address(treasury)).call{value: fee}(
                    abi.encodeWithSignature("depositFees(string)", "Transfer fee")
                );
                require(feeSuccess, "PasifikaMoneyTransfer: fee transfer failed");
            }

            // Send funds to recipient
            (bool success,) = payable(recipient).call{value: amountAfterFee}("");
            require(success, "PasifikaMoneyTransfer: transfer failed");

            // Record transaction for profit sharing eligibility (if membership contract is set)
            if (address(membershipContract) != address(0)) {
                try PasifikaMembership(membershipContract).recordTransaction(msg.sender, amount) {} catch {}
            }

            // Create transaction record
            uint256 transactionId = current(_transactionIdCounter);
            increment(_transactionIdCounter);

            // Initialize the transaction
            _initializeTransaction(
                transactionId, msg.sender, recipient, amountAfterFee, fee, TransactionType.Direct, memo
            );

            // Add to user's transactions
            _userSentTransactions[msg.sender].push(transactionId);
            _userReceivedTransactions[recipient].push(transactionId);

            emit Transfer(msg.sender, recipient, amountAfterFee, memo);

            transactionIds[i] = transactionId;
        }

        return transactionIds;
    }

    /**
     * @dev Create a scheduled transfer
     * @param recipient Address of the recipient
     * @param amount Amount to transfer
     * @param interval Time interval between transfers
     * @param repetitions Number of repetitions (0 = indefinite)
     * @param memo Transaction memo
     * @return uint256 ID of the scheduled transfer
     */
    function createScheduledTransfer(
        address recipient,
        uint256 amount,
        uint256 interval,
        uint256 repetitions,
        string memory memo
    ) external payable whenNotPaused nonReentrant returns (uint256) {
        require(recipient != address(0), "PasifikaMoneyTransfer: invalid recipient");
        require(recipient != msg.sender, "PasifikaMoneyTransfer: cannot send to self");
        require(amount > 0, "PasifikaMoneyTransfer: amount must be positive");
        require(interval > 0, "PasifikaMoneyTransfer: interval must be positive");
        require(msg.value >= amount, "PasifikaMoneyTransfer: insufficient funds");

        // Calculate fee
        uint256 fee = calculateFee(amount, msg.sender);
        uint256 amountAfterFee = amount - fee;

        if (fee > 0) {
            // Use the depositFees function in the treasury
            (bool success,) = payable(address(treasury)).call{value: fee}(
                abi.encodeWithSignature("depositFees(string)", "Scheduled transfer fee")
            );
            require(success, "PasifikaMoneyTransfer: fee transfer failed");
        }

        // Get scheduled transfer ID
        uint256 scheduledTransferId = current(_scheduledTransferIdCounter);
        increment(_scheduledTransferIdCounter);

        // Create scheduled transfer
        scheduledTransfers[scheduledTransferId] = ScheduledTransfer({
            sender: msg.sender,
            recipient: recipient,
            amount: amountAfterFee,
            interval: interval,
            nextExecutionTime: block.timestamp + interval,
            remainingTransfers: repetitions,
            active: true,
            memo: memo
        });

        emit ScheduledTransferCreated(scheduledTransferId, msg.sender, recipient, amount, interval, repetitions);
        emit ScheduledTransferUpdated(scheduledTransferId, true);

        return scheduledTransferId;
    }

    /**
     * @dev Execute a scheduled transfer
     * @param scheduledTransferId ID of scheduled transfer to execute
     */
    function executeScheduledTransfer(uint256 scheduledTransferId) external whenNotPaused nonReentrant {
        ScheduledTransfer storage scheduledTransfer = scheduledTransfers[scheduledTransferId];

        // Check if sender is authorized
        require(msg.sender == scheduledTransfer.sender, "PasifikaMoneyTransfer: not authorized");

        // Check if transfer is active
        require(scheduledTransfer.active, "PasifikaMoneyTransfer: transfer not active");

        // Check if it's time to execute
        require(
            block.timestamp >= scheduledTransfer.nextExecutionTime, "PasifikaMoneyTransfer: not ready for execution"
        );

        // Get recipient and amount
        address recipient = scheduledTransfer.recipient;
        uint256 amount = scheduledTransfer.amount;

        // Execute transfer
        (bool success,) = payable(recipient).call{value: amount}("");
        require(success, "PasifikaMoneyTransfer: transfer failed");

        // Create transaction record
        uint256 transactionId = current(_transactionIdCounter);
        increment(_transactionIdCounter);

        // Initialize the transaction record
        _initializeTransaction(
            transactionId,
            scheduledTransfer.sender,
            recipient,
            amount,
            0, // No fee since it was taken during creation
            TransactionType.Scheduled,
            scheduledTransfer.memo
        );

        // Add to user's transactions
        _userSentTransactions[scheduledTransfer.sender].push(transactionId);
        _userReceivedTransactions[recipient].push(transactionId);

        emit Transfer(scheduledTransfer.sender, recipient, amount, scheduledTransfer.memo);

        // Update scheduled transfer
        if (scheduledTransfer.remainingTransfers > 0) {
            scheduledTransfer.remainingTransfers--;
        }

        // If this was the last transfer or remainingTransfers was 0 (indefinite), check what to do
        if (scheduledTransfer.remainingTransfers == 0) {
            // If indefinite (originally 0), just update next execution time
            if (scheduledTransfer.active) {
                scheduledTransfer.nextExecutionTime = block.timestamp + scheduledTransfer.interval;
            }
        } else {
            // More transfers remain, update next execution time
            scheduledTransfer.nextExecutionTime = block.timestamp + scheduledTransfer.interval;
        }
    }

    /**
     * @dev Create a new community collection
     * @param purpose Purpose of the collection
     * @param goal Goal amount to collect
     * @param deadline Deadline timestamp for collection
     * @return Collection ID
     */
    function createCommunityCollection(string memory purpose, uint256 goal, uint256 deadline)
        external
        whenNotPaused
        nonReentrant
        returns (uint256)
    {
        require(goal > 0, "PasifikaMoneyTransfer: goal must be positive");
        require(deadline > block.timestamp, "PasifikaMoneyTransfer: deadline must be in the future");

        // Generate new collection ID
        uint256 collectionId = current(_communityCollectionIdCounter);
        increment(_communityCollectionIdCounter);

        // Create collection
        communityCollections[collectionId] = CommunityCollection({
            creator: msg.sender,
            purpose: purpose,
            goal: goal,
            collected: 0,
            deadline: deadline,
            active: true
        });

        emit CommunityCollectionCreated(collectionId, msg.sender, purpose, goal, deadline);

        return collectionId;
    }

    /**
     * @dev Contribute to a community collection
     * @param collectionId ID of the collection
     */
    function contributeToCollection(uint256 collectionId) external payable whenNotPaused nonReentrant {
        require(msg.value > 0, "PasifikaMoneyTransfer: amount must be positive");
        require(collectionId < current(_communityCollectionIdCounter), "PasifikaMoneyTransfer: invalid collection ID");

        CommunityCollection storage collection = communityCollections[collectionId];
        require(collection.active, "PasifikaMoneyTransfer: collection not active");
        require(block.timestamp < collection.deadline, "PasifikaMoneyTransfer: collection deadline passed");

        // Update collection
        collection.collected += msg.value;

        // Create transaction record
        uint256 transactionId = current(_transactionIdCounter);
        increment(_transactionIdCounter);

        // Initialize the transaction
        _initializeTransaction(
            transactionId,
            msg.sender,
            collection.creator,
            msg.value,
            0,
            TransactionType.Direct,
            string(abi.encodePacked("Collection: ", collection.purpose))
        );

        // Add to user's transactions
        _userSentTransactions[msg.sender].push(transactionId);
        _userReceivedTransactions[collection.creator].push(transactionId);

        emit CommunityCollectionContribution(collectionId, msg.sender, msg.value);
    }

    /**
     * @dev Withdraw funds to a recipient from a collection
     * @param collectionId ID of the collection
     * @param recipient Address of the recipient
     * @param amount Amount to withdraw
     */
    function payoutFromCollection(uint256 collectionId, address recipient, uint256 amount)
        external
        whenNotPaused
        nonReentrant
        onlyRole(ADMIN_ROLE)
    {
        require(recipient != address(0), "PasifikaMoneyTransfer: invalid recipient");
        require(amount > 0, "PasifikaMoneyTransfer: amount must be positive");
        require(collectionId < current(_communityCollectionIdCounter), "PasifikaMoneyTransfer: invalid collection ID");

        CommunityCollection storage collection = communityCollections[collectionId];
        require(collection.active, "PasifikaMoneyTransfer: collection not active");
        require(collection.collected >= amount, "PasifikaMoneyTransfer: insufficient funds in collection");

        // Update collection
        collection.collected -= amount;

        // Send funds to recipient
        (bool success,) = payable(recipient).call{value: amount}("");
        require(success, "PasifikaMoneyTransfer: transfer failed");

        // Create transaction record
        uint256 transactionId = current(_transactionIdCounter);
        increment(_transactionIdCounter);

        // Initialize the transaction
        _initializeTransaction(
            transactionId,
            address(this),
            recipient,
            amount,
            0,
            TransactionType.Direct,
            string(abi.encodePacked("Payout: ", collection.purpose))
        );

        // Add to user's transactions
        _userReceivedTransactions[recipient].push(transactionId);
        _userSentTransactions[collection.creator].push(transactionId);

        emit CommunityCollectionPaid(collectionId, recipient, amount);
    }

    /**
     * @dev Finalize a community collection and transfer funds to creator
     * @param collectionId ID of the collection to finalize
     */
    function finalizeCommunityCollection(uint256 collectionId) external whenNotPaused nonReentrant {
        require(collectionId < current(_communityCollectionIdCounter), "PasifikaMoneyTransfer: invalid collection ID");

        CommunityCollection storage collection = communityCollections[collectionId];
        require(collection.active, "PasifikaMoneyTransfer: collection not active");
        require(msg.sender == collection.creator, "PasifikaMoneyTransfer: only creator can finalize");

        // Get the amount to transfer
        uint256 amount = collection.collected;
        require(amount > 0, "PasifikaMoneyTransfer: no funds to transfer");

        // Mark as completed
        collection.active = false;
        collection.collected = 0;

        // Transfer funds to creator
        (bool success,) = payable(collection.creator).call{value: amount}("");
        require(success, "PasifikaMoneyTransfer: transfer to creator failed");

        // Create transaction record
        uint256 transactionId = current(_transactionIdCounter);
        increment(_transactionIdCounter);

        // Initialize the transaction
        _initializeTransaction(
            transactionId,
            address(this),
            collection.creator,
            amount,
            0,
            TransactionType.Direct,
            string(abi.encodePacked("Finalized Collection: ", collection.purpose))
        );

        _userReceivedTransactions[collection.creator].push(transactionId);

        emit CommunityCollectionPaid(collectionId, collection.creator, amount);
    }

    /**
     * @dev Calculate fee based on amount and sender's tier level
     * @param amount Transfer amount
     * @param sender Sender address
     * @return Fee amount
     */
    function calculateFee(uint256 amount, address sender) public view returns (uint256) {
        // Free transfers for community collections
        if (msg.sender == address(this)) {
            return 0;
        }

        // Check if sender is a validator node operator (Tier 2)
        if (address(nodeContract) != address(0)) {
            if (nodeContract.isActiveNodeOperator(sender)) {
                return (amount * validatorFeePercent) / 10000; // 0.25% for node operators
            }
        }

        // Check if sender is a member (Tier 1)
        if (address(membershipContract) != address(0)) {
            if (membershipContract.checkMembership(sender)) {
                return (amount * memberFeePercent) / 10000; // 0.5% for members
            }
        }

        // Use token adapter for tier-based discounts if available
        if (address(arbitrumTokenAdapter) != address(0)) {
            // Get sender's tier from the token adapter

            // Apply fee based on tier
            if (arbitrumTokenAdapter.hasTier(sender, 2)) {
                return (amount * validatorFeePercent) / 10000; // 0.25% for tier 2 (node operators)
            } else if (arbitrumTokenAdapter.hasTier(sender, 1)) {
                return (amount * memberFeePercent) / 10000; // 0.5% for tier 1 (members)
            }
        }

        // Default case: base fee for guests (Tier 0)
        uint256 baseFee = (amount * baseFeePercent) / 10000; // 1% for guests

        // Apply minimum and maximum
        if (baseFee < minFee) {
            baseFee = minFee;
        } else if (baseFee > maxFee) {
            baseFee = maxFee;
        }

        return baseFee;
    }

    /**
     * @dev Update daily sent amount and check against limit
     * @param sender Address of the sender
     * @param amount Amount being sent
     */
    function _updateAndCheckDailyLimit(address sender, uint256 amount) internal {
        // Reset daily tracking if it's a new day
        if (block.timestamp > dailySentTimestamp[sender] + 1 days) {
            dailySentAmount[sender] = 0;
            dailySentTimestamp[sender] = block.timestamp;
        }

        // Update and check
        dailySentAmount[sender] += amount;
        require(dailySentAmount[sender] <= dailyTransferLimit, "PasifikaMoneyTransfer: daily limit exceeded");
    }

    /**
     * @dev Set transfer fee parameters (admin only)
     * @param _baseFeePercent Base fee percentage in basis points
     * @param _minFee Minimum fee
     * @param _maxFee Maximum fee
     */
    function setFeeParameters(uint256 _baseFeePercent, uint256 _minFee, uint256 _maxFee)
        external
        onlyRole(FEE_MANAGER_ROLE)
    {
        require(_baseFeePercent <= 1000, "PasifikaMoneyTransfer: fee too high (max 10%)");

        baseFeePercent = _baseFeePercent;
        minFee = _minFee;
        maxFee = _maxFee;

        emit FeeUpdated(baseFeePercent, memberFeePercent, validatorFeePercent);
    }

    /**
     * @dev Set tier discount (admin only)
     * @param tier Tier level (1-3)
     * @param discount Discount percentage (0-100)
     */
    function setTierDiscount(uint256 tier, uint256 discount) external onlyRole(FEE_MANAGER_ROLE) {
        require(tier >= 1 && tier <= 3, "PasifikaMoneyTransfer: invalid tier");
        require(discount <= 100, "PasifikaMoneyTransfer: invalid discount");

        tierDiscounts[tier] = discount;

        emit TierDiscountUpdated(tier, discount);
    }

    /**
     * @dev Set daily transfer limit (admin only)
     * @param newLimit New daily limit
     */
    function setDailyTransferLimit(uint256 newLimit) external onlyRole(ADMIN_ROLE) {
        dailyTransferLimit = newLimit;

        emit DailyLimitUpdated(newLimit);
    }

    /**
     * @dev Set treasury contract address
     * @param _treasury New treasury contract address
     */
    function setTreasury(address payable _treasury) external onlyRole(ADMIN_ROLE) {
        require(_treasury != address(0), "PasifikaMoneyTransfer: zero address");
        treasury = PasifikaTreasury(_treasury);
        emit TreasuryUpdated(_treasury);
    }

    /**
     * @dev Initialize the treasury integration
     * This is called once after deployment to register as a fee collector
     */
    function initializeTreasury() external onlyRole(ADMIN_ROLE) {
        // Only request to be added as a fee collector if not already registered
        bytes32 feeCollectorRole = treasury.FEE_COLLECTOR_ROLE();
        if (!treasury.hasRole(feeCollectorRole, address(this))) {
            treasury.addFeeCollector(address(this));
        }
    }

    /**
     * @dev Set the membership contract address
     * @param _membership New membership contract address
     */
    function setMembershipContract(address payable _membership) external onlyRole(ADMIN_ROLE) {
        require(_membership != address(0), "PasifikaMoneyTransfer: zero address");
        membershipContract = PasifikaMembership(_membership);

        emit MembershipContractUpdated(_membership);
    }

    /**
     * @dev Set the member fee percentage
     * @param _feePercent New fee percentage in basis points
     */
    function setMemberFeePercent(uint256 _feePercent) external onlyRole(FEE_MANAGER_ROLE) {
        require(_feePercent <= baseFeePercent, "PasifikaMoneyTransfer: member fee cannot exceed base fee");
        memberFeePercent = _feePercent;

        emit MemberFeePercentUpdated(_feePercent);
    }

    /**
     * @dev Set the node contract address
     * @param _nodeContract New node contract address
     */
    function setNodeContract(address payable _nodeContract) external onlyRole(ADMIN_ROLE) {
        require(_nodeContract != address(0), "PasifikaMoneyTransfer: zero address");
        nodeContract = PasifikaArbitrumNode(_nodeContract);

        emit NodeContractUpdated(_nodeContract);
    }

    /**
     * @dev Set the validator fee percentage
     * @param _validatorFeePercent New validator fee percentage in basis points
     */
    function setValidatorFeePercent(uint256 _validatorFeePercent) external onlyRole(FEE_MANAGER_ROLE) {
        require(_validatorFeePercent <= 1000, "PasifikaMoneyTransfer: fee too high"); // Max 10%
        validatorFeePercent = _validatorFeePercent;

        emit ValidatorFeeUpdated(_validatorFeePercent);
    }

    /**
     * @dev Get transactions for a user
     * @param user Address of the user
     * @param offset Starting index
     * @param limit Maximum number of transactions to return
     * @return Transaction IDs
     */
    function getUserTransactions(address user, uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory)
    {
        uint256[] storage userTxs = _userSentTransactions[user];
        uint256 total = userTxs.length;

        if (offset >= total) {
            return new uint256[](0);
        }

        uint256 count = (total - offset) < limit ? (total - offset) : limit;
        uint256[] memory result = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = userTxs[offset + i];
        }

        return result;
    }

    /**
     * @dev Get transaction details
     * @param transactionId Transaction ID
     * @return transaction details
     */
    function getTransactionDetails(uint256 transactionId) external view returns (TransactionRecord memory) {
        require(transactionId < current(_transactionIdCounter), "PasifikaMoneyTransfer: invalid transaction ID");

        Transaction storage txn = _transactions[transactionId];

        return TransactionRecord({
            sender: txn.sender,
            recipient: txn.receiver,
            amount: txn.amount,
            fee: txn.fee,
            timestamp: txn.createdAt,
            memo: txn.memo,
            transactionType: txn.transactionType,
            status: txn.status
        });
    }

    /**
     * @dev Get scheduled transfers for a user
     * @param user Address of the user
     * @return Array of scheduled transfer IDs
     */
    function getUserScheduledTransfers(address user) external view returns (uint256[] memory) {
        uint256 count = 0;

        // Count active transfers for the user
        for (uint256 i = 0; i < current(_scheduledTransferIdCounter); i++) {
            if (scheduledTransfers[i].sender == user && scheduledTransfers[i].active) {
                count++;
            }
        }

        // Create result array
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;

        // Fill result array
        for (uint256 i = 0; i < current(_scheduledTransferIdCounter); i++) {
            if (scheduledTransfers[i].sender == user && scheduledTransfers[i].active) {
                result[index++] = i;
            }
        }

        return result;
    }

    /**
     * @dev Get details of a scheduled transfer
     * @param transferId ID of the scheduled transfer
     * @return sender Address of the sender
     * @return recipient Address of the recipient
     * @return amount Amount to transfer
     * @return frequency Time interval between transfers
     * @return remainingPayments Number of remaining payments
     * @return nextPaymentTime Timestamp of the next payment
     * @return memo Transaction memo
     * @return active Whether the transfer is active
     */
    function getScheduledTransfer(uint256 transferId)
        external
        view
        returns (
            address sender,
            address recipient,
            uint256 amount,
            uint256 frequency,
            uint256 remainingPayments,
            uint256 nextPaymentTime,
            string memory memo,
            bool active
        )
    {
        ScheduledTransfer storage scheduledTransfer = scheduledTransfers[transferId];
        return (
            scheduledTransfer.sender,
            scheduledTransfer.recipient,
            scheduledTransfer.amount,
            scheduledTransfer.interval,
            scheduledTransfer.remainingTransfers,
            scheduledTransfer.nextExecutionTime,
            scheduledTransfer.memo,
            scheduledTransfer.active
        );
    }

    /**
     * @dev Get details of a community collection
     * @param collectionId ID of the collection to retrieve
     * @return name Purpose/name of the collection
     * @return creator Address of the creator
     * @return goal Goal amount
     * @return raised Amount raised so far
     * @return collectDeadline Deadline timestamp
     * @return completed Whether the collection has met its goal
     */
    function getCommunityCollection(uint256 collectionId)
        external
        view
        returns (
            string memory name,
            address creator,
            uint256 goal,
            uint256 raised,
            uint256 collectDeadline,
            bool completed
        )
    {
        require(collectionId < current(_communityCollectionIdCounter), "PasifikaMoneyTransfer: invalid collection ID");

        CommunityCollection storage collection = communityCollections[collectionId];
        return (
            collection.purpose,
            collection.creator,
            collection.goal,
            collection.collected,
            collection.deadline,
            collection.collected >= collection.goal
        );
    }

    /**
     * @dev Pause contract (admin only)
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause contract (admin only)
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Allow receiving ETH
     */
    receive() external payable {}

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
        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "PasifikaMoneyTransfer: transfer failed");

        emit FundsWithdrawn(msg.sender, amount);
    }

    /**
     * @dev Set the base fee percentage (admin only)
     * @param _baseFeePercent New base fee percent in basis points (100 = 1%)
     */
    function setBaseFeePercent(uint256 _baseFeePercent) external onlyRole(FEE_MANAGER_ROLE) {
        require(_baseFeePercent <= 500, "PasifikaMoneyTransfer: fee too high (max 5%)");
        baseFeePercent = _baseFeePercent;
        emit FeeUpdated(baseFeePercent, memberFeePercent, validatorFeePercent);
    }

    /**
     * @dev Set transfer fees (admin only)
     * @param _minFee Minimum fee
     * @param _maxFee Maximum fee
     */
    function setFees(uint256 _minFee, uint256 _maxFee) external onlyRole(FEE_MANAGER_ROLE) {
        require(_minFee <= _maxFee, "PasifikaMoneyTransfer: min fee must be <= max fee");
        minFee = _minFee;
        maxFee = _maxFee;

        emit FeeUpdated(baseFeePercent, minFee, maxFee);
    }
}
