// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/DigitalContentNFT.sol";

contract DigitalContentNFTTest is Test {
    DigitalContentNFT public digitalNFT;
    address public admin = address(1);
    address public minter = address(2);
    address public recipient = address(3);
    address public contentManager = address(4);
    address public culturalAuthority = address(5);
    address public user1 = address(6);
    address public user2 = address(7);
    
    function setUp() public {
        // Set a fixed timestamp for testing
        vm.warp(1000000000); // Set block timestamp to a large enough value
        
        // Deploy contract
        console.log("Deploying contract");
        vm.startPrank(admin);
        digitalNFT = new DigitalContentNFT();
        
        // Set up roles
        digitalNFT.grantRole(digitalNFT.MINTER_ROLE(), minter);
        digitalNFT.grantRole(digitalNFT.CONTENT_MANAGER_ROLE(), contentManager);
        digitalNFT.grantRole(digitalNFT.CULTURAL_AUTHORITY_ROLE(), culturalAuthority);
        
        console.log("Contract deployed and roles assigned");
        vm.stopPrank();
    }
    
    function testDeployment() public view {
        // Verify contract deployment
        assert(address(digitalNFT) != address(0));
        
        // Verify role assignments
        assert(digitalNFT.hasRole(digitalNFT.DEFAULT_ADMIN_ROLE(), admin));
        assert(digitalNFT.hasRole(digitalNFT.MINTER_ROLE(), minter));
        assert(digitalNFT.hasRole(digitalNFT.MINTER_ROLE(), admin));
        assert(digitalNFT.hasRole(digitalNFT.CONTENT_MANAGER_ROLE(), contentManager));
        assert(digitalNFT.hasRole(digitalNFT.CONTENT_MANAGER_ROLE(), admin));
        assert(digitalNFT.hasRole(digitalNFT.CULTURAL_AUTHORITY_ROLE(), culturalAuthority));
        assert(digitalNFT.hasRole(digitalNFT.CULTURAL_AUTHORITY_ROLE(), admin));
    }
    
    function testMintDigitalContent() public {
        console.log("Testing basic digital content mint");
        
        // Mint a token as minter
        vm.startPrank(minter);
        uint256 tokenId = digitalNFT.mintDigitalContent(
            recipient,
            "https://example.com/token/1",
            DigitalContentNFT.CulturalSensitivityLevel.PublicDomain,
            DigitalContentNFT.ContentType.Image,
            DigitalContentNFT.LicenseType.Attribution
        );
        vm.stopPrank();
        
        // Verify the token was minted correctly
        assertEq(digitalNFT.ownerOf(tokenId), recipient, "Token owner mismatch");
        
        // Verify token metadata
        (
            DigitalContentNFT.ContentType contentType,
            string memory contentHash,
            bool encrypted,
            uint256 creationTime,
            address creator,
            DigitalContentNFT.CulturalSensitivityLevel sensitivityLevel,
            DigitalContentNFT.LicenseType licenseType,
            string memory culture,
            string memory communityOrigin,
            uint256 usageCount,
            bool commercialRights
        ) = digitalNFT.getTokenMetadata(tokenId);
        
        assertEq(uint256(contentType), uint256(DigitalContentNFT.ContentType.Image), "Content type mismatch");
        assertEq(bytes(contentHash).length, 0, "Content hash should be empty");
        assertEq(encrypted, false, "Encryption flag should be false");
        assertGt(creationTime, 0, "Creation time not set");
        assertEq(creator, minter, "Creator mismatch");
        assertEq(uint256(sensitivityLevel), uint256(DigitalContentNFT.CulturalSensitivityLevel.PublicDomain), "Sensitivity level mismatch");
        assertEq(uint256(licenseType), uint256(DigitalContentNFT.LicenseType.Attribution), "License type mismatch");
        assertEq(usageCount, 0, "Usage count should be 0");
        assertEq(commercialRights, false, "Commercial rights should match license type");
    }
    
    function testMintExtendedDigitalContent() public {
        console.log("Testing extended digital content mint");
        
        // Mint a token with extended data
        vm.startPrank(minter);
        uint256 tokenId = digitalNFT.mintExtendedDigitalContent(
            recipient,
            "https://example.com/token/2",
            DigitalContentNFT.CulturalSensitivityLevel.CommunityRestricted,
            DigitalContentNFT.ContentType.Video,
            "QmHashOfContent",
            true,
            "EncryptionKeyReference",
            DigitalContentNFT.LicenseType.AttributionNonCommercial,
            "Fijian",
            "Suva",
            "Traditional ceremonial video from the community"
        );
        vm.stopPrank();
        
        // Verify the token was minted correctly
        assertEq(digitalNFT.ownerOf(tokenId), recipient, "Token owner mismatch");
        
        // Verify token metadata
        (
            DigitalContentNFT.ContentType contentType,
            string memory contentHash,
            bool encrypted,
            uint256 creationTime,
            address creator,
            DigitalContentNFT.CulturalSensitivityLevel sensitivityLevel,
            DigitalContentNFT.LicenseType licenseType,
            string memory culture,
            string memory communityOrigin,
            uint256 usageCount,
            bool commercialRights
        ) = digitalNFT.getTokenMetadata(tokenId);
        
        assertEq(uint256(contentType), uint256(DigitalContentNFT.ContentType.Video), "Content type mismatch");
        assertEq(contentHash, "QmHashOfContent", "Content hash mismatch");
        assertEq(encrypted, true, "Encryption flag should be true");
        assertGt(creationTime, 0, "Creation time not set");
        assertEq(creator, minter, "Creator mismatch");
        assertEq(uint256(sensitivityLevel), uint256(DigitalContentNFT.CulturalSensitivityLevel.CommunityRestricted), "Sensitivity level mismatch");
        assertEq(uint256(licenseType), uint256(DigitalContentNFT.LicenseType.AttributionNonCommercial), "License type mismatch");
        assertEq(culture, "Fijian", "Culture mismatch");
        assertEq(communityOrigin, "Suva", "Community origin mismatch");
        assertEq(usageCount, 0, "Usage count should be 0");
        assertEq(commercialRights, false, "Commercial rights should match license type");
        
        // Verify cultural context
        (
            string[] memory contexts,
            address[] memory contributors,
            uint256[] memory timestamps
        ) = digitalNFT.getCulturalContexts(tokenId);
        
        assertEq(contexts.length, 1, "Should have one cultural context");
        assertEq(contexts[0], "Traditional ceremonial video from the community", "Context mismatch");
        assertEq(contributors[0], minter, "Contributor mismatch");
        assertGt(timestamps[0], 0, "Timestamp not set");
    }
    
    function testAccessControl() public {
        console.log("Testing access control");
        
        // Mint a token
        vm.prank(minter);
        uint256 tokenId = digitalNFT.mintDigitalContent(
            recipient,
            "https://example.com/token/3",
            DigitalContentNFT.CulturalSensitivityLevel.PublicDomain,
            DigitalContentNFT.ContentType.Document,
            DigitalContentNFT.LicenseType.Attribution
        );
        
        // Verify initial access
        bool recipientAccess = digitalNFT.hasAccess(tokenId, recipient);
        bool minterAccess = digitalNFT.hasAccess(tokenId, minter);
        bool user1Access = digitalNFT.hasAccess(tokenId, user1);
        
        assertTrue(recipientAccess, "Recipient should have access");
        assertTrue(minterAccess, "Minter should have access");
        assertFalse(user1Access, "User1 should not have access");
        
        // Grant access to user1
        vm.prank(recipient);
        digitalNFT.grantAccess(tokenId, user1);
        
        // Verify user1 now has access
        assertTrue(digitalNFT.hasAccess(tokenId, user1), "User1 should now have access");
        
        // Get usage data
        (
            ,
            ,
            address[] memory authorizedUsers
        ) = digitalNFT.getUsageData(tokenId);
        
        // Check if user1 is in authorized users
        bool found = false;
        for (uint i = 0; i < authorizedUsers.length; i++) {
            if (authorizedUsers[i] == user1) {
                found = true;
                break;
            }
        }
        assertTrue(found, "User1 should be in authorized users");
        
        // Revoke access from user1
        vm.prank(recipient);
        digitalNFT.revokeAccess(tokenId, user1);
        
        // Verify user1 no longer has access
        assertFalse(digitalNFT.hasAccess(tokenId, user1), "User1 should no longer have access");
    }
    
    function testRecordUsage() public {
        console.log("Testing usage recording");
        
        // Mint a token
        vm.prank(minter);
        uint256 tokenId = digitalNFT.mintDigitalContent(
            recipient,
            "https://example.com/token/4",
            DigitalContentNFT.CulturalSensitivityLevel.PublicDomain,
            DigitalContentNFT.ContentType.Audio,
            DigitalContentNFT.LicenseType.Attribution
        );
        
        // Record usage by recipient
        vm.prank(recipient);
        digitalNFT.recordUsage(tokenId);
        
        // Grant access to user1
        vm.prank(recipient);
        digitalNFT.grantAccess(tokenId, user1);
        
        // Record usage by user1
        vm.prank(user1);
        digitalNFT.recordUsage(tokenId);
        
        // Verify usage count
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 usageCount,
            
        ) = digitalNFT.getTokenMetadata(tokenId);
        
        (
            ,
            uint256 totalUses,
            
        ) = digitalNFT.getUsageData(tokenId);
        
        assertEq(usageCount, 2, "Usage count should be 2");
        assertEq(totalUses, 2, "Total uses should be 2");
    }
    
    function testAddCulturalContext() public {
        console.log("Testing cultural context addition");
        
        // Mint a token
        vm.prank(minter);
        uint256 tokenId = digitalNFT.mintDigitalContent(
            recipient,
            "https://example.com/token/5",
            DigitalContentNFT.CulturalSensitivityLevel.CeremonialRestricted,
            DigitalContentNFT.ContentType.Image,
            DigitalContentNFT.LicenseType.CommunityApproval
        );
        
        // Add cultural context as cultural authority
        vm.prank(culturalAuthority);
        digitalNFT.addCulturalContext(tokenId, "This image depicts sacred patterns");
        
        // Add cultural context as owner
        vm.prank(recipient);
        digitalNFT.addCulturalContext(tokenId, "Made by artisans in the eastern region");
        
        // Get cultural contexts
        (
            string[] memory contexts,
            address[] memory contributors,
            
        ) = digitalNFT.getCulturalContexts(tokenId);
        
        // Verify contexts
        assertEq(contexts.length, 2, "Should have two cultural contexts");
        assertEq(contexts[0], "This image depicts sacred patterns", "First context mismatch");
        assertEq(contexts[1], "Made by artisans in the eastern region", "Second context mismatch");
        assertEq(contributors[0], culturalAuthority, "First contributor mismatch");
        assertEq(contributors[1], recipient, "Second contributor mismatch");
    }
    
    function testPauseFunctionality() public {
        console.log("Testing pause functionality");
        
        // Pause the contract
        vm.prank(admin);
        digitalNFT.pause();
        
        // Try to mint when paused - should revert
        vm.prank(minter);
        vm.expectRevert(); // Generic expectRevert as the exact error message depends on implementation
        digitalNFT.mintDigitalContent(
            recipient,
            "https://example.com/token/6",
            DigitalContentNFT.CulturalSensitivityLevel.PublicDomain,
            DigitalContentNFT.ContentType.Image,
            DigitalContentNFT.LicenseType.Attribution
        );
        
        // Unpause the contract
        vm.prank(admin);
        digitalNFT.unpause();
        
        // Try to mint after unpausing - should succeed
        vm.prank(minter);
        uint256 tokenId = digitalNFT.mintDigitalContent(
            recipient,
            "https://example.com/token/6",
            DigitalContentNFT.CulturalSensitivityLevel.PublicDomain,
            DigitalContentNFT.ContentType.Image,
            DigitalContentNFT.LicenseType.Attribution
        );
        
        // Verify token was minted
        assertEq(digitalNFT.ownerOf(tokenId), recipient, "Token should be minted after unpausing");
    }
}
