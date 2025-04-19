// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title PasifikaMarketplace
 * @dev Implementation of the marketplace for PASIFIKA ecosystem
 * Handles listings, purchases, auctions, and fees for NFTs
 */
contract PasifikaMarketplace is AccessControl, ReentrancyGuard, Pausable {
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    
    // Counter for listing IDs (native uint256 counter)
    uint256 private _nextListingId = 1;
    
    // State variables
    address public psfToken;
    address public feeManager;
    uint256 public marketplaceFeePercent = 500; // 5% (in basis points)
    uint256 public constant MAX_FEE_PERCENT = 1000; // 10% maximum fee
    
    // Listing status enum
    enum ListingStatus {
        Active,
        Sold,
        Cancelled,
        Expired
    }
    
    // Auction status enum
    enum AuctionStatus {
        Active,
        Ended,
        Cancelled
    }
    
    // Listing struct
    struct Listing {
        uint256 listingId;
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        bool isAuction;
        uint256 auctionEndTime;
        ListingStatus status;
        address highestBidder;
        uint256 highestBid;
        AuctionStatus auctionStatus;
        bool isEscrowRequired;
        bool buyerConfirmed;
        bool sellerConfirmed;
    }
    
    // Mappings
    mapping(uint256 => Listing) public listings;
    mapping(address => mapping(uint256 => bool)) public tokenListingStatus; // nftContract => tokenId => isListed
    mapping(uint256 => mapping(address => uint256)) public auctionBids; // listingId => bidder => amount
    
    // Events
    event ListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 price,
        bool isAuction,
        uint256 auctionEndTime
    );
    
    event ListingPriceChanged(
        uint256 indexed listingId,
        uint256 newPrice
    );
    
    event ListingCancelled(
        uint256 indexed listingId
    );
    
    event ItemPurchased(
        uint256 indexed listingId,
        address indexed buyer,
        uint256 price
    );
    
    event BidPlaced(
        uint256 indexed listingId,
        address indexed bidder,
        uint256 amount
    );
    
    event AuctionEnded(
        uint256 indexed listingId,
        address indexed winner,
        uint256 amount
    );
    
    event EscrowCompleted(
        uint256 indexed listingId,
        address buyer,
        address seller
    );
    
    event BuyerConfirmed(
        uint256 indexed listingId,
        address buyer
    );
    
    event SellerConfirmed(
        uint256 indexed listingId,
        address seller
    );
    
    /**
     * @dev Constructor - sets up initial marketplace parameters
     * @param _psfToken Address of the PSF token contract
     * @param _feeManager Address of the fee manager contract
     */
    constructor(address _psfToken, address _feeManager) {
        require(_psfToken != address(0), "PasifikaMarketplace: PSF token address cannot be zero");
        require(_feeManager != address(0), "PasifikaMarketplace: Fee manager address cannot be zero");
        
        psfToken = _psfToken;
        feeManager = _feeManager;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(FEE_MANAGER_ROLE, _feeManager);
    }
    
    /**
     * @dev Sets the marketplace fee percentage (in basis points)
     * @param _feePercent New fee percentage (e.g., 500 = 5%)
     */
    function setMarketplaceFeePercent(uint256 _feePercent) external onlyRole(ADMIN_ROLE) {
        require(_feePercent <= MAX_FEE_PERCENT, "PasifikaMarketplace: Fee percent exceeds maximum");
        marketplaceFeePercent = _feePercent;
    }
    
    /**
     * @dev Creates a new listing for an NFT
     * @param nftContract Address of the NFT contract
     * @param tokenId ID of the NFT
     * @param price Price in PSF tokens
     * @param isAuction Whether this is an auction listing
     * @param auctionDuration Duration of auction in seconds (0 for fixed price)
     * @param requiresEscrow Whether physical delivery requires escrow
     */
    function createListing(
        address nftContract,
        uint256 tokenId,
        uint256 price,
        bool isAuction,
        uint256 auctionDuration,
        bool requiresEscrow
    ) external whenNotPaused nonReentrant {
        require(price > 0, "PasifikaMarketplace: Price must be greater than zero");
        require(!tokenListingStatus[nftContract][tokenId], "PasifikaMarketplace: Item already listed");
        
        // Ensure seller owns the NFT and has approved this contract
        IERC721 nftInterface = IERC721(nftContract);
        require(nftInterface.ownerOf(tokenId) == msg.sender, "PasifikaMarketplace: Not the owner");
        require(nftInterface.isApprovedForAll(msg.sender, address(this)) || 
                nftInterface.getApproved(tokenId) == address(this), 
                "PasifikaMarketplace: Not approved for marketplace");
        
        // Process auction parameters
        uint256 auctionEndTime = 0;
        if (isAuction) {
            require(auctionDuration > 0, "PasifikaMarketplace: Auction duration must be set");
            auctionEndTime = block.timestamp + auctionDuration;
        }
        
        // Create listing
        uint256 listingId = _nextListingId;
        
        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            price: price,
            isAuction: isAuction,
            auctionEndTime: auctionEndTime,
            status: ListingStatus.Active,
            highestBidder: address(0),
            highestBid: 0,
            auctionStatus: isAuction ? AuctionStatus.Active : AuctionStatus.Cancelled,
            isEscrowRequired: requiresEscrow,
            buyerConfirmed: false,
            sellerConfirmed: false
        });
        
        // Mark token as listed
        tokenListingStatus[nftContract][tokenId] = true;
        
        // Increment counter
        _nextListingId++;
        
        emit ListingCreated(
            listingId,
            msg.sender,
            nftContract,
            tokenId,
            price,
            isAuction,
            auctionEndTime
        );
    }
    
    /**
     * @dev Cancels an existing listing
     * @param listingId ID of the listing to cancel
     */
    function cancelListing(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.seller == msg.sender || hasRole(ADMIN_ROLE, msg.sender), 
                "PasifikaMarketplace: Not the seller or admin");
        require(listing.status == ListingStatus.Active, "PasifikaMarketplace: Listing not active");
        
        // If it's an auction with bids, we can't cancel
        if (listing.isAuction && listing.highestBid > 0) {
            revert("PasifikaMarketplace: Cannot cancel auction with bids");
        }
        
        // Update listing status
        listing.status = ListingStatus.Cancelled;
        if (listing.isAuction) {
            listing.auctionStatus = AuctionStatus.Cancelled;
        }
        
        // Mark token as not listed
        tokenListingStatus[listing.nftContract][listing.tokenId] = false;
        
        emit ListingCancelled(listingId);
    }
    
    /**
     * @dev Changes the price of a fixed-price listing
     * @param listingId ID of the listing
     * @param newPrice New price in PSF tokens
     */
    function changeListingPrice(uint256 listingId, uint256 newPrice) external nonReentrant {
        require(newPrice > 0, "PasifikaMarketplace: Price must be greater than zero");
        
        Listing storage listing = listings[listingId];
        
        require(listing.seller == msg.sender, "PasifikaMarketplace: Not the seller");
        require(listing.status == ListingStatus.Active, "PasifikaMarketplace: Listing not active");
        require(!listing.isAuction, "PasifikaMarketplace: Cannot change auction price");
        
        // Update price
        listing.price = newPrice;
        
        emit ListingPriceChanged(listingId, newPrice);
    }
    
    /**
     * @dev Purchases a fixed-price item
     * @param listingId ID of the listing to purchase
     */
    function purchaseItem(uint256 listingId) external whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.status == ListingStatus.Active, "PasifikaMarketplace: Listing not active");
        require(!listing.isAuction, "PasifikaMarketplace: Cannot direct purchase an auction");
        require(msg.sender != listing.seller, "PasifikaMarketplace: Seller cannot buy their own item");
        
        // Calculate fees
        uint256 fee = listing.price * marketplaceFeePercent / 10000;
        uint256 sellerAmount = listing.price - fee;
        
        // Transfer PSF tokens from buyer to this contract
        IERC20 token = IERC20(psfToken);
        require(token.transferFrom(msg.sender, address(this), listing.price), 
                "PasifikaMarketplace: Transfer from buyer failed");
        
        // If escrow is required, hold the payment and NFT until confirmed
        if (listing.isEscrowRequired) {
            // Just mark the buyer, but don't transfer tokens or NFT yet
            listing.highestBidder = msg.sender;
            listing.highestBid = listing.price;
            
            emit ItemPurchased(listingId, msg.sender, listing.price);
            return;
        }
        
        // Otherwise, complete the sale immediately
        
        // Transfer fee to fee manager
        require(token.transfer(feeManager, fee), "PasifikaMarketplace: Fee transfer failed");
        
        // Transfer payment to seller
        require(token.transfer(listing.seller, sellerAmount), "PasifikaMarketplace: Seller payment failed");
        
        // Transfer NFT to buyer
        IERC721(listing.nftContract).safeTransferFrom(listing.seller, msg.sender, listing.tokenId);
        
        // Update listing
        listing.status = ListingStatus.Sold;
        tokenListingStatus[listing.nftContract][listing.tokenId] = false;
        
        emit ItemPurchased(listingId, msg.sender, listing.price);
    }
    
    /**
     * @dev Places a bid on an auction
     * @param listingId ID of the auction
     * @param bidAmount Bid amount in PSF tokens
     */
    function placeBid(uint256 listingId, uint256 bidAmount) external whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.status == ListingStatus.Active, "PasifikaMarketplace: Listing not active");
        require(listing.isAuction, "PasifikaMarketplace: Not an auction");
        require(listing.auctionStatus == AuctionStatus.Active, "PasifikaMarketplace: Auction not active");
        require(block.timestamp < listing.auctionEndTime, "PasifikaMarketplace: Auction ended");
        require(msg.sender != listing.seller, "PasifikaMarketplace: Seller cannot bid on their own item");
        
        // Check bid amount
        require(bidAmount > listing.highestBid, "PasifikaMarketplace: Bid not high enough");
        
        // Record previous bid to refund
        address previousBidder = listing.highestBidder;
        uint256 previousBid = listing.highestBid;
        
        // Transfer tokens from bidder to this contract
        IERC20 token = IERC20(psfToken);
        require(token.transferFrom(msg.sender, address(this), bidAmount), 
                "PasifikaMarketplace: Transfer from bidder failed");
        
        // Record bid
        listing.highestBidder = msg.sender;
        listing.highestBid = bidAmount;
        auctionBids[listingId][msg.sender] = bidAmount;
        
        // Refund previous bidder if there was one
        if (previousBidder != address(0)) {
            require(token.transfer(previousBidder, previousBid), 
                    "PasifikaMarketplace: Refund to previous bidder failed");
        }
        
        emit BidPlaced(listingId, msg.sender, bidAmount);
    }
    
    /**
     * @dev Ends an auction after its end time
     * @param listingId ID of the auction
     */
    function endAuction(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.isAuction, "PasifikaMarketplace: Not an auction");
        require(listing.auctionStatus == AuctionStatus.Active, "PasifikaMarketplace: Auction not active");
        require(block.timestamp >= listing.auctionEndTime, "PasifikaMarketplace: Auction not ended yet");
        
        // Mark auction as ended
        listing.auctionStatus = AuctionStatus.Ended;
        
        // If no bids, just close the auction
        if (listing.highestBidder == address(0)) {
            listing.status = ListingStatus.Expired;
            tokenListingStatus[listing.nftContract][listing.tokenId] = false;
            
            emit AuctionEnded(listingId, address(0), 0);
            return;
        }
        
        // Calculate fees
        uint256 fee = listing.highestBid * marketplaceFeePercent / 10000;
        uint256 sellerAmount = listing.highestBid - fee;
        
        // If escrow is required, wait for confirmation
        if (listing.isEscrowRequired) {
            emit AuctionEnded(listingId, listing.highestBidder, listing.highestBid);
            return;
        }
        
        // Otherwise complete the sale immediately
        
        // Transfer fee to fee manager
        IERC20 token = IERC20(psfToken);
        require(token.transfer(feeManager, fee), "PasifikaMarketplace: Fee transfer failed");
        
        // Transfer payment to seller
        require(token.transfer(listing.seller, sellerAmount), "PasifikaMarketplace: Seller payment failed");
        
        // Transfer NFT to winner
        IERC721(listing.nftContract).safeTransferFrom(listing.seller, listing.highestBidder, listing.tokenId);
        
        // Update listing
        listing.status = ListingStatus.Sold;
        tokenListingStatus[listing.nftContract][listing.tokenId] = false;
        
        emit AuctionEnded(listingId, listing.highestBidder, listing.highestBid);
    }
    
    /**
     * @dev Confirms receipt of physical item (from buyer)
     * @param listingId ID of the listing
     */
    function confirmReceived(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.isEscrowRequired, "PasifikaMarketplace: Not in escrow");
        require(listing.status == ListingStatus.Active, "PasifikaMarketplace: Listing not active");
        require(msg.sender == listing.highestBidder, "PasifikaMarketplace: Not the buyer");
        require(!listing.buyerConfirmed, "PasifikaMarketplace: Already confirmed");
        
        // Mark as confirmed by buyer
        listing.buyerConfirmed = true;
        
        emit BuyerConfirmed(listingId, msg.sender);
        
        // If both have confirmed, complete the transaction
        if (listing.buyerConfirmed && listing.sellerConfirmed) {
            _completeEscrow(listingId);
        }
    }
    
    /**
     * @dev Confirms shipping of physical item (from seller)
     * @param listingId ID of the listing
     */
    function confirmShipped(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.isEscrowRequired, "PasifikaMarketplace: Not in escrow");
        require(listing.status == ListingStatus.Active, "PasifikaMarketplace: Listing not active");
        require(msg.sender == listing.seller, "PasifikaMarketplace: Not the seller");
        require(!listing.sellerConfirmed, "PasifikaMarketplace: Already confirmed");
        
        // Mark as confirmed by seller
        listing.sellerConfirmed = true;
        
        emit SellerConfirmed(listingId, msg.sender);
        
        // If both have confirmed, complete the transaction
        if (listing.buyerConfirmed && listing.sellerConfirmed) {
            _completeEscrow(listingId);
        }
    }
    
    /**
     * @dev Internal function to complete escrow after confirmations
     * @param listingId ID of the listing
     */
    function _completeEscrow(uint256 listingId) internal {
        Listing storage listing = listings[listingId];
        
        // Calculate fees
        uint256 fee = listing.highestBid * marketplaceFeePercent / 10000;
        uint256 sellerAmount = listing.highestBid - fee;
        
        // Transfer fee to fee manager
        IERC20 token = IERC20(psfToken);
        require(token.transfer(feeManager, fee), "PasifikaMarketplace: Fee transfer failed");
        
        // Transfer payment to seller
        require(token.transfer(listing.seller, sellerAmount), "PasifikaMarketplace: Seller payment failed");
        
        // Transfer NFT to winner
        IERC721(listing.nftContract).safeTransferFrom(listing.seller, listing.highestBidder, listing.tokenId);
        
        // Update listing
        listing.status = ListingStatus.Sold;
        tokenListingStatus[listing.nftContract][listing.tokenId] = false;
        
        emit EscrowCompleted(listingId, listing.highestBidder, listing.seller);
    }
    
    /**
     * @dev Allows admins to resolve disputes for escrow
     * @param listingId ID of the listing
     * @param releaseToSeller Whether to release funds to seller
     */
    function resolveDispute(uint256 listingId, bool releaseToSeller) external onlyRole(ADMIN_ROLE) nonReentrant {
        Listing storage listing = listings[listingId];
        
        require(listing.isEscrowRequired, "PasifikaMarketplace: Not in escrow");
        require(listing.status == ListingStatus.Active, "PasifikaMarketplace: Listing not active");
        require(listing.highestBidder != address(0), "PasifikaMarketplace: No buyer");
        
        if (releaseToSeller) {
            // Calculate fees
            uint256 fee = listing.highestBid * marketplaceFeePercent / 10000;
            uint256 sellerAmount = listing.highestBid - fee;
            
            // Transfer fee to fee manager
            IERC20 token = IERC20(psfToken);
            require(token.transfer(feeManager, fee), "PasifikaMarketplace: Fee transfer failed");
            
            // Transfer payment to seller
            require(token.transfer(listing.seller, sellerAmount), "PasifikaMarketplace: Seller payment failed");
            
            // Transfer NFT to buyer
            IERC721(listing.nftContract).safeTransferFrom(listing.seller, listing.highestBidder, listing.tokenId);
        } else {
            // Refund buyer
            IERC20 token = IERC20(psfToken);
            require(token.transfer(listing.highestBidder, listing.highestBid), 
                    "PasifikaMarketplace: Refund to buyer failed");
        }
        
        // Update listing
        listing.status = ListingStatus.Cancelled;
        tokenListingStatus[listing.nftContract][listing.tokenId] = false;
    }
    
    /**
     * @dev Pause the marketplace
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpause the marketplace
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
    
    /**
     * @dev Gets the details of a listing
     * @param listingId ID of the listing
     * @return Listing struct with details
     */
    function getListingDetails(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }
    
    /**
     * @dev Gets the current number of listings
     * @return Total count of listings created
     */
    function getListingCount() external view returns (uint256) {
        return _nextListingId - 1;
    }
}