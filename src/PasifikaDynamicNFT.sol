// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title PasifikaDynamicNFT
 * @dev Implementation of dynamic NFTs for PASIFIKA ecosystem
 * Supports state changes, cultural metadata, and verification
 */
contract PasifikaDynamicNFT is ERC721URIStorage, AccessControl, Pausable {
    using Strings for uint256;

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant CULTURAL_AUTHORITY_ROLE = keccak256("CULTURAL_AUTHORITY_ROLE");

    // Counter for token IDs (native uint256 counter instead of Counters library)
    uint256 private _nextTokenId = 1;

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

    // State structures
    struct TokenState {
        bytes data;           // Current state data
        uint256 timestamp;    // When state was last updated
        address updater;      // Who updated the state
    }

    struct CulturalMetadata {
        string culture;                     // e.g., "Samoa", "Fiji", "Tonga"
        string communityOrigin;             // Specific community within culture
        CulturalSensitivityLevel level;     // Sensitivity classification
        bool isVerified;                    // Verified by cultural authority
        address verifier;                   // Who verified it
        uint256 verificationTimestamp;      // When it was verified
        string culturalContext;             // Additional cultural information
        bool hasUsageRestrictions;          // Whether there are restrictions
        mapping(uint8 => bool) allowedUsages; // Specific allowed usages
    }

    // Main token metadata
    struct TokenMetadata {
        ItemType itemType;
        string contentHash;      // IPFS hash for original content
        string location;         // Physical location (for physical goods)
        uint256 creationTime;    // When token was created
        bool isVerified;         // Whether token has been verified
        address creator;         // Original creator
    }

    // Mappings
    mapping(uint256 => TokenState[]) private _tokenStateHistory; // State history for each token
    mapping(uint256 => TokenMetadata) private _tokenMetadata;
    mapping(uint256 => mapping(address => bool)) private _tokenAccess; // Access permissions
    mapping(uint256 => CulturalMetadata) private _culturalMetadata;
    
    // Events
    event TokenMinted(
        uint256 indexed tokenId,
        address indexed creator,
        ItemType itemType,
        CulturalSensitivityLevel sensitivityLevel
    );
    
    event StateUpdated(
        uint256 indexed tokenId,
        bytes newState,
        uint256 timestamp,
        address updater
    );
    
    event CulturalVerification(
        uint256 indexed tokenId,
        address indexed verifier,
        uint256 timestamp
    );
    
    event TokenVerification(
        uint256 indexed tokenId,
        address indexed verifier,
        uint256 timestamp
    );
    
    event AccessGranted(
        uint256 indexed tokenId,
        address indexed user
    );
    
    event AccessRevoked(
        uint256 indexed tokenId,
        address indexed user
    );
    
    event CulturalContextAdded(
        uint256 indexed tokenId,
        string context
    );

    // Constructor
    constructor() ERC721("PASIFIKA Dynamic NFT", "PNFT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, msg.sender);
    }

    /**
     * @dev Pause the contract
     * Only callable by admin
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause the contract
     * Only callable by admin
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Create a new dynamic NFT
     * @param to The recipient of the new token
     * @param uri Initial token URI with metadata
     * @param itemType Type of item the NFT represents
     * @param sensitivityLevel The cultural sensitivity level
     * @param culture The cultural origin of the item
     * @param communityOrigin Specific community within the culture
     * @param contentHash IPFS hash for original content
     * @param location Physical location (for physical items)
     * @param culturalContext Additional cultural information
     * @return tokenId The ID of the newly minted token
     */
    function mint(
        address to,
        string memory uri,
        ItemType itemType,
        CulturalSensitivityLevel sensitivityLevel,
        string memory culture,
        string memory communityOrigin,
        string memory contentHash,
        string memory location,
        string memory culturalContext
    ) 
        external
        whenNotPaused
        onlyRole(MINTER_ROLE)
        returns (uint256)
    {
        uint256 tokenId = _nextTokenId;
        _nextTokenId++;
        
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        
        // Initialize token metadata
        _tokenMetadata[tokenId] = TokenMetadata({
            itemType: itemType,
            contentHash: contentHash,
            location: location,
            creationTime: block.timestamp,
            isVerified: false,
            creator: msg.sender
        });
        
        // Initialize cultural metadata
        _culturalMetadata[tokenId].culture = culture;
        _culturalMetadata[tokenId].communityOrigin = communityOrigin;
        _culturalMetadata[tokenId].level = sensitivityLevel;
        _culturalMetadata[tokenId].isVerified = false;
        _culturalMetadata[tokenId].culturalContext = culturalContext;
        _culturalMetadata[tokenId].hasUsageRestrictions = sensitivityLevel != CulturalSensitivityLevel.PublicDomain;
        
        // Initialize state with empty data
        _tokenStateHistory[tokenId].push(TokenState({
            data: bytes(""),
            timestamp: block.timestamp,
            updater: msg.sender
        }));
        
        emit TokenMinted(tokenId, msg.sender, itemType, sensitivityLevel);
        
        return tokenId;
    }

    /**
     * @dev Update the state of an NFT
     * @param tokenId The token to update
     * @param newState New state data
     */
    function updateState(uint256 tokenId, bytes memory newState) 
        external 
        whenNotPaused
        onlyRole(UPDATER_ROLE)
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        _tokenStateHistory[tokenId].push(TokenState({
            data: newState,
            timestamp: block.timestamp,
            updater: msg.sender
        }));
        
        emit StateUpdated(tokenId, newState, block.timestamp, msg.sender);
    }

    /**
     * @dev Verify the cultural attributes of an NFT
     * @param tokenId The token to verify
     */
    function verifyCultural(uint256 tokenId) 
        external 
        whenNotPaused
        onlyRole(CULTURAL_AUTHORITY_ROLE) 
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        require(!_culturalMetadata[tokenId].isVerified, "Already verified");
        
        _culturalMetadata[tokenId].isVerified = true;
        _culturalMetadata[tokenId].verifier = msg.sender;
        _culturalMetadata[tokenId].verificationTimestamp = block.timestamp;
        
        emit CulturalVerification(tokenId, msg.sender, block.timestamp);
    }

    /**
     * @dev Verify the authenticity of an NFT
     * @param tokenId The token to verify
     */
    function verifyToken(uint256 tokenId) 
        external 
        whenNotPaused
        onlyRole(VALIDATOR_ROLE) 
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        require(!_tokenMetadata[tokenId].isVerified, "Already verified");
        
        _tokenMetadata[tokenId].isVerified = true;
        
        emit TokenVerification(tokenId, msg.sender, block.timestamp);
    }

    /**
     * @dev Grant access to a token for a specific user
     * @param tokenId The token to grant access to
     * @param user The user to grant access
     */
    function grantAccess(uint256 tokenId, address user) 
        external 
        whenNotPaused
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        require(
            ownerOf(tokenId) == msg.sender || 
            hasRole(ADMIN_ROLE, msg.sender) || 
            hasRole(CULTURAL_AUTHORITY_ROLE, msg.sender),
            "Not authorized"
        );
        
        _tokenAccess[tokenId][user] = true;
        
        emit AccessGranted(tokenId, user);
    }

    /**
     * @dev Revoke access to a token for a specific user
     * @param tokenId The token to revoke access from
     * @param user The user to revoke access from
     */
    function revokeAccess(uint256 tokenId, address user) 
        external 
        whenNotPaused
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        require(
            ownerOf(tokenId) == msg.sender || 
            hasRole(ADMIN_ROLE, msg.sender) || 
            hasRole(CULTURAL_AUTHORITY_ROLE, msg.sender),
            "Not authorized"
        );
        
        _tokenAccess[tokenId][user] = false;
        
        emit AccessRevoked(tokenId, user);
    }

    /**
     * @dev Add cultural context to a token
     * @param tokenId The token to add context to
     * @param context The cultural context to add
     */
    function addCulturalContext(uint256 tokenId, string memory context) 
        external 
        whenNotPaused
        onlyRole(CULTURAL_AUTHORITY_ROLE)
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        _culturalMetadata[tokenId].culturalContext = context;
        
        emit CulturalContextAdded(tokenId, context);
    }

    /**
     * @dev Set allowed usage permissions for a token
     * @param tokenId The token to set permissions for
     * @param usageType The type of usage (use constants in implementations)
     * @param allowed Whether the usage is allowed
     */
    function setUsagePermission(uint256 tokenId, uint8 usageType, bool allowed) 
        external 
        whenNotPaused
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        require(
            hasRole(CULTURAL_AUTHORITY_ROLE, msg.sender) || 
            hasRole(ADMIN_ROLE, msg.sender),
            "Not authorized"
        );
        
        _culturalMetadata[tokenId].allowedUsages[usageType] = allowed;
    }

    /**
     * @dev Transfer token with cultural attestations
     * @param from Current owner
     * @param to New owner
     * @param tokenId The token to transfer
     */
    function transferWithAttestations(address from, address to, uint256 tokenId) 
        external 
        whenNotPaused
    {
        require(_isAuthorized(_ownerOf(tokenId), msg.sender, tokenId), "Not approved or owner");
        require(_ownerOf(tokenId) != address(0), "Token does not exist");

        // Check if the token has transfer restrictions based on cultural sensitivity
        CulturalSensitivityLevel level = _culturalMetadata[tokenId].level;
        if (level == CulturalSensitivityLevel.SacredProtected) {
            require(
                hasRole(CULTURAL_AUTHORITY_ROLE, msg.sender),
                "Sacred items require cultural authority approval for transfer"
            );
        }
        
        _transfer(from, to, tokenId);
    }

    /**
     * @dev Get the latest state of a token
     * @param tokenId The token to query
     * @return The latest state data
     */
    function getLatestState(uint256 tokenId) 
        external 
        view 
        returns (bytes memory) 
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        uint256 historyLength = _tokenStateHistory[tokenId].length;
        
        if (historyLength == 0) {
            return "";
        }
        
        return _tokenStateHistory[tokenId][historyLength - 1].data;
    }

    /**
     * @dev Get the state history of a token
     * @param tokenId The token to query
     * @return Array of historical states
     */
    function getStateHistory(uint256 tokenId) 
        external 
        view 
        returns (TokenState[] memory) 
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        return _tokenStateHistory[tokenId];
    }

    /**
     * @dev Get the token metadata
     * @param tokenId The token to query
     * @return itemType The type of item
     * @return contentHash IPFS hash of the content
     * @return location Geographic location
     * @return creationTime When token was created
     * @return isVerified Whether token is verified
     * @return creator Original creator address
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
            address creator
        ) 
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        TokenMetadata storage metadata = _tokenMetadata[tokenId];
        return (
            metadata.itemType,
            metadata.contentHash,
            metadata.location,
            metadata.creationTime,
            metadata.isVerified,
            metadata.creator
        );
    }

    /**
     * @dev Get the cultural metadata for a token
     * @param tokenId The token to query
     * @return culture The cultural identity 
     * @return communityOrigin The community of origin
     * @return level The cultural sensitivity level
     * @return isVerified Whether metadata is verified
     * @return verifier Address of the verifier
     * @return verificationTimestamp When verification occurred
     * @return culturalContext Additional cultural information
     * @return hasUsageRestrictions Whether there are usage restrictions
     */
    function getCulturalMetadata(uint256 tokenId) 
        external 
        view 
        returns (
            string memory culture,
            string memory communityOrigin,
            CulturalSensitivityLevel level,
            bool isVerified,
            address verifier,
            uint256 verificationTimestamp,
            string memory culturalContext,
            bool hasUsageRestrictions
        ) 
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        CulturalMetadata storage metadata = _culturalMetadata[tokenId];
        return (
            metadata.culture,
            metadata.communityOrigin,
            metadata.level,
            metadata.isVerified,
            metadata.verifier,
            metadata.verificationTimestamp,
            metadata.culturalContext,
            metadata.hasUsageRestrictions
        );
    }

    /**
     * @dev Check if a specific usage is allowed for a token
     * @param tokenId The token to query
     * @param usageType The type of usage to check
     * @return Whether the usage is allowed
     */
    function isUsageAllowed(uint256 tokenId, uint8 usageType) 
        external 
        view 
        returns (bool) 
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        // If public domain, all usage is allowed
        if (_culturalMetadata[tokenId].level == CulturalSensitivityLevel.PublicDomain) {
            return true;
        }
        
        return _culturalMetadata[tokenId].allowedUsages[usageType];
    }

    /**
     * @dev Check if a user has access to a token
     * @param tokenId The token to query
     * @param user The user to check
     * @return Whether the user has access
     */
    function hasAccess(uint256 tokenId, address user) 
        external 
        view 
        returns (bool) 
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        // Owner always has access
        if (ownerOf(tokenId) == user) {
            return true;
        }
        
        // Admins and cultural authorities always have access
        if (hasRole(ADMIN_ROLE, user) || hasRole(CULTURAL_AUTHORITY_ROLE, user)) {
            return true;
        }
        
        // Public domain items are accessible to everyone
        if (_culturalMetadata[tokenId].level == CulturalSensitivityLevel.PublicDomain) {
            return true;
        }
        
        // Check explicit access grants
        return _tokenAccess[tokenId][user];
    }

    /**
     * @dev Override ERC721 _update to add custom transfer restrictions
     */
    function _update(address to, uint256 tokenId, address auth) internal override whenNotPaused returns (address) {
        address from = _ownerOf(tokenId);
        
        // If not minting and the token has high cultural sensitivity, check restrictions
        if (from != address(0)) {
            CulturalSensitivityLevel level = _culturalMetadata[tokenId].level;
            
            // Ceremonial restricted tokens need approval or admin/cultural authority role
            if (level == CulturalSensitivityLevel.CeremonialRestricted) {
                require(
                    hasRole(ADMIN_ROLE, auth) || 
                    hasRole(CULTURAL_AUTHORITY_ROLE, auth) || 
                    _isAuthorized(from, auth, tokenId),
                    "Transfer restricted: cultural approval needed"
                );
            }
            
            // Sacred protected tokens cannot be transferred on regular markets
            if (level == CulturalSensitivityLevel.SacredProtected) {
                require(
                    hasRole(CULTURAL_AUTHORITY_ROLE, auth) || 
                    hasRole(ADMIN_ROLE, auth),
                    "Sacred items can only be transferred by cultural authorities"
                );
            }
        }
        
        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Override for ERC721 function to implement base URI
     */
    function _baseURI() internal pure override returns (string memory) {
        return "ipfs://";
    }

    /**
     * @dev Override supportsInterface to support all inherited interfaces
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}