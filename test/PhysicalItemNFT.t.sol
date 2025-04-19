// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/PhysicalItemNFT.sol";

contract PhysicalItemNFTTest is Test {
    PhysicalItemNFT public physicalNFT;
    address public admin = address(1);
    address public minter = address(2);
    address public recipient = address(3);
    address public supplyChainOperator = address(4);
    address public qualityVerifier = address(5);
    address public validator = address(6);
    
    function setUp() public {
        // Set a fixed timestamp for testing
        vm.warp(1000000000); // Set block timestamp to a large enough value
        
        // Deploy contract
        console.log("Deploying contract");
        vm.startPrank(admin);
        physicalNFT = new PhysicalItemNFT();
        
        // Set up roles
        physicalNFT.grantRole(physicalNFT.MINTER_ROLE(), minter);
        physicalNFT.grantRole(physicalNFT.SUPPLY_CHAIN_ROLE(), supplyChainOperator);
        physicalNFT.grantRole(physicalNFT.QUALITY_VERIFIER_ROLE(), qualityVerifier);
        physicalNFT.grantRole(physicalNFT.VALIDATOR_ROLE(), validator);
        
        console.log("Contract deployed and roles assigned");
        vm.stopPrank();
    }
    
    function testDeployment() public view {
        // Verify contract deployment
        assert(address(physicalNFT) != address(0));
        
        // Verify role assignments
        assert(physicalNFT.hasRole(physicalNFT.DEFAULT_ADMIN_ROLE(), admin));
        assert(physicalNFT.hasRole(physicalNFT.MINTER_ROLE(), minter));
        assert(physicalNFT.hasRole(physicalNFT.MINTER_ROLE(), admin));
        assert(physicalNFT.hasRole(physicalNFT.SUPPLY_CHAIN_ROLE(), supplyChainOperator));
        assert(physicalNFT.hasRole(physicalNFT.QUALITY_VERIFIER_ROLE(), qualityVerifier));
        assert(physicalNFT.hasRole(physicalNFT.VALIDATOR_ROLE(), validator));
    }
    
    function testMintSimple() public {
        console.log("Testing simple mint");
        
        // Mint a token as admin (who has the minter role by default)
        vm.startPrank(admin);
        uint256 tokenId = physicalNFT.mintSimple(
            recipient,
            "https://example.com/token/1",
            PhysicalItemNFT.CulturalSensitivityLevel.PublicDomain
        );
        vm.stopPrank();
        
        // Verify the token was minted correctly
        assertEq(physicalNFT.ownerOf(tokenId), recipient, "Token owner mismatch");
        
        // Test minting as minter
        vm.startPrank(minter);
        uint256 tokenId2 = physicalNFT.mintSimple(
            recipient,
            "https://example.com/token/2",
            PhysicalItemNFT.CulturalSensitivityLevel.PublicDomain
        );
        vm.stopPrank();
        
        // Verify the token was minted correctly
        assertEq(physicalNFT.ownerOf(tokenId2), recipient, "Token owner mismatch");
        assertEq(tokenId2, tokenId + 1, "Token ID sequence error");
    }
    
    function testMintPhysicalItem() public {
        console.log("Testing physical item mint");
        
        // Setup parameters - Use small, fixed values for timestamps to avoid underflow
        address to = recipient;
        string memory uri = "https://example.com/token/3";
        PhysicalItemNFT.CulturalSensitivityLevel sensitivityLevel = PhysicalItemNFT.CulturalSensitivityLevel.PublicDomain;
        PhysicalItemNFT.ItemType itemType = PhysicalItemNFT.ItemType.PhysicalGood;
        string memory contentHash = "QmHashOfContent";
        string memory location = "Fiji Islands";
        string memory culture = "Fijian";
        string memory communityOrigin = "Suva";
        string memory culturalContext = "Traditional handicraft item";
        
        // Use specific timestamps rather than relative calculations
        uint256 productionDate = 1000000000 - 2592000; // current timestamp - 30 days in seconds
        uint256 estimatedDeliveryDate = 1000000000 + 604800; // current timestamp + 7 days in seconds
        
        string memory trackingInfo = "TRACK123456789";
        
        console.log("Parameters initialized");
        console.log("Current block timestamp:", block.timestamp);
        console.log("Production date:", productionDate);
        console.log("Estimated delivery date:", estimatedDeliveryDate);
        
        // Mint the token
        vm.startPrank(minter);
        console.log("Start prank as minter");
        
        // Call the mint function - this should succeed with our fixed implementation
        uint256 tokenId = physicalNFT.mintPhysicalItem(
            to,
            uri,
            sensitivityLevel,
            itemType,
            contentHash,
            location,
            culture,
            communityOrigin,
            culturalContext,
            productionDate,
            estimatedDeliveryDate,
            trackingInfo
        );
        
        console.log("Token minted, ID:", tokenId);
        vm.stopPrank();
        
        // Verify token ownership
        assertEq(physicalNFT.ownerOf(tokenId), to, "Token owner incorrect");
    }
    
    // Helper function to ensure we are using the proper string representation
    function testStringConstructionIssue() public {
        console.log("Testing string construction");
        
        // Test with empty strings
        string memory emptyStr = "";
        bytes memory emptyBytes = bytes(emptyStr);
        assertEq(emptyBytes.length, 0, "Empty string should have 0 length");
        
        // Test with non-empty strings
        string memory testStr = "Test String";
        bytes memory testBytes = bytes(testStr);
        assertEq(testBytes.length, 11, "String should have correct length");
        
        // Test string array
        string[] memory strArray = new string[](2);
        strArray[0] = "First";
        strArray[1] = "Second";
        assertEq(bytes(strArray[0]).length, 5, "First string should have correct length");
        assertEq(bytes(strArray[1]).length, 6, "Second string should have correct length");
        
        console.log("String tests passed");
    }
    
    // Test initializing arrays specifically
    function testLocationArrayInitialization() public {
        console.log("Testing location array initialization");
        
        // Create and add to string array directly
        string[] memory locations = new string[](1);
        locations[0] = "Initial Location";
        
        // Verify array setup
        assertEq(locations.length, 1, "Array should have 1 element");
        assertEq(locations[0], "Initial Location", "First element should match");
        
        console.log("Array initialization test passed");
    }
}
