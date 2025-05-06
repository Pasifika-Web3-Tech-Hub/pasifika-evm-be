// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test, console } from "forge-std/Test.sol";
import { PasifikaNFT } from "../src/PasifikaNFT.sol";
import { PasifikaMembership } from "../src/PasifikaMembership.sol";
import { PasifikaTreasury } from "../src/PasifikaTreasury.sol";

contract PasifikaNFTTest is Test {
    PasifikaNFT public nft;
    PasifikaMembership public membership;
    PasifikaTreasury public treasury;

    address public admin = address(0x1);
    address public creator = address(0x2);
    address public buyer = address(0x3);
    address public memberBuyer = address(0x4);

    uint96 public defaultRoyaltyPercent = 100; // 1%
    uint96 public memberRoyaltyPercent = 50; // 0.5%
    uint256 public membershipFee = 0.5 ether;

    address mockRifToken = address(0x1234567890123456789012345678901234567890);

    function setUp() public {
        vm.startPrank(admin);

        // Deploy contracts
        treasury = new PasifikaTreasury(admin);
        membership = new PasifikaMembership(payable(address(treasury)));
        nft = new PasifikaNFT("Pasifika NFT", "PNFT", "https://pasifika.io/metadata/");

        // Grant FEE_COLLECTOR_ROLE to membership contract
        treasury.grantRole(keccak256("FEE_COLLECTOR_ROLE"), address(membership));

        // Set royalty percentages
        nft.setDefaultRoyalty(defaultRoyaltyPercent);
        nft.setMemberRoyalty(memberRoyaltyPercent);

        // Set membership contract
        nft.setMembershipContract(payable(address(membership)));

        // Add NFT minter role to creator
        nft.grantRole(keccak256("MINTER_ROLE"), creator);

        vm.stopPrank();

        // Fund test accounts
        vm.deal(creator, 10 ether);
        vm.deal(buyer, 10 ether);
        vm.deal(memberBuyer, 10 ether);

        // Make memberBuyer a member
        vm.startPrank(memberBuyer);
        membership.joinMembership{ value: membershipFee }();
        vm.stopPrank();
    }

    function test_MintNFT() public {
        vm.startPrank(creator);

        // Mint an NFT
        uint256 tokenId = nft.mint(
            creator,
            "ipfs://QmZ1Hg8dXm4nHUsyQXQXe8g5HCPxpXsXF3Kxnfm8NZ6hXH",
            PasifikaNFT.ItemType.Digital,
            defaultRoyaltyPercent,
            ""
        );

        // Verify ownership
        assertEq(nft.ownerOf(tokenId), creator);

        // Verify token URI
        assertEq(
            nft.tokenURI(tokenId), "https://pasifika.io/metadata/ipfs://QmZ1Hg8dXm4nHUsyQXQXe8g5HCPxpXsXF3Kxnfm8NZ6hXH"
        );

        vm.stopPrank();
    }

    function test_RoyaltyInfo() public {
        vm.startPrank(creator);

        // Mint an NFT
        uint256 tokenId = nft.mint(
            creator,
            "ipfs://QmZ1Hg8dXm4nHUsyQXQXe8g5HCPxpXsXF3Kxnfm8NZ6hXH",
            PasifikaNFT.ItemType.Digital,
            defaultRoyaltyPercent,
            ""
        );

        vm.stopPrank();

        // Get royalty info as normal buyer
        vm.startPrank(buyer);
        uint256 salePrice = 1 ether;
        (address royaltyReceiver, uint256 royaltyAmount) = nft.royaltyInfo(tokenId, salePrice);

        // Verify royalty receiver and amount
        assertEq(royaltyReceiver, creator);
        // 1% of 1 ether = 0.01 ether
        assertEq(royaltyAmount, (salePrice * defaultRoyaltyPercent) / 10000);

        vm.stopPrank();

        // Get royalty info as member buyer
        vm.startPrank(memberBuyer);
        (address memberRoyaltyReceiver, uint256 memberRoyaltyAmount) = nft.royaltyInfo(tokenId, salePrice);

        // Verify royalty receiver and the reduced amount for member
        assertEq(memberRoyaltyReceiver, creator);
        // 0.5% of 1 ether = 0.005 ether
        assertEq(memberRoyaltyAmount, (salePrice * memberRoyaltyPercent) / 10000);

        vm.stopPrank();
    }

    function test_PhysicalItemMint() public {
        vm.startPrank(creator);

        // Mint a physical item NFT
        string memory physicalDetails = '{"location": "Fiji", "dimensions": "30x20x10cm", "weight": "2kg"}';
        uint256 tokenId = nft.mint(
            creator, "ipfs://QmPhysical123456789", PasifikaNFT.ItemType.Physical, defaultRoyaltyPercent, physicalDetails
        );

        // Verify item type
        (,, PasifikaNFT.ItemType itemType,,) = nft.getMetadata(tokenId);
        assertEq(uint256(itemType), uint256(PasifikaNFT.ItemType.Physical));

        // Verify physical details
        (,,,, string memory details) = nft.getMetadata(tokenId);
        assertEq(details, physicalDetails);

        vm.stopPrank();
    }

    function test_TransferNFT() public {
        // Mint an NFT
        vm.startPrank(creator);
        uint256 tokenId = nft.mint(
            creator,
            "ipfs://QmZ1Hg8dXm4nHUsyQXQXe8g5HCPxpXsXF3Kxnfm8NZ6hXH",
            PasifikaNFT.ItemType.Digital,
            defaultRoyaltyPercent,
            ""
        );

        // Transfer to buyer
        nft.safeTransferFrom(creator, buyer, tokenId);
        vm.stopPrank();

        // Verify new owner
        assertEq(nft.ownerOf(tokenId), buyer);
    }

    function test_FailUnauthorizedMint() public {
        vm.startPrank(buyer);

        // Try to mint as non-minter
        vm.expectRevert();
        nft.mint(
            buyer,
            "ipfs://QmZ1Hg8dXm4nHUsyQXQXe8g5HCPxpXsXF3Kxnfm8NZ6hXH",
            PasifikaNFT.ItemType.Digital,
            defaultRoyaltyPercent,
            ""
        );

        vm.stopPrank();
    }

    function test_UpdateBaseURI() public {
        vm.startPrank(admin);

        // Update base URI
        string memory newBaseURI = "https://new.pasifika.io/nft/";
        nft.setBaseURI(newBaseURI);

        vm.stopPrank();

        // Mint an NFT
        vm.startPrank(creator);
        uint256 tokenId = nft.mint(
            creator,
            "ipfs://QmZ1Hg8dXm4nHUsyQXQXe8g5HCPxpXsXF3Kxnfm8NZ6hXH",
            PasifikaNFT.ItemType.Digital,
            defaultRoyaltyPercent,
            ""
        );
        vm.stopPrank();

        // Verify updated token URI
        assertEq(
            nft.tokenURI(tokenId), "https://new.pasifika.io/nft/ipfs://QmZ1Hg8dXm4nHUsyQXQXe8g5HCPxpXsXF3Kxnfm8NZ6hXH"
        );
    }

    function test_AdminSetRoyaltyPercentages() public {
        vm.startPrank(admin);

        // Update default royalty
        uint96 newDefaultRoyalty = 100; // 1% - maximum allowed value
        nft.setDefaultRoyalty(newDefaultRoyalty);
        assertEq(nft.getDefaultRoyalty(), newDefaultRoyalty);

        // Update member royalty
        uint96 newMemberRoyalty = 75; // 0.75%
        nft.setMemberRoyalty(newMemberRoyalty);
        assertEq(nft.getMemberRoyalty(), newMemberRoyalty);

        vm.stopPrank();
    }

    function test_FailNonAdminSetRoyalty() public {
        vm.startPrank(buyer);

        // Try to update default royalty as non-admin
        vm.expectRevert();
        nft.setDefaultRoyalty(150);

        // Try to update member royalty as non-admin
        vm.expectRevert();
        nft.setMemberRoyalty(75);

        vm.stopPrank();
    }

    function test_UpdateMembershipContract() public {
        vm.startPrank(admin);

        // Deploy a new membership contract
        PasifikaMembership newMembership = new PasifikaMembership(payable(address(treasury)));

        // Update the membership contract in NFT
        nft.setMembershipContract(payable(address(newMembership)));

        // Verify the membership contract was updated
        assertEq(address(nft.getMembershipContract()), address(newMembership));

        vm.stopPrank();
    }

    function test_Burn() public {
        // Mint an NFT
        vm.startPrank(creator);
        uint256 tokenId = nft.mint(
            creator,
            "ipfs://QmZ1Hg8dXm4nHUsyQXQXe8g5HCPxpXsXF3Kxnfm8NZ6hXH",
            PasifikaNFT.ItemType.Digital,
            defaultRoyaltyPercent,
            ""
        );

        // Burn the NFT
        nft.burn(tokenId);
        vm.stopPrank();

        // Verify the NFT is burned
        vm.expectRevert();
        nft.ownerOf(tokenId);
    }
}
