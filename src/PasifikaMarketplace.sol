// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

import "./ArbitrumTokenAdapter.sol";
import "./PasifikaTreasury.sol";
import "./PasifikaMembership.sol";
import "./PasifikaArbitrumNode.sol";
import "./PasifikaNFT.sol";

/**
 * @title PasifikaMarketplace
 * @dev Streamlined marketplace contract for Pasifika NFTs
 * Uses ETH native token for payments with integrated fee management
 * Supports royalties and works directly with ArbitrumTokenAdapter for tier benefits
 */
contract PasifikaMarketplace is AccessControl, ReentrancyGuard, Pausable {
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MARKET_MANAGER_ROLE = keccak256("MARKET_MANAGER_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    
    // Listing status
    enum ListingStatus { Active, Sold, Cancelled }
    
    // Listing type
    enum ListingType { FixedPrice, Auction, PhysicalItem }
    
    // Listing struct
    struct Listing {
        uint256 tokenId;
        address nftContract;
        address seller;
        uint256 price;
        ListingStatus status;
        ListingType listingType;
        uint256 startTime;
        uint256 endTime;
        address highestBidder;
        uint256 highestBid;
        bool escrow; // Whether payment should be held in escrow (for physical items)
        string shippingInfo; // For physical items, can be IPFS hash to shipping details
    }
    
    // Tier discount structure
    struct TierDiscount {
        uint256 tier;
        uint256 discountPercent; // Discount in whole percent (5 = 5%)
    }
    
    // State variables
    mapping(uint256 => Listing) public listings;
    uint256 public listingCounter;
    
    // Core adapter for tier benefits
    ArbitrumTokenAdapter public arbitrumTokenAdapter;
    
    // Treasury for collecting fees
    PasifikaTreasury public treasury;
    
    // Membership contract for reduced fees
    PasifikaMembership public membershipContract;
    
    // Node contract for validator nodes
    PasifikaArbitrumNode public nodeContract;
    
    // Fee recipient
    address payable public feeRecipient;
    
    // Treasury allocation percentage (in basis points - 10000 = 100%)
    uint256 public treasuryAllocation = 7000; // 70% goes to treasury by default
    
    // Tier discounts
    mapping(uint256 => TierDiscount) public tierDiscounts;
    
    // Escrow state
    mapping(uint256 => bool) public escrowReleased;
    mapping(uint256 => mapping(address => uint256)) public pendingWithdrawals; // For auction refunds
    
    // Base fee percentage (in basis points)
    uint256 public baseFeePercent = 100; // 1% base fee
    
    // Member fee percentage (in basis points)
    uint256 public memberFeePercent = 50; // 0.5% fee for members
    
    // Validator fee percentage (in basis points)
    uint256 public validatorFeePercent = 25; // 0.25% fee for validators
    
    // Treasury wallet address
    address payable public treasuryWallet;
    
    // Events
    event ItemListed(uint256 indexed listingId, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 price, ListingType listingType);
    event ItemSold(uint256 indexed listingId, address indexed buyer, uint256 price);
    event AuctionBid(uint256 indexed listingId, address indexed bidder, uint256 bid);
    event ListingCancelled(uint256 indexed listingId);
    event EscrowReleased(uint256 indexed listingId, address indexed seller, uint256 amount);
    event FeeUpdated(uint256 newFeePercent);
    event FeeRecipientUpdated(address indexed newRecipient);
    event TierDiscountUpdated(uint256 tier, uint256 discountPercent);
    event TreasuryAllocationUpdated(uint256 newAllocationPercent);
    event TreasuryWalletUpdated(address indexed newTreasuryWallet);
    event RoyaltyPaid(uint256 indexed tokenId, address indexed creator, uint256 amount);
    event NodeContractUpdated(address indexed newNodeContract);
    event ValidatorFeePercentUpdated(uint256 newValidatorFeePercent);
    
    /**
     * @dev Constructor
     * @param _feeRecipient Address to receive marketplace fees
     * @param _treasuryWallet Address of the treasury wallet for direct fee transfers
     * @param _arbitrumTokenAdapter Address of the ArbitrumTokenAdapter contract
     * @param _treasury Address of the PasifikaTreasury contract
     */
    constructor(
        address payable _feeRecipient,
        address payable _treasuryWallet,
        address payable _arbitrumTokenAdapter,
        address payable _treasury
    ) {
        require(_feeRecipient != address(0), "PasifikaMarketplace: zero address");
        require(_treasuryWallet != address(0), "PasifikaMarketplace: zero address");
        require(_arbitrumTokenAdapter != address(0), "PasifikaMarketplace: zero address");
        require(_treasury != address(0), "PasifikaMarketplace: zero address");
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(FEE_MANAGER_ROLE, msg.sender);
        
        feeRecipient = _feeRecipient;
        treasuryWallet = _treasuryWallet;
        arbitrumTokenAdapter = ArbitrumTokenAdapter(_arbitrumTokenAdapter);
        treasury = PasifikaTreasury(_treasury);
        
        // Initialize tier discounts
        tierDiscounts[1] = TierDiscount(1, 0);     // Basic tier: 0% discount
        tierDiscounts[2] = TierDiscount(2, 5);     // Silver tier: 5% discount
        tierDiscounts[3] = TierDiscount(3, 10);    // Gold tier: 10% discount
        tierDiscounts[4] = TierDiscount(4, 15);    // Platinum tier: 15% discount
        tierDiscounts[5] = TierDiscount(5, 20);    // Validator tier: 20% discount
        tierDiscounts[6] = TierDiscount(6, 25);    // Node operator tier: 25% discount
    }
    
    /**
     * @dev Create a new listing for NFT
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to list
     * @param price Price in ETH
     * @param listingType Type of listing (fixed price, auction, physical)
     * @param duration Duration of the listing in seconds (for auctions)
     * @param escrow Whether to use escrow for payment
     * @param shippingInfo Shipping information for physical items
     */
    function createListing(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        ListingType listingType,
        uint256 duration,
        bool escrow,
        string memory shippingInfo
    ) external whenNotPaused returns (uint256) {
        require(nftContract != address(0), "PasifikaMarketplace: invalid NFT contract");
        require(price > 0, "PasifikaMarketplace: price must be greater than 0");
        
        // Check if it's a physical item in our Pasifika NFT
        bool isPhysicalItem = false;
        if (listingType == ListingType.PhysicalItem) {
            try PasifikaNFT(nftContract).getItemType(tokenId) returns (PasifikaNFT.ItemType itemType) {
                isPhysicalItem = (itemType == PasifikaNFT.ItemType.Physical);
                require(isPhysicalItem, "PasifikaMarketplace: not a physical item");
            } catch {
                // Not our NFT contract, just continue
            }
        }
        
        // If not physical item, transfer NFT to marketplace
        if (listingType != ListingType.PhysicalItem) {
            IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);
        }
        
        // Set auction end time if applicable
        uint256 endTime = 0;
        if (listingType == ListingType.Auction) {
            require(duration > 0, "PasifikaMarketplace: auction duration must be greater than 0");
            endTime = block.timestamp + duration;
        }
        
        // For physical items, always require escrow
        if (listingType == ListingType.PhysicalItem) {
            escrow = true;
        }
        
        // Create listing
        uint256 listingId = listingCounter;
        listings[listingId] = Listing({
            tokenId: tokenId,
            nftContract: nftContract,
            seller: msg.sender,
            price: price,
            status: ListingStatus.Active,
            listingType: listingType,
            startTime: block.timestamp,
            endTime: endTime,
            highestBidder: address(0),
            highestBid: 0,
            escrow: escrow,
            shippingInfo: shippingInfo
        });
        
        listingCounter++;
        
        emit ItemListed(listingId, msg.sender, nftContract, tokenId, price, listingType);
        
        return listingId;
    }
    
    /**
     * @dev Purchase an item at fixed price
     * @param listingId ID of the listing to purchase
     */
    function purchaseItem(uint256 listingId) external payable whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.status == ListingStatus.Active, "PasifikaMarketplace: item not available");
        require(listing.listingType == ListingType.FixedPrice, "PasifikaMarketplace: not a fixed price listing");
        require(msg.value >= listing.price, "PasifikaMarketplace: insufficient payment");
        require(msg.sender != listing.seller, "PasifikaMarketplace: cannot buy your own item");
        
        // Apply tier discount if applicable
        uint256 finalPrice = _applyTierDiscount(listing.price, msg.sender);
        require(msg.value >= finalPrice, "PasifikaMarketplace: insufficient payment after discount");
        
        // Mark as sold
        listing.status = ListingStatus.Sold;
        
        // Handle royalties
        uint256 remainingAmount = finalPrice;
        uint256 royaltyAmount = 0;
        
        try IERC2981(listing.nftContract).royaltyInfo(listing.tokenId, finalPrice) returns (address receiver, uint256 royaltyFee) {
            if (royaltyFee > 0 && receiver != address(0)) {
                royaltyAmount = royaltyFee;
                remainingAmount = finalPrice - royaltyAmount;
                
                // Transfer royalties
                (bool royaltySuccess, ) = payable(receiver).call{value: royaltyAmount}("");
                require(royaltySuccess, "PasifikaMarketplace: royalty transfer failed");
                
                emit RoyaltyPaid(listing.tokenId, receiver, royaltyAmount);
            }
        } catch {
            // No royalty support, continue
        }
        
        // Calculate platform fee
        uint256 fee = _calculateFee(msg.sender, remainingAmount);
        uint256 sellerAmount = remainingAmount - fee;
        
        // Calculate treasury allocation
        uint256 treasuryAmount = (fee * treasuryAllocation) / 10000;
        uint256 feeManagerAmount = fee - treasuryAmount;
        
        // Handle payment based on escrow setting
        if (listing.escrow) {
            // Hold funds in the contract
            pendingWithdrawals[listingId][listing.seller] = sellerAmount;
        } else {
            // Transfer funds to seller directly
            (bool success, ) = payable(listing.seller).call{value: sellerAmount}("");
            require(success, "PasifikaMarketplace: transfer to seller failed");
        }
        
        // Calculate total fee amount
        uint256 totalFee = treasuryAmount + feeManagerAmount;
        
        // Send total fee to treasury
        if (totalFee > 0) {
            // Use the depositFees function in the treasury
            (bool treasurySuccess, ) = address(treasury).call{value: totalFee}(
                abi.encodeWithSignature(
                    "depositFees(string)",
                    string(abi.encodePacked("Marketplace fee from NFT sale #", _toString(listing.tokenId)))
                )
            );
            require(treasurySuccess, "PasifikaMarketplace: treasury transfer failed");
        }
        
        // Transfer NFT to buyer
        IERC721(listing.nftContract).transferFrom(address(this), msg.sender, listing.tokenId);
        
        // Refund excess payment
        if (msg.value > finalPrice) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: msg.value - finalPrice}("");
            require(refundSuccess, "PasifikaMarketplace: refund failed");
        }
        
        emit ItemSold(listingId, msg.sender, finalPrice);
    }
    
    /**
     * @dev Place a bid on an auction
     * @param listingId ID of the listing to bid on
     */
    function placeBid(uint256 listingId) external payable whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.status == ListingStatus.Active, "PasifikaMarketplace: auction not active");
        require(listing.listingType == ListingType.Auction, "PasifikaMarketplace: not an auction");
        require(block.timestamp < listing.endTime, "PasifikaMarketplace: auction ended");
        require(msg.sender != listing.seller, "PasifikaMarketplace: cannot bid on your own auction");
        
        // Apply tier discount if applicable
        uint256 minBid = listing.highestBid > 0 ? listing.highestBid * 105 / 100 : listing.price;
        uint256 discountedMinBid = _applyTierDiscount(minBid, msg.sender);
        
        require(msg.value >= discountedMinBid, "PasifikaMarketplace: bid too low");
        
        // Refund previous highest bidder
        if (listing.highestBidder != address(0)) {
            pendingWithdrawals[listingId][listing.highestBidder] += listing.highestBid;
        }
        
        // Update highest bid
        listing.highestBidder = msg.sender;
        listing.highestBid = msg.value;
        
        emit AuctionBid(listingId, msg.sender, msg.value);
    }
    
    /**
     * @dev Finalize an auction after it ends
     * @param listingId ID of the auction to finalize
     */
    function finalizeAuction(uint256 listingId) external whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.status == ListingStatus.Active, "PasifikaMarketplace: auction not active");
        require(listing.listingType == ListingType.Auction, "PasifikaMarketplace: not an auction");
        require(block.timestamp >= listing.endTime, "PasifikaMarketplace: auction not ended");
        
        // Mark as sold
        listing.status = ListingStatus.Sold;
        
        // If no bids, return NFT to seller
        if (listing.highestBidder == address(0)) {
            IERC721(listing.nftContract).transferFrom(address(this), listing.seller, listing.tokenId);
            emit ListingCancelled(listingId);
            return;
        }
        
        uint256 finalPrice = listing.highestBid;
        
        // Handle royalties
        uint256 remainingAmount = finalPrice;
        uint256 royaltyAmount = 0;
        
        try IERC2981(listing.nftContract).royaltyInfo(listing.tokenId, finalPrice) returns (address receiver, uint256 royaltyFee) {
            if (royaltyFee > 0 && receiver != address(0)) {
                royaltyAmount = royaltyFee;
                remainingAmount = finalPrice - royaltyAmount;
                
                // Transfer royalties
                (bool royaltySuccess, ) = payable(receiver).call{value: royaltyAmount}("");
                require(royaltySuccess, "PasifikaMarketplace: royalty transfer failed");
                
                emit RoyaltyPaid(listing.tokenId, receiver, royaltyAmount);
            }
        } catch {
            // No royalty support, continue
        }
        
        // Calculate platform fee
        uint256 fee = _calculateFee(listing.highestBidder, remainingAmount);
        uint256 sellerAmount = remainingAmount - fee;
        
        // Calculate treasury allocation
        uint256 treasuryAmount = (fee * treasuryAllocation) / 10000;
        uint256 feeManagerAmount = fee - treasuryAmount;
        
        // Handle payment based on escrow setting
        if (listing.escrow) {
            // Hold funds in the contract
            pendingWithdrawals[listingId][listing.seller] = sellerAmount;
        } else {
            // Transfer funds to seller directly
            (bool success, ) = payable(listing.seller).call{value: sellerAmount}("");
            require(success, "PasifikaMarketplace: transfer to seller failed");
        }
        
        // Calculate total fee amount
        uint256 totalFee = treasuryAmount + feeManagerAmount;
        
        // Send total fee to treasury
        if (totalFee > 0) {
            // Use the depositFees function in the treasury
            (bool treasurySuccess, ) = address(treasury).call{value: totalFee}(
                abi.encodeWithSignature(
                    "depositFees(string)",
                    string(abi.encodePacked("Marketplace fee from NFT sale #", _toString(listing.tokenId)))
                )
            );
            require(treasurySuccess, "PasifikaMarketplace: treasury transfer failed");
        }
        
        // Transfer NFT to highest bidder
        IERC721(listing.nftContract).transferFrom(address(this), listing.highestBidder, listing.tokenId);
        
        emit ItemSold(listingId, listing.highestBidder, finalPrice);
    }
    
    /**
     * @dev Purchase a physical item
     * @param listingId ID of the listing to purchase
     */
    function purchasePhysicalItem(uint256 listingId) external payable whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.status == ListingStatus.Active, "PasifikaMarketplace: item not available");
        require(listing.listingType == ListingType.PhysicalItem, "PasifikaMarketplace: not a physical item");
        require(msg.value >= listing.price, "PasifikaMarketplace: insufficient payment");
        require(msg.sender != listing.seller, "PasifikaMarketplace: cannot buy your own item");
        
        // Apply tier discount if applicable
        uint256 finalPrice = _applyTierDiscount(listing.price, msg.sender);
        require(msg.value >= finalPrice, "PasifikaMarketplace: insufficient payment after discount");
        
        // Mark as sold
        listing.status = ListingStatus.Sold;
        
        // Handle royalties for our NFT contract
        uint256 remainingAmount = finalPrice;
        uint256 royaltyAmount = 0;
        
        try IERC2981(listing.nftContract).royaltyInfo(listing.tokenId, finalPrice) returns (address receiver, uint256 royaltyFee) {
            if (royaltyFee > 0 && receiver != address(0)) {
                royaltyAmount = royaltyFee;
                remainingAmount = finalPrice - royaltyAmount;
                
                // Transfer royalties
                (bool royaltySuccess, ) = payable(receiver).call{value: royaltyAmount}("");
                require(royaltySuccess, "PasifikaMarketplace: royalty transfer failed");
                
                emit RoyaltyPaid(listing.tokenId, receiver, royaltyAmount);
            }
        } catch {
            // No royalty support, continue
        }
        
        // Calculate platform fee
        uint256 fee = _calculateFee(msg.sender, remainingAmount);
        uint256 sellerAmount = remainingAmount - fee;
        
        // Calculate treasury allocation
        uint256 treasuryAmount = (fee * treasuryAllocation) / 10000;
        uint256 feeManagerAmount = fee - treasuryAmount;
        
        // Always use escrow for physical items to ensure delivery
        pendingWithdrawals[listingId][listing.seller] = sellerAmount;
        
        // Calculate total fee amount
        uint256 totalFee = treasuryAmount + feeManagerAmount;
        
        // Send total fee to treasury
        if (totalFee > 0) {
            // Use the depositFees function in the treasury
            (bool treasurySuccess, ) = address(treasury).call{value: totalFee}(
                abi.encodeWithSignature(
                    "depositFees(string)",
                    string(abi.encodePacked("Marketplace fee from NFT sale #", _toString(listing.tokenId)))
                )
            );
            require(treasurySuccess, "PasifikaMarketplace: treasury transfer failed");
        }
        
        // Refund excess payment
        if (msg.value > finalPrice) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: msg.value - finalPrice}("");
            require(refundSuccess, "PasifikaMarketplace: refund failed");
        }
        
        emit ItemSold(listingId, msg.sender, finalPrice);
    }
    
    /**
     * @dev Release funds from escrow after delivery confirmed
     * @param listingId ID of the listing
     */
    function releaseEscrow(uint256 listingId) external onlyRole(MARKET_MANAGER_ROLE) nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.status == ListingStatus.Sold, "PasifikaMarketplace: item not sold");
        require(listing.escrow, "PasifikaMarketplace: not using escrow");
        require(!escrowReleased[listingId], "PasifikaMarketplace: escrow already released");
        
        uint256 amount = pendingWithdrawals[listingId][listing.seller];
        require(amount > 0, "PasifikaMarketplace: no funds in escrow");
        
        // Mark escrow as released
        escrowReleased[listingId] = true;
        pendingWithdrawals[listingId][listing.seller] = 0;
        
        // Transfer funds to seller
        (bool success, ) = payable(listing.seller).call{value: amount}("");
        require(success, "PasifikaMarketplace: transfer from escrow failed");
        
        emit EscrowReleased(listingId, listing.seller, amount);
    }
    
    /**
     * @dev Cancel a listing (seller or admin)
     * @param listingId ID of the listing to cancel
     */
    function cancelListing(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.status == ListingStatus.Active, "PasifikaMarketplace: listing not active");
        require(msg.sender == listing.seller || hasRole(MARKET_MANAGER_ROLE, msg.sender), 
                "PasifikaMarketplace: not seller or manager");
        
        // Mark as cancelled
        listing.status = ListingStatus.Cancelled;
        
        // Return NFT to seller (if not a physical item)
        if (listing.listingType != ListingType.PhysicalItem) {
            IERC721(listing.nftContract).transferFrom(address(this), listing.seller, listing.tokenId);
        }
        
        emit ListingCancelled(listingId);
    }
    
    /**
     * @dev Withdraw pending funds (for auction refunds or escrow release)
     */
    function withdrawFunds(uint256 listingId) external nonReentrant {
        uint256 amount = pendingWithdrawals[listingId][msg.sender];
        require(amount > 0, "PasifikaMarketplace: no funds to withdraw");
        
        // Clear pending withdrawal before sending
        pendingWithdrawals[listingId][msg.sender] = 0;
        
        // Transfer funds
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "PasifikaMarketplace: withdrawal failed");
    }
    
    /**
     * @dev Apply tier discount based on staking tier
     * @param price Original price
     * @param buyer Buyer address
     * @return Discounted price
     */
    function _applyTierDiscount(uint256 price, address buyer) internal view returns (uint256) {
        // Get highest tier from ArbitrumTokenAdapter
        uint256 highestTier = 0;
        
        // Try to check if buyer has any tier
        for (uint256 i = 6; i >= 1; i--) {
            if (arbitrumTokenAdapter.hasTier(buyer, i)) {
                highestTier = i;
                break;
            }
        }
        
        // No tier or basic tier, no discount
        if (highestTier <= 1) {
            return price;
        }
        
        // Apply discount
        uint256 discount = (price * tierDiscounts[highestTier].discountPercent) / 100;
        return price - discount;
    }
    
    /**
     * @dev Sets the node contract address
     * @param _nodeContract Address of the PasifikaArbitrumNode contract
     */
    function setNodeContract(address payable _nodeContract) external onlyRole(ADMIN_ROLE) {
        require(_nodeContract != address(0), "PasifikaMarketplace: zero address");
        nodeContract = PasifikaArbitrumNode(_nodeContract);
        emit NodeContractUpdated(_nodeContract);
    }
    
    /**
     * @dev Sets the validator fee percentage (in basis points)
     * @param _validatorFeePercent New validator fee percentage
     */
    function setValidatorFeePercent(uint256 _validatorFeePercent) external onlyRole(ADMIN_ROLE) {
        require(_validatorFeePercent <= 1000, "PasifikaMarketplace: fee too high"); // Max 10%
        validatorFeePercent = _validatorFeePercent;
        emit ValidatorFeePercentUpdated(_validatorFeePercent);
    }
    
    /**
     * @dev Calculates the fee amount based on transaction amount
     * @param sender Address of the sender/buyer
     * @param amount Transaction amount
     * @return Fee amount
     */
    function _calculateFee(address sender, uint256 amount) internal view returns (uint256) {
        uint256 feePercentToUse = baseFeePercent;
        
        // Check if sender is a validator node operator
        if (address(nodeContract) != address(0) && nodeContract.isActiveNodeOperator(sender)) {
            feePercentToUse = validatorFeePercent; // 0.25% for validators
        } 
        // If not a validator, check if they're a member
        else if (address(membershipContract) != address(0) && membershipContract.checkMembership(sender)) {
            feePercentToUse = memberFeePercent; // 0.5% for members
        }
        
        uint256 fee = (amount * feePercentToUse) / 10000;
        return fee;
    }
    
    /**
     * @dev Set the treasury contract address
     * @param _treasury New treasury address
     */
    function setTreasury(address payable _treasury) external onlyRole(ADMIN_ROLE) {
        require(_treasury != address(0), "PasifikaMarketplace: zero address");
        treasury = PasifikaTreasury(_treasury);
    }
    
    /**
     * @dev Initialize the treasury integration
     * This is called once after deployment to register the marketplace as fee collector
     */
    function initializeTreasury() external onlyRole(ADMIN_ROLE) {
        // Request to be added as a fee collector
        treasury.addFeeCollector(address(this));
    }
    
    /**
     * @dev Set the membership contract address
     * @param _membership New membership contract address
     */
    function setMembershipContract(address payable _membership) external onlyRole(ADMIN_ROLE) {
        require(_membership != address(0), "PasifikaMarketplace: zero address");
        membershipContract = PasifikaMembership(_membership);
    }
    
    /**
     * @dev Helper function to convert uint256 to string
     * @param value uint256 to convert
     * @return String representation of the uint256
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        // Special case for 0
        if (value == 0) {
            return "0";
        }
        
        // Calculate length of decimal representation
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        // Allocate byte array with length
        bytes memory buffer = new bytes(digits);
        
        // Fill buffer in reverse
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }
    
    /**
     * @dev Get listing details
     * @param listingId ID of the listing
     * @return Full listing data
     */
    function getListingDetails(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }
    
    /**
     * @dev Get active listings count
     * @return Number of active listings
     */
    function getActiveListingsCount() external view returns (uint256) {
        uint256 count = 0;
        
        for (uint256 i = 0; i < listingCounter; i++) {
            if (listings[i].status == ListingStatus.Active) {
                count++;
            }
        }
        
        return count;
    }
    
    /**
     * @dev Get price with tier discount applied
     * @param price Original price
     * @param buyer Buyer address
     * @return Final price after discount
     */
    function getPriceWithDiscount(uint256 price, address buyer) external view returns (uint256) {
        return _applyTierDiscount(price, buyer);
    }
    
    /**
     * @dev Pause the marketplace
     * Can only be called by an admin
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpause the marketplace
     * Can only be called by an admin
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
    
    /**
     * @dev Allow receiving ETH
     */
    receive() external payable {}
}