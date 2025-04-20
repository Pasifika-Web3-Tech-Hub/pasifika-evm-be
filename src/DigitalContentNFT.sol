// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "forge-std/console.sol";

/**
 * @title DigitalContentNFT
 * @dev Implementation of NFTs for digital content in the PASIFIKA ecosystem.
 * Features include access controls, usage rights management, attribution tracking,
 * and cultural context preservation.
 */
contract DigitalContentNFT is ERC721URIStorage, AccessControl, Pausable {
    using Strings for uint256;

    // Roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    bytes32 public constant CONTENT_MANAGER_ROLE = keccak256("CONTENT_MANAGER_ROLE");
    bytes32 public constant CULTURAL_AUTHORITY_ROLE = keccak256("CULTURAL_AUTHORITY_ROLE");
    
    // Token ID counter
    uint256 private _nextTokenId;
    
    // Cultural sensitivity levels
    enum CulturalSensitivityLevel {
        PublicDomain,         // Freely shareable
        CommunityRestricted,  // Limited distribution with attribution
        CeremonialRestricted, // Special access controls
        SacredProtected       // Not eligible for commercial marketplace
    }

    // Content type enum
    enum ContentType {
        Image,
        Video,
        Audio,
        Document,
        Interactive,
        Dataset,
        Other
    }
    
    // License type enum
    enum LicenseType {
        OpenAccess,
        Attribution,
        AttributionNonCommercial,
        AttributionShareAlike,
        AttributionNoDerivatives,
        CommercialLicense,
        CommunityApproval,
        PrivateUse
    }
    
    // Token metadata structure
    struct TokenMetadata {
        ContentType contentType;
        string contentHash;          // IPFS hash to digital content
        bool encrypted;              // Whether the content is encrypted
        string encryptionKey;        // Store a hash or reference to the encryption key
        uint256 creationTime;        // When token was created
        address creator;             // Original creator
        CulturalSensitivityLevel sensitivityLevel;
        LicenseType licenseType;
        string culture;              // Cultural origin
        string communityOrigin;      // Specific community
        uint256 usageCount;          // Track content usage/views
        bool commercialRights;       // Whether commercial use is allowed
    }
    
    // Cultural context data
    struct CulturalContext {
        string[] contexts;           // Array of cultural context descriptions
        address[] contributors;      // Who contributed the context
        uint256[] timestamps;        // When each context was added
    }
    
    // Usage tracking data
    struct UsageData {
        uint256 lastUsed;            // Timestamp of last usage
        uint256 totalUses;           // Number of times used/viewed
        address[] authorizedUsers;   // List of users with access rights
    }
    
    // Mappings
    mapping(uint256 => TokenMetadata) private _tokenMetadata;
    mapping(uint256 => CulturalContext) private _culturalContexts;
    mapping(uint256 => UsageData) private _usageData;
    mapping(address => mapping(uint256 => bool)) private _hasAccess;
    
    // Events
    event TokenMinted(
        uint256 indexed tokenId,
        address indexed creator,
        ContentType contentType,
        CulturalSensitivityLevel sensitivityLevel
    );
    
    event AccessGranted(
        uint256 indexed tokenId,
        address indexed user,
        address indexed grantor,
        uint256 timestamp
    );
    
    event AccessRevoked(
        uint256 indexed tokenId,
        address indexed user,
        address indexed revoker,
        uint256 timestamp
    );
    
    event UsageRecorded(
        uint256 indexed tokenId,
        uint256 timestamp,
        uint256 totalUses
    );
    
    event CulturalContextAdded(
        uint256 indexed tokenId,
        address indexed contributor,
        uint256 timestamp
    );
    
    // Constructor
    constructor() 
        ERC721("PasifikaDigitalContent", "PASDIG") 
        ERC721URIStorage()
    {
        console.log("Constructor start");
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, msg.sender);
        _grantRole(CONTENT_MANAGER_ROLE, msg.sender);
        _grantRole(CULTURAL_AUTHORITY_ROLE, msg.sender);
        
        // Initialize token ID counter to start with 1 (not 0)
        _nextTokenId = 1;
        
        console.log("Constructor end");
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
     * @dev Mint a simple digital content token
     * @param to The address that will own the minted token
     * @param uri The token URI
     * @param sensitivityLevel The cultural sensitivity level
     * @param contentType The type of digital content
     * @param licenseType The license type for this content
     * @return tokenId The ID of the newly minted token
     */
    function mintDigitalContent(
        address to,
        string memory uri,
        CulturalSensitivityLevel sensitivityLevel,
        ContentType contentType,
        LicenseType licenseType
    ) 
        external
        whenNotPaused
        onlyRole(MINTER_ROLE)
        returns (uint256) 
    {
        console.log("DEBUG: mintDigitalContent - Start");
        console.log("DEBUG: to address", to);
        
        uint256 tokenId = _nextTokenId;
        console.log("DEBUG: tokenId", tokenId);
        
        _nextTokenId = tokenId + 1;
        console.log("DEBUG: _nextTokenId updated to", _nextTokenId);
        
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        
        // Initialize token metadata
        TokenMetadata memory metadata;
        metadata.contentType = contentType;
        metadata.contentHash = "";  // Will be set by the content creator later
        metadata.encrypted = false;
        metadata.encryptionKey = "";
        metadata.creationTime = block.timestamp;
        metadata.creator = msg.sender;
        metadata.sensitivityLevel = sensitivityLevel;
        metadata.licenseType = licenseType;
        metadata.usageCount = 0;
        metadata.commercialRights = (licenseType == LicenseType.CommercialLicense || 
                                   licenseType == LicenseType.OpenAccess);
        
        _tokenMetadata[tokenId] = metadata;
        
        // Initialize cultural context
        _culturalContexts[tokenId].contexts = new string[](0);
        _culturalContexts[tokenId].contributors = new address[](0);
        _culturalContexts[tokenId].timestamps = new uint256[](0);
        
        // Initialize usage data
        _usageData[tokenId].lastUsed = block.timestamp;
        _usageData[tokenId].totalUses = 0;
        _usageData[tokenId].authorizedUsers = new address[](0);
        
        // Owner automatically gets access
        _grantAccess(tokenId, to);
        
        // Creator automatically gets access if different from owner
        if (msg.sender != to) {
            _grantAccess(tokenId, msg.sender);
        }
        
        emit TokenMinted(tokenId, msg.sender, contentType, sensitivityLevel);
        
        return tokenId;
    }
    
    /**
     * @dev Mint a full digital content token with extended metadata
     * @param to The address that will own the minted token
     * @param uri The token URI
     * @param sensitivityLevel The cultural sensitivity level
     * @param contentType The type of digital content
     * @param contentHash The IPFS hash of the content
     * @param encrypted Whether the content is encrypted
     * @param encryptionKey Reference to encryption key if applicable
     * @param licenseType The license type for this content
     * @param culture Cultural origin of the content
     * @param communityOrigin Community origin of the content
     * @param initialContext Initial cultural context
     * @return tokenId The ID of the newly minted token
     */
    function mintExtendedDigitalContent(
        address to,
        string memory uri,
        CulturalSensitivityLevel sensitivityLevel,
        ContentType contentType,
        string memory contentHash,
        bool encrypted,
        string memory encryptionKey,
        LicenseType licenseType,
        string memory culture,
        string memory communityOrigin,
        string memory initialContext
    ) 
        external
        whenNotPaused
        onlyRole(MINTER_ROLE)
        returns (uint256) 
    {
        console.log("DEBUG: mintExtendedDigitalContent - Start");
        
        uint256 tokenId = _nextTokenId;
        _nextTokenId = tokenId + 1;
        
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        
        // Initialize token metadata
        TokenMetadata memory metadata;
        metadata.contentType = contentType;
        metadata.contentHash = contentHash;
        metadata.encrypted = encrypted;
        metadata.encryptionKey = encryptionKey;
        metadata.creationTime = block.timestamp;
        metadata.creator = msg.sender;
        metadata.sensitivityLevel = sensitivityLevel;
        metadata.licenseType = licenseType;
        metadata.culture = culture;
        metadata.communityOrigin = communityOrigin;
        metadata.usageCount = 0;
        metadata.commercialRights = (licenseType == LicenseType.CommercialLicense || 
                                   licenseType == LicenseType.OpenAccess);
        
        _tokenMetadata[tokenId] = metadata;
        
        // Initialize cultural context with initial value
        if (bytes(initialContext).length > 0) {
            _addCulturalContext(tokenId, initialContext);
        } else {
            // Initialize empty arrays
            _culturalContexts[tokenId].contexts = new string[](0);
            _culturalContexts[tokenId].contributors = new address[](0);
            _culturalContexts[tokenId].timestamps = new uint256[](0);
        }
        
        // Initialize usage data
        _usageData[tokenId].lastUsed = block.timestamp;
        _usageData[tokenId].totalUses = 0;
        _usageData[tokenId].authorizedUsers = new address[](0);
        
        // Owner automatically gets access
        _grantAccess(tokenId, to);
        
        // Creator automatically gets access if different from owner
        if (msg.sender != to) {
            _grantAccess(tokenId, msg.sender);
        }
        
        emit TokenMinted(tokenId, msg.sender, contentType, sensitivityLevel);
        
        return tokenId;
    }
    
    /**
     * @dev Grant content access to a user
     * @param tokenId The token ID to grant access to
     * @param user The address to grant access to
     */
    function grantAccess(uint256 tokenId, address user) 
        external 
        whenNotPaused 
    {
        require(_exists(tokenId), "Token does not exist");
        require(
            _isApprovedOrOwner(msg.sender, tokenId) || 
            hasRole(CONTENT_MANAGER_ROLE, msg.sender),
            "Caller is not owner, approved, or content manager"
        );
        
        _grantAccess(tokenId, user);
    }
    
    /**
     * @dev Internal method to grant access
     */
    function _grantAccess(uint256 tokenId, address user) internal {
        require(user != address(0), "Cannot grant access to zero address");
        
        _hasAccess[user][tokenId] = true;
        
        // Add to authorized users array if not already there
        bool found = false;
        for (uint i = 0; i < _usageData[tokenId].authorizedUsers.length; i++) {
            if (_usageData[tokenId].authorizedUsers[i] == user) {
                found = true;
                break;
            }
        }
        
        if (!found) {
            _usageData[tokenId].authorizedUsers.push(user);
        }
        
        emit AccessGranted(tokenId, user, msg.sender, block.timestamp);
    }
    
    /**
     * @dev Revoke content access from a user
     * @param tokenId The token ID to revoke access from
     * @param user The address to revoke access from
     */
    function revokeAccess(uint256 tokenId, address user) 
        external 
        whenNotPaused 
    {
        require(_exists(tokenId), "Token does not exist");
        require(
            _isApprovedOrOwner(msg.sender, tokenId) || 
            hasRole(CONTENT_MANAGER_ROLE, msg.sender),
            "Caller is not owner, approved, or content manager"
        );
        require(user != ownerOf(tokenId), "Cannot revoke access from token owner");
        
        _hasAccess[user][tokenId] = false;
        
        // Remove from authorized users array
        for (uint i = 0; i < _usageData[tokenId].authorizedUsers.length; i++) {
            if (_usageData[tokenId].authorizedUsers[i] == user) {
                // Replace with the last element and then pop
                _usageData[tokenId].authorizedUsers[i] = _usageData[tokenId].authorizedUsers[_usageData[tokenId].authorizedUsers.length - 1];
                _usageData[tokenId].authorizedUsers.pop();
                break;
            }
        }
        
        emit AccessRevoked(tokenId, user, msg.sender, block.timestamp);
    }
    
    /**
     * @dev Record usage of a token
     * @param tokenId The token ID to record usage for
     */
    function recordUsage(uint256 tokenId) 
        external 
        whenNotPaused 
    {
        require(_exists(tokenId), "Token does not exist");
        require(
            _hasAccess[msg.sender][tokenId] || 
            _isApprovedOrOwner(msg.sender, tokenId),
            "No access rights"
        );
        
        _usageData[tokenId].lastUsed = block.timestamp;
        _usageData[tokenId].totalUses++;
        _tokenMetadata[tokenId].usageCount++;
        
        emit UsageRecorded(tokenId, block.timestamp, _usageData[tokenId].totalUses);
    }
    
    /**
     * @dev Add cultural context to a token
     * @param tokenId The token ID to add context to
     * @param context The cultural context to add
     */
    function addCulturalContext(uint256 tokenId, string memory context) 
        external 
        whenNotPaused 
    {
        require(_exists(tokenId), "Token does not exist");
        require(
            hasRole(CULTURAL_AUTHORITY_ROLE, msg.sender) || 
            _isApprovedOrOwner(msg.sender, tokenId),
            "Not authorized to add cultural context"
        );
        
        _addCulturalContext(tokenId, context);
    }
    
    /**
     * @dev Internal method to add cultural context
     */
    function _addCulturalContext(uint256 tokenId, string memory context) internal {
        _culturalContexts[tokenId].contexts.push(context);
        _culturalContexts[tokenId].contributors.push(msg.sender);
        _culturalContexts[tokenId].timestamps.push(block.timestamp);
        
        emit CulturalContextAdded(tokenId, msg.sender, block.timestamp);
    }
    
    /**
     * @dev Check if a user has access to a token
     * @param tokenId The token ID to check access for
     * @param user The address to check access for
     * @return Whether the user has access
     */
    function hasAccess(uint256 tokenId, address user) 
        external 
        view 
        returns (bool) 
    {
        require(_exists(tokenId), "Token does not exist");
        
        // Token owner and approved addresses always have access
        if (_isApprovedOrOwner(user, tokenId)) {
            return true;
        }
        
        return _hasAccess[user][tokenId];
    }
    
    /**
     * @dev Get token metadata
     * @param tokenId The token ID to get metadata for
     */
    function getTokenMetadata(uint256 tokenId) 
        external 
        view 
        returns (
            ContentType contentType,
            string memory contentHash,
            bool encrypted,
            uint256 creationTime,
            address creator,
            CulturalSensitivityLevel sensitivityLevel,
            LicenseType licenseType,
            string memory culture,
            string memory communityOrigin,
            uint256 usageCount,
            bool commercialRights
        ) 
    {
        require(_exists(tokenId), "Token does not exist");
        
        TokenMetadata storage metadata = _tokenMetadata[tokenId];
        return (
            metadata.contentType,
            metadata.contentHash,
            metadata.encrypted,
            metadata.creationTime,
            metadata.creator,
            metadata.sensitivityLevel,
            metadata.licenseType,
            metadata.culture,
            metadata.communityOrigin,
            metadata.usageCount,
            metadata.commercialRights
        );
    }
    
    /**
     * @dev Get cultural contexts for a token
     * @param tokenId The token ID to get contexts for
     */
    function getCulturalContexts(uint256 tokenId) 
        external 
        view 
        returns (
            string[] memory contexts,
            address[] memory contributors,
            uint256[] memory timestamps
        ) 
    {
        require(_exists(tokenId), "Token does not exist");
        
        return (
            _culturalContexts[tokenId].contexts,
            _culturalContexts[tokenId].contributors,
            _culturalContexts[tokenId].timestamps
        );
    }
    
    /**
     * @dev Get usage data for a token
     * @param tokenId The token ID to get usage data for
     */
    function getUsageData(uint256 tokenId) 
        external 
        view 
        returns (
            uint256 lastUsed,
            uint256 totalUses,
            address[] memory authorizedUsers
        ) 
    {
        require(_exists(tokenId), "Token does not exist");
        
        return (
            _usageData[tokenId].lastUsed,
            _usageData[tokenId].totalUses,
            _usageData[tokenId].authorizedUsers
        );
    }
    
    /**
     * @dev Check if a token exists
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
    
    /**
     * @dev Check if an address is approved or owner of a token
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = ownerOf(tokenId);
        return (spender == owner || isApprovedForAll(owner, spender) || getApproved(tokenId) == spender);
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
