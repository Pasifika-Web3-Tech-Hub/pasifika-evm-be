// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/PasifikaMarketplace.sol";
import "../src/PSFToken.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// Simple mockup NFT contract for testing
contract MockNFT is ERC721 {
    uint256 private _tokenIdCounter = 1;
    
    constructor() ERC721("Mock NFT", "MNFT") {}
    
    function mint(address to) external returns (uint256) {
        uint256 tokenId = _tokenIdCounter;
        _mint(to, tokenId);
        _tokenIdCounter++;
        return tokenId;
    }
}

contract PasifikaMarketplaceTest is Test {
    PasifikaMarketplace public marketplace;
    PSFToken public psfToken;
    MockNFT public mockNFT;
    
    // Test accounts
    address public admin = address(1);
    address public feeManager = address(2);
    address public seller = address(3);
    address public buyer = address(4);
    address public bidder1 = address(5);
    address public bidder2 = address(6);
    address public validator = address(7);
    
    // Constants for testing
    uint256 constant INITIAL_PSF_SUPPLY = 1000000 * 10**18; // 1 million PSF
    uint256 constant LISTING_PRICE = 1000 * 10**18; // 1000 PSF
    uint256 constant BID_AMOUNT = 1200 * 10**18; // 1200 PSF
    uint256 constant HIGHER_BID = 1500 * 10**18; // 1500 PSF
    uint256 constant AUCTION_DURATION = 3 days;
    
    function setUp() public {
        // Deploy PSF token
        vm.startPrank(admin);
        psfToken = new PSFToken();
        
        // Deploy mock NFT
        mockNFT = new MockNFT();
        
        // Deploy marketplace with PSF token and fee manager
        marketplace = new PasifikaMarketplace(address(psfToken), feeManager);
        
        // Grant roles
        marketplace.grantRole(marketplace.VALIDATOR_ROLE(), validator);
        vm.stopPrank();
        
        // Mint tokens to users
        vm.startPrank(admin);
        // Admin is the minter of PSF tokens
        psfToken.mint(seller, INITIAL_PSF_SUPPLY);
        psfToken.mint(buyer, INITIAL_PSF_SUPPLY);
        psfToken.mint(bidder1, INITIAL_PSF_SUPPLY);
        psfToken.mint(bidder2, INITIAL_PSF_SUPPLY);
        vm.stopPrank();
    }

    function testDeployment() public {
        // Check role assignments and addresses
        assertTrue(marketplace.hasRole(marketplace.ADMIN_ROLE(), admin));
        assertTrue(marketplace.hasRole(marketplace.FEE_MANAGER_ROLE(), feeManager));
        assertTrue(marketplace.hasRole(marketplace.VALIDATOR_ROLE(), validator));
        
        assertEq(marketplace.psfToken(), address(psfToken));
        assertEq(marketplace.feeManager(), address(feeManager));
        
        // Check initial marketplace fee
        assertEq(marketplace.marketplaceFeePercent(), 500); // 5%
    }
    
    function testCreateFixedPriceListing() public {
        // Mint NFT to seller
        vm.prank(admin);
        uint256 tokenId = mockNFT.mint(seller);
        
        // Approve marketplace to transfer the NFT
        vm.startPrank(seller);
        mockNFT.approve(address(marketplace), tokenId);
        
        // Create listing
        marketplace.createListing(
            address(mockNFT),
            tokenId,
            LISTING_PRICE,
            false, // not an auction
            0, // no auction duration
            false // no escrow
        );
        vm.stopPrank();
        
        // Check listing details
        PasifikaMarketplace.Listing memory listing = marketplace.getListingDetails(1);
        assertEq(listing.listingId, 1);
        assertEq(listing.seller, seller);
        assertEq(listing.nftContract, address(mockNFT));
        assertEq(listing.tokenId, tokenId);
        assertEq(listing.price, LISTING_PRICE);
        assertFalse(listing.isAuction);
        assertEq(uint(listing.status), uint(PasifikaMarketplace.ListingStatus.Active));
    }
    
    function testCreateAuctionListing() public {
        // Mint NFT to seller
        vm.prank(admin);
        uint256 tokenId = mockNFT.mint(seller);
        
        // Approve marketplace to transfer the NFT
        vm.startPrank(seller);
        mockNFT.approve(address(marketplace), tokenId);
        
        // Create auction listing
        marketplace.createListing(
            address(mockNFT),
            tokenId,
            LISTING_PRICE, // starting price
            true, // auction
            AUCTION_DURATION,
            false // no escrow
        );
        vm.stopPrank();
        
        // Check listing details
        PasifikaMarketplace.Listing memory listing = marketplace.getListingDetails(1);
        assertEq(listing.listingId, 1);
        assertEq(listing.seller, seller);
        assertEq(listing.nftContract, address(mockNFT));
        assertEq(listing.tokenId, tokenId);
        assertEq(listing.price, LISTING_PRICE);
        assertTrue(listing.isAuction);
        assertEq(listing.auctionEndTime, block.timestamp + AUCTION_DURATION);
        assertEq(uint(listing.status), uint(PasifikaMarketplace.ListingStatus.Active));
    }
    
    function testCancelListing() public {
        // Create a listing first
        testCreateFixedPriceListing();
        
        // Cancel the listing
        vm.prank(seller);
        marketplace.cancelListing(1);
        
        // Check listing is cancelled
        PasifikaMarketplace.Listing memory listing = marketplace.getListingDetails(1);
        assertEq(uint(listing.status), uint(PasifikaMarketplace.ListingStatus.Cancelled));
        
        // Verify token is no longer listed
        assertFalse(marketplace.tokenListingStatus(address(mockNFT), listing.tokenId));
    }
    
    function testChangeListingPrice() public {
        // Create a listing first
        testCreateFixedPriceListing();
        
        uint256 newPrice = LISTING_PRICE * 2;
        
        // Change the price
        vm.prank(seller);
        marketplace.changeListingPrice(1, newPrice);
        
        // Check price was updated
        PasifikaMarketplace.Listing memory listing = marketplace.getListingDetails(1);
        assertEq(listing.price, newPrice);
    }
    
    function testPurchaseItem() public {
        // Create a listing first
        testCreateFixedPriceListing();
        
        // Approve tokens for the purchase
        vm.startPrank(buyer);
        psfToken.approve(address(marketplace), LISTING_PRICE);
        
        // Purchase the item
        marketplace.purchaseItem(1);
        vm.stopPrank();
        
        // Check listing is marked as sold
        PasifikaMarketplace.Listing memory listing = marketplace.getListingDetails(1);
        assertEq(uint(listing.status), uint(PasifikaMarketplace.ListingStatus.Sold));
        
        // Check NFT ownership
        assertEq(mockNFT.ownerOf(listing.tokenId), buyer);
        
        // Check token balances
        uint256 fee = LISTING_PRICE * marketplace.marketplaceFeePercent() / 10000;
        uint256 sellerPayout = LISTING_PRICE - fee;
        
        // Check fee manager received the fee
        assertEq(psfToken.balanceOf(feeManager), fee);
        
        // Check seller received payment (minus fee)
        assertEq(psfToken.balanceOf(seller), INITIAL_PSF_SUPPLY + sellerPayout);
        
        // Check buyer paid the price
        assertEq(psfToken.balanceOf(buyer), INITIAL_PSF_SUPPLY - LISTING_PRICE);
    }
    
    function testPlaceBid() public {
        // Create an auction listing first
        testCreateAuctionListing();
        
        // Approve tokens for bidding
        vm.startPrank(bidder1);
        psfToken.approve(address(marketplace), BID_AMOUNT);
        
        // Place a bid
        marketplace.placeBid(1, BID_AMOUNT);
        vm.stopPrank();
        
        // Check highest bid is recorded
        PasifikaMarketplace.Listing memory listing = marketplace.getListingDetails(1);
        assertEq(listing.highestBidder, bidder1);
        assertEq(listing.highestBid, BID_AMOUNT);
        
        // Check bidder's tokens are held
        assertEq(psfToken.balanceOf(bidder1), INITIAL_PSF_SUPPLY - BID_AMOUNT);
    }
    
    function testOutbid() public {
        // Place an initial bid
        testPlaceBid();
        
        // Place a higher bid
        vm.startPrank(bidder2);
        psfToken.approve(address(marketplace), HIGHER_BID);
        
        // Place a higher bid
        marketplace.placeBid(1, HIGHER_BID);
        vm.stopPrank();
        
        // Check the new highest bid is recorded
        PasifikaMarketplace.Listing memory listing = marketplace.getListingDetails(1);
        assertEq(listing.highestBidder, bidder2);
        assertEq(listing.highestBid, HIGHER_BID);
        
        // Check first bidder was refunded
        assertEq(psfToken.balanceOf(bidder1), INITIAL_PSF_SUPPLY);
        
        // Check second bidder's tokens are held
        assertEq(psfToken.balanceOf(bidder2), INITIAL_PSF_SUPPLY - HIGHER_BID);
    }
    
    function testFinalizeAuction() public {
        // Create an auction with bids
        testOutbid();
        
        // Fast forward past auction end time
        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        
        // Finalize the auction
        vm.prank(seller);
        marketplace.endAuction(1);
        
        // Check auction ended
        PasifikaMarketplace.Listing memory listing = marketplace.getListingDetails(1);
        assertEq(uint(listing.status), uint(PasifikaMarketplace.ListingStatus.Sold));
        assertEq(uint(listing.auctionStatus), uint(PasifikaMarketplace.AuctionStatus.Ended));
        
        // Check NFT was transferred to the highest bidder
        assertEq(mockNFT.ownerOf(listing.tokenId), bidder2);
        
        // Check seller received payment minus fees
        uint256 fee = HIGHER_BID * marketplace.marketplaceFeePercent() / 10000;
        uint256 sellerPayout = HIGHER_BID - fee;
        
        // Check fee manager received the fee
        assertEq(psfToken.balanceOf(feeManager), fee);
        
        // Check seller received payment
        assertEq(psfToken.balanceOf(seller), INITIAL_PSF_SUPPLY + sellerPayout);
    }
    
    function testEscrowFlow() public {
        // Mint NFT to seller
        vm.prank(admin);
        uint256 tokenId = mockNFT.mint(seller);
        
        // Approve marketplace to transfer the NFT
        vm.startPrank(seller);
        mockNFT.approve(address(marketplace), tokenId);
        
        // Create listing with escrow
        marketplace.createListing(
            address(mockNFT),
            tokenId,
            LISTING_PRICE,
            true, // auction
            AUCTION_DURATION,
            true // with escrow
        );
        vm.stopPrank();
        
        // Place a bid
        vm.startPrank(bidder1);
        psfToken.approve(address(marketplace), BID_AMOUNT);
        marketplace.placeBid(1, BID_AMOUNT);
        vm.stopPrank();
        
        // Fast forward past auction end time
        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        
        // Finalize the auction
        vm.prank(seller);
        marketplace.endAuction(1);
        
        // Verify auction is finalized but in escrow
        PasifikaMarketplace.Listing memory listing = marketplace.getListingDetails(1);
        assertEq(uint(listing.auctionStatus), uint(PasifikaMarketplace.AuctionStatus.Ended));
        assertTrue(listing.isEscrowRequired);
        assertFalse(listing.buyerConfirmed);
        assertFalse(listing.sellerConfirmed);
        
        // Buyer confirms
        vm.prank(bidder1);
        marketplace.confirmReceived(1);
        
        // Check buyer confirmed
        listing = marketplace.getListingDetails(1);
        assertTrue(listing.buyerConfirmed);
        
        // Seller confirms
        vm.prank(seller);
        marketplace.confirmShipped(1);
        
        // Check escrow is completed
        listing = marketplace.getListingDetails(1);
        assertEq(uint(listing.status), uint(PasifikaMarketplace.ListingStatus.Sold));
        assertTrue(listing.buyerConfirmed);
        assertTrue(listing.sellerConfirmed);
        
        // Check NFT ownership
        assertEq(mockNFT.ownerOf(listing.tokenId), bidder1);
        
        // Check payments
        uint256 fee = BID_AMOUNT * marketplace.marketplaceFeePercent() / 10000;
        uint256 sellerPayout = BID_AMOUNT - fee;
        
        assertEq(psfToken.balanceOf(feeManager), fee);
        assertEq(psfToken.balanceOf(seller), INITIAL_PSF_SUPPLY + sellerPayout);
        assertEq(psfToken.balanceOf(bidder1), INITIAL_PSF_SUPPLY - BID_AMOUNT);
    }
    
    function testDisputeResolution() public {
        // Create an escrow situation
        // Mint NFT to seller
        vm.prank(admin);
        uint256 tokenId = mockNFT.mint(seller);
        
        // Approve marketplace to transfer the NFT
        vm.startPrank(seller);
        mockNFT.approve(address(marketplace), tokenId);
        
        // Create listing with escrow
        marketplace.createListing(
            address(mockNFT),
            tokenId,
            LISTING_PRICE,
            true, // auction
            AUCTION_DURATION,
            true // with escrow
        );
        vm.stopPrank();
        
        // Place a bid
        vm.startPrank(bidder1);
        psfToken.approve(address(marketplace), BID_AMOUNT);
        marketplace.placeBid(1, BID_AMOUNT);
        vm.stopPrank();
        
        // Fast forward past auction end time
        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        
        // Finalize the auction
        vm.prank(seller);
        marketplace.endAuction(1);
        
        // Admin resolves dispute in favor of seller
        vm.prank(admin);
        marketplace.resolveDispute(1, true);
        
        // Check payments went to seller
        uint256 fee = BID_AMOUNT * marketplace.marketplaceFeePercent() / 10000;
        uint256 sellerPayout = BID_AMOUNT - fee;
        
        assertEq(psfToken.balanceOf(feeManager), fee);
        assertEq(psfToken.balanceOf(seller), INITIAL_PSF_SUPPLY + sellerPayout);
        
        // Check NFT was transferred
        assertEq(mockNFT.ownerOf(tokenId), bidder1);
        
        // Check listing is cancelled
        PasifikaMarketplace.Listing memory listing = marketplace.getListingDetails(1);
        assertEq(uint(listing.status), uint(PasifikaMarketplace.ListingStatus.Cancelled));
    }
    
    function testDisputeResolutionBuyerFavor() public {
        // Create an escrow situation
        // Mint NFT to seller
        vm.prank(admin);
        uint256 tokenId = mockNFT.mint(seller);
        
        // Approve marketplace to transfer the NFT
        vm.startPrank(seller);
        mockNFT.approve(address(marketplace), tokenId);
        
        // Create listing with escrow
        marketplace.createListing(
            address(mockNFT),
            tokenId,
            LISTING_PRICE,
            true, // auction
            AUCTION_DURATION,
            true // with escrow
        );
        vm.stopPrank();
        
        // Place a bid
        vm.startPrank(bidder1);
        psfToken.approve(address(marketplace), BID_AMOUNT);
        marketplace.placeBid(1, BID_AMOUNT);
        vm.stopPrank();
        
        // Fast forward past auction end time
        vm.warp(block.timestamp + AUCTION_DURATION + 1);
        
        // Finalize the auction
        vm.prank(seller);
        marketplace.endAuction(1);
        
        // Admin resolves dispute in favor of buyer
        vm.prank(admin);
        marketplace.resolveDispute(1, false);
        
        // Check buyer was refunded
        assertEq(psfToken.balanceOf(bidder1), INITIAL_PSF_SUPPLY);
        
        // NFT should still be with seller
        assertEq(mockNFT.ownerOf(tokenId), seller);
        
        // Check listing is cancelled
        PasifikaMarketplace.Listing memory listing = marketplace.getListingDetails(1);
        assertEq(uint(listing.status), uint(PasifikaMarketplace.ListingStatus.Cancelled));
    }
    
    function testPauseUnpause() public {
        // Admin pauses the marketplace
        vm.prank(admin);
        marketplace.pause();
        
        // Check marketplace is paused
        assertTrue(marketplace.paused());
        
        // Mint NFT to seller
        vm.prank(admin);
        uint256 tokenId = mockNFT.mint(seller);
        
        // Approve marketplace to transfer the NFT
        vm.startPrank(seller);
        mockNFT.approve(address(marketplace), tokenId);
        
        // Creating a listing should revert when paused
        vm.expectRevert();
        marketplace.createListing(
            address(mockNFT),
            tokenId,
            LISTING_PRICE,
            false,
            0,
            false
        );
        vm.stopPrank();
        
        // Admin unpauses the marketplace
        vm.prank(admin);
        marketplace.unpause();
        
        // Check marketplace is unpaused
        assertFalse(marketplace.paused());
        
        // Now creating a listing should succeed
        vm.startPrank(seller);
        marketplace.createListing(
            address(mockNFT),
            tokenId,
            LISTING_PRICE,
            false,
            0,
            false
        );
        vm.stopPrank();
        
        // Verify listing was created
        PasifikaMarketplace.Listing memory listing = marketplace.getListingDetails(1);
        assertEq(listing.listingId, 1);
        assertEq(listing.seller, seller);
        assertEq(listing.nftContract, address(mockNFT));
        assertEq(listing.tokenId, tokenId);
        assertEq(listing.price, LISTING_PRICE);
    }
    
    function testListingCount() public {
        // Create multiple listings
        // Listing 1
        vm.prank(admin);
        uint256 tokenId1 = mockNFT.mint(seller);
        
        vm.startPrank(seller);
        mockNFT.approve(address(marketplace), tokenId1);
        marketplace.createListing(
            address(mockNFT),
            tokenId1,
            LISTING_PRICE,
            false,
            0,
            false
        );
        vm.stopPrank();
        
        // Listing 2
        vm.prank(admin);
        uint256 tokenId2 = mockNFT.mint(seller);
        
        vm.startPrank(seller);
        mockNFT.approve(address(marketplace), tokenId2);
        marketplace.createListing(
            address(mockNFT),
            tokenId2,
            LISTING_PRICE * 2,
            true,
            AUCTION_DURATION,
            true
        );
        vm.stopPrank();
        
        // Check listing count
        assertEq(marketplace.getListingCount(), 2);
    }
}
