// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "forge-std/console.sol";

/**
 * @title PhysicalItemNFT
 * @dev Implementation of NFTs for physical goods in the PASIFIKA ecosystem
 */
contract PhysicalItemNFT is ERC721URIStorage, AccessControl, Pausable {
    using Strings for uint256;

    // Roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant CULTURAL_AUTHORITY_ROLE = keccak256("CULTURAL_AUTHORITY_ROLE");
    bytes32 public constant SUPPLY_CHAIN_ROLE = keccak256("SUPPLY_CHAIN_ROLE");
    bytes32 public constant QUALITY_VERIFIER_ROLE = keccak256("QUALITY_VERIFIER_ROLE");
    
    // Token ID counter
    uint256 private _nextTokenId;
    
    // Cultural sensitivity levels
    enum CulturalSensitivityLevel {
        PublicDomain,         // Freely shareable
        CommunityRestricted,  // Limited distribution with attribution
        CeremonialRestricted, // Special access controls
        SacredProtected       // Not eligible for commercial marketplace
    }

    // Item types
    enum ItemType {
        PhysicalGood,
        DigitalContent,
        DataResource,
        Service
    }
    
    // Fulfillment status enum
    enum FulfillmentStatus {
        Created,       // Initial state
        InProduction,  // Being produced
        Shipped,       // In transit
        Delivered,     // Received by buyer
        Verified,      // Authenticity verified
        Disputed,      // Issue raised
        Returned       // Sent back to seller
    }
    
    // Main token metadata
    struct TokenMetadata {
        ItemType itemType;
        string contentHash;      // IPFS hash for original content
        string location;         // Physical location (for physical goods)
        uint256 creationTime;    // When token was created
        bool isVerified;         // Whether token has been verified
        address creator;         // Original creator
        CulturalSensitivityLevel sensitivityLevel;
        string culture;
        string communityOrigin;
        string culturalContext;
    }
    
    // Quality metrics structure
    struct QualityMetrics {
        uint256 qualityScore;        // 0-100 score
        string qualityGrade;         // Letter grade (A, B, C, etc.)
        uint256 lastInspectionTime;  // When item was last inspected
        address inspector;           // Who performed the inspection
        string notes;                // Inspector notes
    }
    
    // Supply chain data structure
    struct SupplyChainData {
        FulfillmentStatus status;            // Current fulfillment status
        string currentLocation;              // Current physical location
        uint256 productionDate;              // When production started
        uint256 estimatedDeliveryDate;       // Expected delivery date
        string trackingInfo;                 // Shipping tracking number or other info
    }
    
    // Mappings
    mapping(uint256 => TokenMetadata) private _tokenMetadata;
    mapping(uint256 => QualityMetrics) private _qualityMetrics;
    mapping(uint256 => SupplyChainData) private _supplyChainData;
    mapping(uint256 => string[]) private _locationHistory;
    
    // Events
    event TokenMinted(
        uint256 indexed tokenId,
        address indexed creator,
        ItemType itemType,
        CulturalSensitivityLevel sensitivityLevel
    );
    
    event TokenVerification(
        uint256 indexed tokenId,
        address indexed verifier,
        uint256 timestamp
    );
    
    event LocationUpdated(
        uint256 indexed tokenId,
        string location,
        uint256 timestamp
    );
    
    event QualityUpdated(
        uint256 indexed tokenId,
        uint256 qualityScore,
        string qualityGrade,
        address indexed inspector
    );
    
    event FulfillmentStatusUpdated(
        uint256 indexed tokenId,
        FulfillmentStatus status,
        uint256 timestamp
    );
    
    // Constructor - explicitly calling all parent constructors
    constructor() 
        ERC721("PasifikaPhysicalItem", "PSIPHY") 
        ERC721URIStorage()
    {
        console.log("Constructor start");
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, msg.sender);
        _grantRole(VALIDATOR_ROLE, msg.sender);
        _grantRole(CULTURAL_AUTHORITY_ROLE, msg.sender);
        _grantRole(SUPPLY_CHAIN_ROLE, msg.sender);
        _grantRole(QUALITY_VERIFIER_ROLE, msg.sender);
        
        // Initialize token ID counter to start with 1 (not 0)
        _nextTokenId = 1;
        
        console.log("Constructor end");
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Simplified mint function to isolate overflow issues
     */
    function mintSimple(
        address to,
        string memory uri,
        CulturalSensitivityLevel sensitivityLevel
    ) 
        external
        whenNotPaused
        onlyRole(MINTER_ROLE)
        returns (uint256) 
    {
        console.log("DEBUG: mintSimple - Start");
        console.log("DEBUG: to address", to);
        
        uint256 tokenId = _nextTokenId;
        console.log("DEBUG: tokenId", tokenId);
        
        _nextTokenId = tokenId + 1;
        console.log("DEBUG: _nextTokenId updated to", _nextTokenId);
        
        _safeMint(to, tokenId);
        console.log("DEBUG: After _safeMint");
        
        _setTokenURI(tokenId, uri);
        console.log("DEBUG: After _setTokenURI");
        
        // Emit simplified event
        emit TokenMinted(tokenId, msg.sender, ItemType.PhysicalGood, sensitivityLevel);
        console.log("DEBUG: TokenMinted event emitted");
        
        return tokenId;
    }
    
    /**
     * @dev Mint a physical item with proper structure initialization
     */
    function mintPhysicalItem(
        address to,
        string memory uri,
        CulturalSensitivityLevel sensitivityLevel,
        ItemType itemType,
        string memory contentHash,
        string memory location,
        string memory culture,
        string memory communityOrigin,
        string memory culturalContext,
        uint256 productionDate,
        uint256 estimatedDeliveryDate,
        string memory trackingInfo
    ) 
        external
        whenNotPaused
        onlyRole(MINTER_ROLE)
        returns (uint256) 
    {
        console.log("DEBUG: mintPhysicalItem - Start");
        console.log("DEBUG: to address", to);
        console.log("DEBUG: sensitivityLevel", uint256(sensitivityLevel));
        console.log("DEBUG: itemType", uint256(itemType));
        console.log("DEBUG: location", location);
        console.log("DEBUG: production date", productionDate);
        console.log("DEBUG: estimated delivery date", estimatedDeliveryDate);
        
        // Mint the token
        uint256 tokenId = _nextTokenId;
        console.log("DEBUG: tokenId", tokenId);
        
        _nextTokenId = tokenId + 1;
        console.log("DEBUG: _nextTokenId updated to", _nextTokenId);
        
        console.log("DEBUG: Before _safeMint");
        _safeMint(to, tokenId);
        console.log("DEBUG: After _safeMint");
        
        console.log("DEBUG: Before _setTokenURI");
        _setTokenURI(tokenId, uri);
        console.log("DEBUG: After _setTokenURI");
        
        console.log("DEBUG: Before metadata setup");
        // Initialize token metadata with field-by-field assignment
        TokenMetadata memory metadata;
        console.log("DEBUG: metadata struct created in memory");
        
        console.log("DEBUG: Setting itemType");
        metadata.itemType = itemType;
        console.log("DEBUG: Setting contentHash");
        metadata.contentHash = contentHash;
        console.log("DEBUG: Setting location");
        metadata.location = location;
        console.log("DEBUG: Setting creationTime");
        metadata.creationTime = block.timestamp;
        console.log("DEBUG: Setting isVerified");
        metadata.isVerified = false;
        console.log("DEBUG: Setting creator");
        metadata.creator = msg.sender;
        console.log("DEBUG: Setting sensitivityLevel");
        metadata.sensitivityLevel = sensitivityLevel;
        console.log("DEBUG: Setting culture");
        metadata.culture = culture;
        console.log("DEBUG: Setting communityOrigin");
        metadata.communityOrigin = communityOrigin;
        console.log("DEBUG: Setting culturalContext");
        metadata.culturalContext = culturalContext;
        console.log("DEBUG: metadata fields assigned");
        
        console.log("DEBUG: Storing metadata in mapping");
        _tokenMetadata[tokenId] = metadata;
        console.log("DEBUG: metadata stored in mapping");
        
        // Use minimal initialization for other structures
        // Initialize quality metrics with empty values
        console.log("DEBUG: Initializing quality metrics");
        _qualityMetrics[tokenId] = QualityMetrics(0, "Ungraded", 0, address(0), "");
        console.log("DEBUG: quality metrics initialized");
        
        // Initialize supply chain data with minimal values
        console.log("DEBUG: Initializing supply chain data");
        _supplyChainData[tokenId] = SupplyChainData(
            FulfillmentStatus.Created,
            location,
            productionDate,
            estimatedDeliveryDate,
            trackingInfo
        );
        console.log("DEBUG: supply chain data initialized");
        
        // Initialize location history with the first location
        console.log("DEBUG: Initializing location history");
        string[] storage locationHistory = _locationHistory[tokenId];
        console.log("DEBUG: Got location history array reference");
        locationHistory.push(location);
        console.log("DEBUG: location history initialized with:", location);
        
        console.log("DEBUG: Emitting event");
        emit TokenMinted(tokenId, msg.sender, itemType, sensitivityLevel);
        console.log("DEBUG: Event emitted");
        
        console.log("DEBUG: mintPhysicalItem - End");
        return tokenId;
    }
    
    /**
     * @dev Update the physical location of an item
     */
    function updateLocation(uint256 tokenId, string memory location) 
        external 
        whenNotPaused
        onlyRole(SUPPLY_CHAIN_ROLE)
    {
        require(_exists(tokenId), "Token does not exist");
        
        // Update current location
        _supplyChainData[tokenId].currentLocation = location;
        _tokenMetadata[tokenId].location = location;
        
        // Add to location history
        _locationHistory[tokenId].push(location);
        
        emit LocationUpdated(tokenId, location, block.timestamp);
    }
    
    /**
     * @dev Update quality metrics for an item
     */
    function updateQuality(
        uint256 tokenId, 
        uint256 qualityScore, 
        string memory qualityGrade,
        string memory notes
    ) 
        external 
        whenNotPaused
        onlyRole(QUALITY_VERIFIER_ROLE)
    {
        require(_exists(tokenId), "Token does not exist");
        require(qualityScore <= 100, "Score must be 0-100");
        
        _qualityMetrics[tokenId].qualityScore = qualityScore;
        _qualityMetrics[tokenId].qualityGrade = qualityGrade;
        _qualityMetrics[tokenId].lastInspectionTime = block.timestamp;
        _qualityMetrics[tokenId].inspector = msg.sender;
        _qualityMetrics[tokenId].notes = notes;
        
        emit QualityUpdated(tokenId, qualityScore, qualityGrade, msg.sender);
    }
    
    /**
     * @dev Verify the authenticity of a physical item
     */
    function verifyAuthenticity(uint256 tokenId) 
        external 
        whenNotPaused
        onlyRole(VALIDATOR_ROLE)
    {
        require(_exists(tokenId), "Token does not exist");
        require(!_tokenMetadata[tokenId].isVerified, "Already verified");
        
        // Mark the token as verified
        _tokenMetadata[tokenId].isVerified = true;
        
        emit TokenVerification(tokenId, msg.sender, block.timestamp);
        
        // Update fulfillment status if in a relevant state
        FulfillmentStatus currentStatus = _supplyChainData[tokenId].status;
        if (currentStatus == FulfillmentStatus.Delivered) {
            _supplyChainData[tokenId].status = FulfillmentStatus.Verified;
            emit FulfillmentStatusUpdated(tokenId, FulfillmentStatus.Verified, block.timestamp);
        }
    }
    
    /**
     * @dev Update the fulfillment status of an item
     */
    function updateFulfillmentStatus(uint256 tokenId, FulfillmentStatus status) 
        external 
        whenNotPaused
        onlyRole(SUPPLY_CHAIN_ROLE)
    {
        require(_exists(tokenId), "Token does not exist");
        
        _supplyChainData[tokenId].status = status;
        
        emit FulfillmentStatusUpdated(tokenId, status, block.timestamp);
    }
    
    /**
     * @dev Get token metadata
     */
    function getTokenMetadata(uint256 tokenId) 
        external 
        view 
        returns (
            ItemType itemType,
            string memory contentHash,
            string memory location,
            uint256 creationTime,
            bool isVerified,
            address creator,
            CulturalSensitivityLevel sensitivityLevel,
            string memory culture,
            string memory communityOrigin,
            string memory culturalContext
        ) 
    {
        require(_exists(tokenId), "Token does not exist");
        
        TokenMetadata storage metadata = _tokenMetadata[tokenId];
        return (
            metadata.itemType,
            metadata.contentHash,
            metadata.location,
            metadata.creationTime,
            metadata.isVerified,
            metadata.creator,
            metadata.sensitivityLevel,
            metadata.culture,
            metadata.communityOrigin,
            metadata.culturalContext
        );
    }
    
    /**
     * @dev Get quality metrics
     */
    function getQualityMetrics(uint256 tokenId) 
        external 
        view 
        returns (
            uint256 qualityScore,
            string memory qualityGrade,
            uint256 lastInspectionTime,
            address inspector,
            string memory notes
        ) 
    {
        require(_exists(tokenId), "Token does not exist");
        
        QualityMetrics storage metrics = _qualityMetrics[tokenId];
        return (
            metrics.qualityScore,
            metrics.qualityGrade,
            metrics.lastInspectionTime,
            metrics.inspector,
            metrics.notes
        );
    }
    
    /**
     * @dev Get supply chain data
     */
    function getFulfillmentStatus(uint256 tokenId) 
        external 
        view 
        returns (
            FulfillmentStatus status,
            string memory currentLocation,
            uint256 estimatedDeliveryDate
        ) 
    {
        require(_exists(tokenId), "Token does not exist");
        
        SupplyChainData storage data = _supplyChainData[tokenId];
        return (
            data.status,
            data.currentLocation,
            data.estimatedDeliveryDate
        );
    }
    
    /**
     * @dev Get location history
     */
    function getLocationHistory(uint256 tokenId) 
        external 
        view 
        returns (string[] memory) 
    {
        require(_exists(tokenId), "Token does not exist");
        
        return _locationHistory[tokenId];
    }
    
    /**
     * @dev Check if a token is authenticated
     */
    function isAuthenticated(uint256 tokenId) 
        external 
        view 
        returns (bool) 
    {
        require(_exists(tokenId), "Token does not exist");
        
        return _tokenMetadata[tokenId].isVerified;
    }
    
    /**
     * @dev Check if a token exists
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
    
    /**
     * @dev Override supportsInterface
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
    
    /**
     * @dev Override tokenURI to provide extended functionality
     */
    function tokenURI(uint256 tokenId) 
        public 
        view 
        override(ERC721URIStorage)
        returns (string memory) 
    {
        return super.tokenURI(tokenId);
    }
}
