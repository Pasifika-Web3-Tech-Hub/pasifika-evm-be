// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

/**
 * @title FeeManager
 * @dev Contract for managing, calculating, collecting and distributing fees for the PASIFIKA marketplace.
 * Handles fee structures, discounts, and distribution to various stakeholders.
 */
contract FeeManager is AccessControl, Pausable, ReentrancyGuard {
    // Use the Math library from OpenZeppelin for safe math operations
    using Math for uint256;

    // Roles
    bytes32 public constant FEE_ADMIN_ROLE = keccak256("FEE_ADMIN_ROLE");
    bytes32 public constant MARKETPLACE_ROLE = keccak256("MARKETPLACE_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    
    // Fee types
    enum FeeType {
        StandardSale,    // Regular marketplace sale
        Auction,         // Auction completion fee
        PremiumListing,  // Featured/premium listing
        PhysicalItem,    // Physical goods transaction
        DigitalContent,  // Digital content transaction
        CrossCultural    // Cross-cultural collaboration
    }
    
    // Fee configuration structure
    struct FeeConfig {
        uint256 baseFeePercentage;     // Base fee in basis points (100 = 1%)
        uint256 creatorRoyaltyPercentage; // Creator royalty in basis points
        uint256 communityFundPercentage;  // Community fund percentage in basis points
        uint256 platformFeePercentage;    // Platform fee percentage in basis points
        bool active;                    // Whether this fee type is active
    }
    
    // Transaction record for fee tracking
    struct FeeTransaction {
        uint256 transactionId;
        address payer;
        address paymentReceiver;
        uint256 totalAmount;
        uint256 feeAmount;
        uint256 creatorRoyalty;
        uint256 communityFund;
        uint256 platformFee;
        FeeType feeType;
        uint256 timestamp;
        bool processed;
    }
    
    // Addresses for fee distribution
    address public treasuryAddress;
    address public communityFundAddress;
    
    // Token address for ERC20 payments
    address public acceptedTokenAddress;
    bool public acceptsNativeToken;
    
    // Mapping for fee configurations by type
    mapping(FeeType => FeeConfig) public feeConfigurations;
    
    // Maximum fee percentage to prevent errors (e.g., 3000 basis points = 30%)
    uint256 public constant MAX_FEE_PERCENTAGE = 3000;
    
    // Total fees collected
    uint256 public totalFeesCollected;
    uint256 public totalRoyaltiesDistributed;
    uint256 public totalCommunityFundsDistributed;
    
    // Fee transactions tracking
    mapping(uint256 => FeeTransaction) public feeTransactions;
    uint256 private _nextTransactionId;
    
    // Discount tiers (spend amount => discount percentage in basis points)
    mapping(uint256 => uint256) public volumeDiscountTiers;
    
    // User spending tracking for discounts
    mapping(address => uint256) public userTotalSpending;
    
    // Custom community fee overrides for specific collections or tokens
    mapping(address => uint256) public communityFeeOverrides;
    
    // Events
    event FeeConfigUpdated(FeeType indexed feeType, uint256 baseFeePercentage);
    event FeeCalculated(uint256 indexed transactionId, uint256 amount, uint256 feeAmount);
    event FeeCollected(uint256 indexed transactionId, address indexed payer, uint256 feeAmount);
    event FeeDistributed(
        uint256 indexed transactionId, 
        uint256 creatorAmount, 
        uint256 communityAmount, 
        uint256 platformAmount
    );
    event TreasuryAddressUpdated(address indexed oldAddress, address indexed newAddress);
    event CommunityFundAddressUpdated(address indexed oldAddress, address indexed newAddress);
    event AcceptedTokenUpdated(address indexed tokenAddress);
    event VolumeDiscountTierUpdated(uint256 spendThreshold, uint256 discountPercentage);
    event CommunityFeeOverrideSet(address indexed collection, uint256 overridePercentage);
    event NativeTokenAcceptanceUpdated(bool acceptsNative);
    
    // Constructor
    constructor(address treasury, address communityFund) {
        console.log("FeeManager: Constructor start");
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FEE_ADMIN_ROLE, msg.sender);
        _grantRole(TREASURY_ROLE, msg.sender);
        
        // Initialize addresses
        treasuryAddress = treasury;
        communityFundAddress = communityFund;
        
        // Default to accepting native token
        acceptsNativeToken = true;
        
        // Initialize transaction ID counter
        _nextTransactionId = 1;
        
        // Set up default fee configurations
        _setupDefaultFeeConfigurations();
        
        // Set up default volume discount tiers
        _setupDefaultDiscountTiers();
        
        console.log("FeeManager: Constructor end");
    }
    
    /**
     * @dev Set up the default fee configurations
     */
    function _setupDefaultFeeConfigurations() internal {
        // Standard sale: 2.5% total (1% platform, 1% creator royalty, 0.5% community)
        feeConfigurations[FeeType.StandardSale] = FeeConfig({
            baseFeePercentage: 250,
            creatorRoyaltyPercentage: 100,
            communityFundPercentage: 50,
            platformFeePercentage: 100,
            active: true
        });
        
        // Auction: 3% total (1.5% platform, 1% creator royalty, 0.5% community)
        feeConfigurations[FeeType.Auction] = FeeConfig({
            baseFeePercentage: 300,
            creatorRoyaltyPercentage: 100,
            communityFundPercentage: 50,
            platformFeePercentage: 150,
            active: true
        });
        
        // Premium listing: 3.5% total (2% platform, 1% creator royalty, 0.5% community)
        feeConfigurations[FeeType.PremiumListing] = FeeConfig({
            baseFeePercentage: 350,
            creatorRoyaltyPercentage: 100,
            communityFundPercentage: 50,
            platformFeePercentage: 200,
            active: true
        });
        
        // Physical item: 4% total (2% platform, 1.5% creator royalty, 0.5% community)
        feeConfigurations[FeeType.PhysicalItem] = FeeConfig({
            baseFeePercentage: 400,
            creatorRoyaltyPercentage: 150,
            communityFundPercentage: 50,
            platformFeePercentage: 200,
            active: true
        });
        
        // Digital content: 3% total (1% platform, 1.5% creator royalty, 0.5% community)
        feeConfigurations[FeeType.DigitalContent] = FeeConfig({
            baseFeePercentage: 300,
            creatorRoyaltyPercentage: 150,
            communityFundPercentage: 50,
            platformFeePercentage: 100,
            active: true
        });
        
        // Cross-cultural: 3% total (1% platform, 1% creator royalty, 1% community)
        feeConfigurations[FeeType.CrossCultural] = FeeConfig({
            baseFeePercentage: 300,
            creatorRoyaltyPercentage: 100,
            communityFundPercentage: 100,
            platformFeePercentage: 100,
            active: true
        });
    }
    
    /**
     * @dev Set up default volume discount tiers
     */
    function _setupDefaultDiscountTiers() internal {
        // Discounts based on total spending (in wei)
        // 1 ETH = 10% discount
        volumeDiscountTiers[1 ether] = 1000;
        
        // 5 ETH = 15% discount
        volumeDiscountTiers[5 ether] = 1500;
        
        // 10 ETH = 20% discount
        volumeDiscountTiers[10 ether] = 2000;
        
        // 50 ETH = 25% discount
        volumeDiscountTiers[50 ether] = 2500;
    }
    
    /**
     * @dev Pause the contract - only admin can call
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpause the contract - only admin can call
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
    
    /**
     * @dev Update the treasury address
     * @param newTreasury The new treasury address
     */
    function updateTreasuryAddress(address newTreasury) 
        external 
        whenNotPaused 
        onlyRole(TREASURY_ROLE) 
    {
        require(newTreasury != address(0), "Cannot set zero address as treasury");
        
        address oldTreasury = treasuryAddress;
        treasuryAddress = newTreasury;
        
        emit TreasuryAddressUpdated(oldTreasury, newTreasury);
    }
    
    /**
     * @dev Update the community fund address
     * @param newCommunityFund The new community fund address
     */
    function updateCommunityFundAddress(address newCommunityFund) 
        external 
        whenNotPaused 
        onlyRole(TREASURY_ROLE) 
    {
        require(newCommunityFund != address(0), "Cannot set zero address as community fund");
        
        address oldCommunityFund = communityFundAddress;
        communityFundAddress = newCommunityFund;
        
        emit CommunityFundAddressUpdated(oldCommunityFund, newCommunityFund);
    }
    
    /**
     * @dev Set accepted ERC20 token for payments
     * @param tokenAddress The token contract address
     */
    function setAcceptedToken(address tokenAddress) 
        external 
        whenNotPaused 
        onlyRole(FEE_ADMIN_ROLE) 
    {
        // Zero address means native token only
        acceptedTokenAddress = tokenAddress;
        
        emit AcceptedTokenUpdated(tokenAddress);
    }
    
    /**
     * @dev Toggle native token acceptance
     * @param accept Whether to accept native token
     */
    function setNativeTokenAcceptance(bool accept) 
        external 
        whenNotPaused 
        onlyRole(FEE_ADMIN_ROLE) 
    {
        acceptsNativeToken = accept;
        
        emit NativeTokenAcceptanceUpdated(accept);
    }
    
    /**
     * @dev Update fee configuration for a specific fee type
     * @param feeType The fee type to update
     * @param baseFeePercentage The new base fee percentage in basis points
     * @param creatorRoyaltyPercentage The new creator royalty percentage
     * @param communityFundPercentage The new community fund percentage
     * @param platformFeePercentage The new platform fee percentage
     * @param active Whether this fee type is active
     */
    function updateFeeConfiguration(
        FeeType feeType,
        uint256 baseFeePercentage,
        uint256 creatorRoyaltyPercentage,
        uint256 communityFundPercentage,
        uint256 platformFeePercentage,
        bool active
    ) 
        external 
        whenNotPaused 
        onlyRole(FEE_ADMIN_ROLE) 
    {
        require(baseFeePercentage <= MAX_FEE_PERCENTAGE, "Fee percentage too high");
        require(
            creatorRoyaltyPercentage + communityFundPercentage + platformFeePercentage == baseFeePercentage,
            "Fee distribution percentages must sum to base fee"
        );
        
        feeConfigurations[feeType] = FeeConfig({
            baseFeePercentage: baseFeePercentage,
            creatorRoyaltyPercentage: creatorRoyaltyPercentage,
            communityFundPercentage: communityFundPercentage,
            platformFeePercentage: platformFeePercentage,
            active: active
        });
        
        emit FeeConfigUpdated(feeType, baseFeePercentage);
    }
    
    /**
     * @dev Set a volume discount tier
     * @param spendThreshold The spending threshold for this tier
     * @param discountPercentage The discount percentage in basis points (100 = 1%)
     */
    function setVolumeDiscountTier(uint256 spendThreshold, uint256 discountPercentage) 
        external 
        whenNotPaused 
        onlyRole(FEE_ADMIN_ROLE) 
    {
        require(spendThreshold > 0, "Spend threshold must be positive");
        require(discountPercentage <= MAX_FEE_PERCENTAGE, "Discount percentage too high");
        
        volumeDiscountTiers[spendThreshold] = discountPercentage;
        
        emit VolumeDiscountTierUpdated(spendThreshold, discountPercentage);
    }
    
    /**
     * @dev Set a community fee override for a specific collection
     * @param collection Address of the NFT contract/collection
     * @param overridePercentage The override percentage in basis points
     */
    function setCommunityFeeOverride(address collection, uint256 overridePercentage) 
        external 
        whenNotPaused 
        onlyRole(FEE_ADMIN_ROLE) 
    {
        require(collection != address(0), "Cannot set override for zero address");
        require(overridePercentage <= MAX_FEE_PERCENTAGE, "Override percentage too high");
        
        communityFeeOverrides[collection] = overridePercentage;
        
        emit CommunityFeeOverrideSet(collection, overridePercentage);
    }
    
    /**
     * @dev Calculate fee for a transaction
     * @param amount The transaction amount
     * @param feeType The type of fee to apply
     * @param payer The address paying the fee
     * @param collection Optional collection address for community fee overrides
     * @return feeAmount The calculated fee amount
     * @return creatorRoyalty The calculated creator royalty
     * @return communityFund The calculated community fund amount
     * @return platformFee The calculated platform fee amount
     */
    function calculateFee(
        uint256 amount,
        FeeType feeType,
        address payer,
        address collection
    ) 
        public 
        view 
        returns (
            uint256 feeAmount,
            uint256 creatorRoyalty,
            uint256 communityFund,
            uint256 platformFee
        ) 
    {
        require(feeConfigurations[feeType].active, "Fee type not active");
        
        // Get fee configuration
        FeeConfig memory config = feeConfigurations[feeType];
        
        // Calculate base fee amount
        feeAmount = (amount * config.baseFeePercentage) / 10000;
        
        // Apply volume discount if applicable
        uint256 discount = getVolumeDiscount(payer);
        if (discount > 0) {
            feeAmount = feeAmount * (10000 - discount) / 10000;
        }
        
        // Calculate creator royalty
        creatorRoyalty = (amount * config.creatorRoyaltyPercentage) / 10000;
        
        // Check for community fee override
        uint256 communityPercentage = config.communityFundPercentage;
        if (collection != address(0) && communityFeeOverrides[collection] > 0) {
            communityPercentage = communityFeeOverrides[collection];
        }
        
        // Calculate community fund amount
        communityFund = (amount * communityPercentage) / 10000;
        
        // Ensure the sum doesn't exceed the total fee amount
        uint256 totalDistributed = creatorRoyalty + communityFund;
        if (totalDistributed > feeAmount) {
            // Adjust the platform fee to zero and cap other fees proportionally
            platformFee = 0;
            uint256 adjustmentRatio = feeAmount * 10000 / totalDistributed;
            creatorRoyalty = (creatorRoyalty * adjustmentRatio) / 10000;
            communityFund = feeAmount - creatorRoyalty; // Ensures no rounding errors
        } else {
            // Platform fee is whatever remains from the total fee
            platformFee = feeAmount - totalDistributed;
        }
        
        return (feeAmount, creatorRoyalty, communityFund, platformFee);
    }
    
    /**
     * @dev Get the volume discount rate for a user
     * @param user The user address
     * @return The discount rate in basis points
     */
    function getVolumeDiscount(address user) public view returns (uint256) {
        uint256 totalSpent = userTotalSpending[user];
        uint256 highestDiscount = 0;
        
        // Find the highest applicable discount
        uint256[] memory thresholds = getDiscountThresholds();
        for (uint256 i = 0; i < thresholds.length; i++) {
            if (totalSpent >= thresholds[i] && volumeDiscountTiers[thresholds[i]] > highestDiscount) {
                highestDiscount = volumeDiscountTiers[thresholds[i]];
            }
        }
        
        return highestDiscount;
    }
    
    /**
     * @dev Get all discount thresholds
     * @return Array of discount thresholds
     */
    function getDiscountThresholds() public view returns (uint256[] memory) {
        // First, count how many active thresholds we have
        uint256 count = 0;
        uint256[] memory potentialThresholds = new uint256[](5); // Assuming a reasonable max
        potentialThresholds[0] = 1 ether;
        potentialThresholds[1] = 5 ether;
        potentialThresholds[2] = 10 ether;
        potentialThresholds[3] = 50 ether;
        potentialThresholds[4] = 100 ether;
        
        for (uint256 i = 0; i < potentialThresholds.length; i++) {
            if (volumeDiscountTiers[potentialThresholds[i]] > 0) {
                count++;
            }
        }
        
        // Create and populate the result array
        uint256[] memory result = new uint256[](count);
        uint256 resultIndex = 0;
        
        for (uint256 i = 0; i < potentialThresholds.length; i++) {
            if (volumeDiscountTiers[potentialThresholds[i]] > 0) {
                result[resultIndex] = potentialThresholds[i];
                resultIndex++;
            }
        }
        
        return result;
    }
    
    /**
     * @dev Process a transaction fee (collect and distribute)
     * @param amount The transaction amount
     * @param feeType The type of fee to apply
     * @param payer The address paying the fee
     * @param paymentReceiver The address receiving the payment (seller)
     * @param creator The content creator address for royalties
     * @param collection The collection address (for community fee overrides)
     * @return transactionId The ID of the processed fee transaction
     */
    function processFee(
        uint256 amount,
        FeeType feeType,
        address payer,
        address paymentReceiver,
        address creator,
        address collection
    ) 
        external 
        payable
        whenNotPaused 
        onlyRole(MARKETPLACE_ROLE) 
        nonReentrant
        returns (uint256) 
    {
        require(amount > 0, "Amount must be positive");
        require(payer != address(0), "Payer cannot be zero address");
        require(paymentReceiver != address(0), "Payment receiver cannot be zero address");
        require(feeConfigurations[feeType].active, "Fee type not active");
        
        // Calculate the fee
        (
            uint256 feeAmount,
            uint256 creatorRoyalty,
            uint256 communityFund,
            uint256 platformFee
        ) = calculateFee(amount, feeType, payer, collection);
        
        // Create transaction record
        uint256 transactionId = _nextTransactionId++;
        
        feeTransactions[transactionId] = FeeTransaction({
            transactionId: transactionId,
            payer: payer,
            paymentReceiver: paymentReceiver,
            totalAmount: amount,
            feeAmount: feeAmount,
            creatorRoyalty: creatorRoyalty,
            communityFund: communityFund,
            platformFee: platformFee,
            feeType: feeType,
            timestamp: block.timestamp,
            processed: false
        });
        
        emit FeeCalculated(transactionId, amount, feeAmount);
        
        // Collect the fee
        if (acceptsNativeToken && msg.value >= feeAmount) {
            // Using native token
            require(msg.value >= feeAmount, "Insufficient fee payment");
            
            // Distribute the collected fee
            _distributeNativeTokenFee(transactionId, creator);
        } else if (acceptedTokenAddress != address(0)) {
            // Using ERC20 token
            // The marketplace should have approval to transfer tokens
            _distributeERC20Fee(transactionId, creator);
        } else {
            revert("No payment method available");
        }
        
        // Update user spending for volume discounts
        userTotalSpending[payer] += amount;
        
        return transactionId;
    }
    
    /**
     * @dev Distribute fee using native token
     * @param transactionId The fee transaction ID
     * @param creator The content creator address
     */
    function _distributeNativeTokenFee(uint256 transactionId, address creator) internal {
        FeeTransaction storage transaction = feeTransactions[transactionId];
        
        // Update global stats
        totalFeesCollected += transaction.feeAmount;
        totalRoyaltiesDistributed += transaction.creatorRoyalty;
        totalCommunityFundsDistributed += transaction.communityFund;
        
        // Mark as processed
        transaction.processed = true;
        
        // Distribute creator royalty if applicable
        if (transaction.creatorRoyalty > 0 && creator != address(0)) {
            (bool creatorSuccess, ) = payable(creator).call{value: transaction.creatorRoyalty}("");
            require(creatorSuccess, "Creator royalty transfer failed");
        } else if (transaction.creatorRoyalty > 0) {
            // If no creator specified, send to treasury
            transaction.platformFee += transaction.creatorRoyalty;
            transaction.creatorRoyalty = 0;
        }
        
        // Distribute community fund
        if (transaction.communityFund > 0) {
            (bool communitySuccess, ) = payable(communityFundAddress).call{value: transaction.communityFund}("");
            require(communitySuccess, "Community fund transfer failed");
        }
        
        // Distribute platform fee to treasury
        if (transaction.platformFee > 0) {
            (bool treasurySuccess, ) = payable(treasuryAddress).call{value: transaction.platformFee}("");
            require(treasurySuccess, "Treasury transfer failed");
        }
        
        emit FeeCollected(transactionId, transaction.payer, transaction.feeAmount);
        emit FeeDistributed(
            transactionId,
            transaction.creatorRoyalty,
            transaction.communityFund,
            transaction.platformFee
        );
    }
    
    /**
     * @dev Distribute fee using ERC20 token
     * @param transactionId The fee transaction ID
     * @param creator The content creator address
     */
    function _distributeERC20Fee(uint256 transactionId, address creator) internal {
        FeeTransaction storage transaction = feeTransactions[transactionId];
        IERC20 token = IERC20(acceptedTokenAddress);
        
        // Collect the fee from the marketplace contract
        require(
            token.transferFrom(msg.sender, address(this), transaction.feeAmount),
            "Fee collection failed"
        );
        
        // Update global stats
        totalFeesCollected += transaction.feeAmount;
        totalRoyaltiesDistributed += transaction.creatorRoyalty;
        totalCommunityFundsDistributed += transaction.communityFund;
        
        // Mark as processed
        transaction.processed = true;
        
        // Distribute creator royalty if applicable
        if (transaction.creatorRoyalty > 0 && creator != address(0)) {
            require(
                token.transfer(creator, transaction.creatorRoyalty),
                "Creator royalty transfer failed"
            );
        } else if (transaction.creatorRoyalty > 0) {
            // If no creator specified, send to treasury
            transaction.platformFee += transaction.creatorRoyalty;
            transaction.creatorRoyalty = 0;
        }
        
        // Distribute community fund
        if (transaction.communityFund > 0) {
            require(
                token.transfer(communityFundAddress, transaction.communityFund),
                "Community fund transfer failed"
            );
        }
        
        // Distribute platform fee to treasury
        if (transaction.platformFee > 0) {
            require(
                token.transfer(treasuryAddress, transaction.platformFee),
                "Treasury transfer failed"
            );
        }
        
        emit FeeCollected(transactionId, transaction.payer, transaction.feeAmount);
        emit FeeDistributed(
            transactionId,
            transaction.creatorRoyalty,
            transaction.communityFund,
            transaction.platformFee
        );
    }
    
    /**
     * @dev Get fee transaction details
     * @param transactionId The transaction ID
     * @return Transaction details
     */
    function getFeeTransaction(uint256 transactionId) 
        external 
        view 
        returns (FeeTransaction memory) 
    {
        require(transactionId < _nextTransactionId, "Transaction does not exist");
        
        return feeTransactions[transactionId];
    }
    
    /**
     * @dev Get fee configuration for a fee type
     * @param feeType The fee type
     * @return Fee configuration
     */
    function getFeeConfiguration(FeeType feeType) 
        external 
        view 
        returns (FeeConfig memory) 
    {
        return feeConfigurations[feeType];
    }
    
    /**
     * @dev Withdraw any excess native token from the contract
     * @param amount The amount to withdraw
     */
    function withdrawExcessFunds(uint256 amount) 
        external 
        onlyRole(TREASURY_ROLE) 
        nonReentrant
        returns (uint256) 
    {
        require(amount <= address(this).balance, "Insufficient contract balance");
        
        (bool success, ) = payable(treasuryAddress).call{value: amount}("");
        require(success, "Withdrawal failed");
        
        return amount;
    }
    
    /**
     * @dev Withdraw any excess ERC20 tokens from the contract
     * @param tokenAddress The token contract address
     * @param amount The amount to withdraw
     */
    function withdrawExcessTokens(address tokenAddress, uint256 amount) 
        external 
        onlyRole(TREASURY_ROLE) 
        nonReentrant 
    {
        IERC20 token = IERC20(tokenAddress);
        require(amount <= token.balanceOf(address(this)), "Insufficient token balance");
        
        require(token.transfer(treasuryAddress, amount), "Token withdrawal failed");
    }
    
    /**
     * @dev Receive function to accept ETH
     */
    receive() external payable {
        // Just accept ETH payments
    }
    
    /**
     * @dev Fallback function
     */
    fallback() external payable {
        // Just accept ETH payments
    }
}
