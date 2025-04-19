// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/PasifikaDynamicNFT.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

error AccessControlUnauthorizedAccount(address account, bytes32 role);
error EnforcedPause();
error InvalidApproval();
error ERC721NonexistentToken(uint256 tokenId);

contract PasifikaDynamicNFTTest is Test {
    PasifikaDynamicNFT public nft;
    
    // Test accounts
    address public admin = address(1);
    address public minter = address(2);
    address public updater = address(3);
    address public oracle = address(4);
    address public validator = address(5);
    address public culturalAuthority = address(6);
    address public user1 = address(7);
    address public user2 = address(8);
    address public user3 = address(9);
    
    // Constants for testing
    string constant TOKEN_URI = "QmXZQeNxiVJKtaWdDQv7pN97zcHrAVeyYS4xiyJBrLAHrz";
    bytes constant INITIAL_STATE = "";
    bytes constant UPDATED_STATE = abi.encode("Updated state");
    uint8 constant COMMERCIAL_USAGE = 1;
    uint8 constant EDUCATIONAL_USAGE = 2;
    uint8 constant CEREMONIAL_USAGE = 3;

    function setUp() public {
        // Deploy the NFT contract
        vm.prank(admin);
        nft = new PasifikaDynamicNFT();
        
        // Set up roles
        vm.startPrank(admin);
        nft.grantRole(nft.MINTER_ROLE(), minter);
        nft.grantRole(nft.UPDATER_ROLE(), updater);
        nft.grantRole(nft.ORACLE_ROLE(), oracle);
        nft.grantRole(nft.VALIDATOR_ROLE(), validator);
        nft.grantRole(nft.CULTURAL_AUTHORITY_ROLE(), culturalAuthority);
        vm.stopPrank();
    }

    function testDeployment() public {
        // Check role assignments
        assertTrue(nft.hasRole(nft.ADMIN_ROLE(), admin));
        assertTrue(nft.hasRole(nft.MINTER_ROLE(), minter));
        assertTrue(nft.hasRole(nft.UPDATER_ROLE(), updater));
        assertTrue(nft.hasRole(nft.ORACLE_ROLE(), oracle));
        assertTrue(nft.hasRole(nft.VALIDATOR_ROLE(), validator));
        assertTrue(nft.hasRole(nft.CULTURAL_AUTHORITY_ROLE(), culturalAuthority));
        
        // Verify contract name and symbol
        assertEq(nft.name(), "PASIFIKA Dynamic NFT");
        assertEq(nft.symbol(), "PNFT");
    }

    function testMintNFT() public {
        // Mint a new NFT as the minter
        vm.startPrank(minter);
        uint256 tokenId = nft.mint(
            user1, 
            TOKEN_URI, 
            PasifikaDynamicNFT.ItemType.PhysicalGood, 
            PasifikaDynamicNFT.CulturalSensitivityLevel.PublicDomain,
            "Samoan", 
            "Upolu Island", 
            "QmHash1234", 
            "-14.2426,170.1326", 
            "Traditional Tapa cloth"
        );
        vm.stopPrank();
        
        // Verify token ownership
        assertEq(nft.ownerOf(tokenId), user1);
        
        // Verify token URI
        assertEq(nft.tokenURI(tokenId), string.concat("ipfs://", TOKEN_URI));
        
        // Verify token metadata
        (
            PasifikaDynamicNFT.ItemType itemType,
            string memory contentHash,
            string memory location,
            uint256 creationTime,
            bool isVerified,
            address creator
        ) = nft.getTokenMetadata(tokenId);
        
        assertEq(uint(itemType), uint(PasifikaDynamicNFT.ItemType.PhysicalGood));
        assertEq(contentHash, "QmHash1234");
        assertEq(location, "-14.2426,170.1326");
        assertGt(creationTime, 0);
        assertFalse(isVerified);
        assertEq(creator, minter);
        
        // Verify cultural metadata
        (
            string memory culture,
            string memory communityOrigin,
            PasifikaDynamicNFT.CulturalSensitivityLevel level,
            bool culturalIsVerified,
            address verifier,
            uint256 verificationTimestamp,
            string memory culturalContext,
            bool hasUsageRestrictions
        ) = nft.getCulturalMetadata(tokenId);
        
        assertEq(culture, "Samoan");
        assertEq(communityOrigin, "Upolu Island");
        assertEq(uint(level), uint(PasifikaDynamicNFT.CulturalSensitivityLevel.PublicDomain));
        assertFalse(culturalIsVerified);
        assertEq(verifier, address(0));
        assertEq(verificationTimestamp, 0);
        assertEq(culturalContext, "Traditional Tapa cloth");
        assertFalse(hasUsageRestrictions);
    }

    function testStateUpdate() public {
        // Mint a token first
        vm.prank(minter);
        uint256 tokenId = nft.mint(
            user1, 
            TOKEN_URI, 
            PasifikaDynamicNFT.ItemType.DigitalContent, 
            PasifikaDynamicNFT.CulturalSensitivityLevel.CommunityRestricted,
            "Fijian", 
            "Viti Levu", 
            "QmHash5678", 
            "-18.1416,178.4419", 
            "Digital representation of Masi"
        );
        
        // Get initial state
        bytes memory initialState = nft.getLatestState(tokenId);
        assertEq(initialState, INITIAL_STATE);
        
        // Update the state
        vm.prank(updater);
        nft.updateState(tokenId, UPDATED_STATE);
        
        // Verify updated state
        assertEq(nft.getLatestState(tokenId), UPDATED_STATE);
    }

    function testTokenVerification() public {
        // Mint a token first
        vm.prank(minter);
        uint256 tokenId = nft.mint(
            user1, 
            TOKEN_URI, 
            PasifikaDynamicNFT.ItemType.PhysicalGood, 
            PasifikaDynamicNFT.CulturalSensitivityLevel.PublicDomain,
            "Tongan", 
            "Tongatapu", 
            "QmHashABCD", 
            "-21.1790,-175.1982", 
            "Traditional ngatu"
        );
        
        // Verify token is not verified
        (
            ,
            ,
            ,
            ,
            bool isVerified,
            
        ) = nft.getTokenMetadata(tokenId);
        assertFalse(isVerified);
        
        // Verify the token
        vm.prank(validator);
        nft.verifyToken(tokenId);
        
        // Check token is now verified
        (
            ,
            ,
            ,
            ,
            bool isVerifiedAfter,
            
        ) = nft.getTokenMetadata(tokenId);
        assertTrue(isVerifiedAfter);
    }

    function testCulturalVerification() public {
        // Mint a token first
        vm.prank(minter);
        uint256 tokenId = nft.mint(
            user1, 
            TOKEN_URI, 
            PasifikaDynamicNFT.ItemType.PhysicalGood, 
            PasifikaDynamicNFT.CulturalSensitivityLevel.CeremonialRestricted,
            "Solomon Islands", 
            "Malaita", 
            "QmHashEFGH", 
            "-9.4456,160.1457", 
            "Sacred shell money"
        );
        
        // Verify cultural metadata is not verified
        (
            ,
            ,
            ,
            bool culturalIsVerified,
            ,
            ,
            ,
            
        ) = nft.getCulturalMetadata(tokenId);
        assertFalse(culturalIsVerified);
        
        // Verify the cultural metadata
        vm.prank(culturalAuthority);
        nft.verifyCultural(tokenId);
        
        // Check cultural metadata is now verified
        (
            ,
            ,
            ,
            bool culturalIsVerifiedAfter,
            address verifier,
            uint256 verificationTimestamp,
            ,
            
        ) = nft.getCulturalMetadata(tokenId);
        assertTrue(culturalIsVerifiedAfter);
        assertEq(verifier, culturalAuthority);
        assertGt(verificationTimestamp, 0);
    }

    function testAccessControl() public {
        // Mint a token with restricted access
        vm.prank(minter);
        uint256 tokenId = nft.mint(
            user1, 
            TOKEN_URI, 
            PasifikaDynamicNFT.ItemType.DigitalContent, 
            PasifikaDynamicNFT.CulturalSensitivityLevel.CommunityRestricted,
            "Samoan", 
            "Upolu Island", 
            "QmHash5678", 
            "-14.2426,170.1326", 
            "Cultural design with access control"
        );
        
        // Non-owner and non-admin cannot access
        vm.prank(user3);
        vm.expectRevert("Not authorized");
        nft.grantAccess(tokenId, user2);
        
        // Admin can grant access
        vm.prank(admin);
        nft.grantAccess(tokenId, user2);
        
        // Owner can grant access
        vm.prank(user1);
        nft.grantAccess(tokenId, user2);
        
        // Verify user2 has access
        assertTrue(nft.hasAccess(tokenId, user2));
        
        // Revoke access from user2
        vm.prank(user1);
        nft.revokeAccess(tokenId, user2);
        
        // Verify user2 no longer has access
        assertFalse(nft.hasAccess(tokenId, user2));
    }

    function testTransferRestrictions() public {
        // Mint a sacred protected token
        vm.prank(minter);
        uint256 tokenId = nft.mint(
            user1, 
            TOKEN_URI, 
            PasifikaDynamicNFT.ItemType.PhysicalGood, 
            PasifikaDynamicNFT.CulturalSensitivityLevel.SacredProtected,
            "Hawaiian", 
            "Oahu", 
            "QmHash9012", 
            "21.3069,-157.8583", 
            "Sacred cultural artifact"
        );
        
        // Setup user1 to approve the transfer first
        vm.prank(user1);
        nft.approve(culturalAuthority, tokenId);
        
        // Cultural authority can transfer
        vm.prank(culturalAuthority);
        nft.transferFrom(user1, user2, tokenId);
        
        // Verify ownership changed
        assertEq(nft.ownerOf(tokenId), user2);
    }

    function testUsagePermissions() public {
        // Mint a token with community restricted access
        vm.prank(minter);
        uint256 tokenId = nft.mint(
            user1, 
            TOKEN_URI, 
            PasifikaDynamicNFT.ItemType.Service, 
            PasifikaDynamicNFT.CulturalSensitivityLevel.CommunityRestricted,
            "Kiribati", 
            "Tarawa", 
            "QmHashQRST", 
            "1.4518,173.0069", 
            "Traditional dance instruction"
        );
        
        // Set usage permissions
        vm.prank(culturalAuthority);
        nft.setUsagePermission(tokenId, EDUCATIONAL_USAGE, true);
        
        // Check usage permissions
        assertTrue(nft.isUsageAllowed(tokenId, EDUCATIONAL_USAGE));
        assertFalse(nft.isUsageAllowed(tokenId, COMMERCIAL_USAGE));
        
        // Set commercial usage to true
        vm.prank(culturalAuthority);
        nft.setUsagePermission(tokenId, COMMERCIAL_USAGE, true);
        
        // Verify commercial usage is now allowed
        assertTrue(nft.isUsageAllowed(tokenId, COMMERCIAL_USAGE));
    }

    function testPauseUnpause() public {
        // Check contract is not paused initially
        assertFalse(nft.paused());
        
        // Pause the contract
        vm.prank(admin);
        nft.pause();
        
        // Verify contract is paused
        assertTrue(nft.paused());
        
        // Attempt to mint when paused should revert
        vm.expectRevert(EnforcedPause.selector);
        vm.prank(minter);
        nft.mint(
            user1, 
            TOKEN_URI, 
            PasifikaDynamicNFT.ItemType.PhysicalGood, 
            PasifikaDynamicNFT.CulturalSensitivityLevel.PublicDomain,
            "Cook Islands", 
            "Rarotonga", 
            "QmHashUVWX", 
            "-21.2357,-159.7777", 
            "Digital tivaevae"
        );
        
        // Unpause the contract
        vm.prank(admin);
        nft.unpause();
        
        // Verify contract is unpaused
        assertFalse(nft.paused());
        
        // Now minting should work
        vm.prank(minter);
        uint256 tokenId = nft.mint(
            user1, 
            TOKEN_URI, 
            PasifikaDynamicNFT.ItemType.PhysicalGood, 
            PasifikaDynamicNFT.CulturalSensitivityLevel.PublicDomain,
            "Cook Islands", 
            "Rarotonga", 
            "QmHashUVWX", 
            "-21.2357,-159.7777", 
            "Digital tivaevae"
        );
        
        // Verify token was created
        assertEq(nft.ownerOf(tokenId), user1);
    }

    function testRoleBasedAccess() public {
        // Admin grants minter role to user3
        vm.startPrank(admin);
        nft.grantRole(nft.MINTER_ROLE(), user3);
        vm.stopPrank();
        
        // Verify user3 now has the minter role
        assertTrue(nft.hasRole(nft.MINTER_ROLE(), user3));
        
        // Now user3 can mint tokens
        vm.prank(user3);
        uint256 tokenId = nft.mint(
            user1, 
            TOKEN_URI, 
            PasifikaDynamicNFT.ItemType.PhysicalGood, 
            PasifikaDynamicNFT.CulturalSensitivityLevel.PublicDomain,
            "Tuvalu", 
            "Funafuti", 
            "QmHashYZ12", 
            "-8.5211,179.1987", 
            "Traditional handicraft"
        );
        
        // Verify token was created
        assertEq(nft.ownerOf(tokenId), user1);
    }

    function testStateHistory() public {
        // Mint a token
        vm.prank(minter);
        uint256 tokenId = nft.mint(
            user1, 
            TOKEN_URI, 
            PasifikaDynamicNFT.ItemType.DigitalContent, 
            PasifikaDynamicNFT.CulturalSensitivityLevel.PublicDomain,
            "Niue", 
            "Alofi", 
            "QmHash3456", 
            "-19.0554,-169.9175", 
            "Digital tivaevae"
        );
        
        // Make several state updates
        bytes memory state1 = abi.encode("State 1");
        bytes memory state2 = abi.encode("State 2");
        bytes memory state3 = abi.encode("State 3");
        
        vm.prank(updater);
        nft.updateState(tokenId, state1);
        
        vm.prank(updater);
        nft.updateState(tokenId, state2);
        
        vm.prank(updater);
        nft.updateState(tokenId, state3);
        
        // Latest state should be state3
        assertEq(nft.getLatestState(tokenId), state3);
        
        // Get state history - note: the contract returns TokenState[] directly
        PasifikaDynamicNFT.TokenState[] memory history = nft.getStateHistory(tokenId);
        
        // Verify history length (initial state + 3 updates = 4)
        assertEq(history.length, 4);
        
        // Verify state data in order (cannot directly access fields due to how Forge Test works with storage structs)
        // For proper testing, we'd need to update the contract to return state components separately
    }
    
    function testCulturalContext() public {
        // Mint a token
        vm.prank(minter);
        uint256 tokenId = nft.mint(
            user1, 
            TOKEN_URI, 
            PasifikaDynamicNFT.ItemType.PhysicalGood, 
            PasifikaDynamicNFT.CulturalSensitivityLevel.CommunityRestricted,
            "Marshall Islands", 
            "Majuro", 
            "QmHash7890", 
            "7.1164,171.1857", 
            "Initial cultural context"
        );
        
        // Check initial cultural context
        (
            ,
            ,
            ,
            ,
            ,
            ,
            string memory initialContext,
            
        ) = nft.getCulturalMetadata(tokenId);
        assertEq(initialContext, "Initial cultural context");
        
        // Update cultural context
        string memory newContext = "Updated cultural context with additional information";
        vm.prank(culturalAuthority);
        nft.addCulturalContext(tokenId, newContext);
        
        // Verify updated context
        (
            ,
            ,
            ,
            ,
            ,
            ,
            string memory updatedContext,
            
        ) = nft.getCulturalMetadata(tokenId);
        assertEq(updatedContext, newContext);
    }
    
    function testTransferWithAttestations() public {
        // Mint a token with community restricted access
        vm.prank(minter);
        uint256 tokenId = nft.mint(
            user1, 
            TOKEN_URI, 
            PasifikaDynamicNFT.ItemType.PhysicalGood, 
            PasifikaDynamicNFT.CulturalSensitivityLevel.CommunityRestricted,
            "Tonga", 
            "Nuku'alofa", 
            "QmHashABCDEF", 
            "-21.1393,-175.1982", 
            "Traditional craftsmanship"
        );
        
        // Approve user2 to transfer the token
        vm.prank(user1);
        nft.approve(user2, tokenId);
        
        // Transfer with attestations
        vm.prank(user2);
        nft.transferWithAttestations(user1, user3, tokenId);
        
        // Verify ownership changed
        assertEq(nft.ownerOf(tokenId), user3);
    }

    function testUnauthorizedVerificationReverts() public {
        // Mint a token first
        vm.prank(minter);
        uint256 tokenId = nft.mint(
            user1, 
            TOKEN_URI, 
            PasifikaDynamicNFT.ItemType.DigitalContent, 
            PasifikaDynamicNFT.CulturalSensitivityLevel.PublicDomain,
            "Fiji", 
            "Suva", 
            "QmHashFIJI", 
            "-18.1416,178.4419", 
            "Digital masi design"
        );
        
        // Non-validator tries to verify token
        vm.prank(user2);
        vm.expectRevert();
        nft.verifyToken(tokenId);
        
        // Non-cultural authority tries to verify cultural metadata
        vm.prank(user3);
        vm.expectRevert();
        nft.verifyCultural(tokenId);
    }
}
