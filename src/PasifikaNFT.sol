// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IERC2981 } from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./PasifikaMembership.sol";
import "./PasifikaArbitrumNode.sol";

/**
 * @title PasifikaNFT
 * @dev A consolidated NFT contract for Pasifika
 * This contract handles minting, royalty management, and trading of NFTs
 * With special features for physical item minting and token-gated governance
 *
 * NFTs can represent:
 * - Digital art
 * - Physical items with QR code tracking (supports authenticity & provenance)
 * - Memberships (token-gated access with "soul-bound" non-transferability)
 * - Contributions to the ecosystem
 */
contract PasifikaNFT is ERC721, AccessControl, IERC2981, Pausable, ReentrancyGuard {
    using Strings for uint256;

    // Simple counter implementation to replace OpenZeppelin Counters
    struct Counter {
        uint256 _value; // default: 0
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function increment(Counter storage counter) internal {
        counter._value += 1;
    }

    function decrement(Counter storage counter) internal {
        counter._value = counter._value - 1;
    }

    function reset(Counter storage counter) internal {
        counter._value = 0;
    }

    // NFT Types
    enum ItemType {
        Digital,
        Physical
    }

    // Roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;

    // Token counter
    Counter private _tokenIdCounter;

    // Base URI for token metadata
    string private _baseTokenURI;

    // Token URI storage
    mapping(uint256 => string) private _tokenURIs;

    // Royalty percentages (in basis points, e.g., 100 = 1%)
    uint96 public defaultRoyaltyPercent = 100; // 1% default royalty
    uint96 public memberRoyaltyPercent = 50; // 0.5% member royalty
    uint96 public validatorRoyaltyPercent = 25; // 0.25% validator royalty

    // Membership contract for membership verification
    PasifikaMembership public membershipContract;

    // Node contract for validator node verification
    PasifikaArbitrumNode public nodeContract;

    // Token metadata
    struct ItemMetadata {
        address creator;
        string tokenURI;
        ItemType itemType;
        uint96 royaltyPercent;
        string physicalDetails; // JSON string for physical items
    }

    // Mapping from token ID to token metadata
    mapping(uint256 => ItemMetadata) internal _itemMetadata;

    // Events
    event NFTMinted(uint256 indexed tokenId, address indexed creator, address indexed owner, ItemType itemType);
    event DefaultRoyaltyUpdated(uint96 newDefaultRoyalty);
    event MemberRoyaltyUpdated(uint96 newMemberRoyalty);
    event ValidatorRoyaltyUpdated(uint96 newValidatorRoyalty);
    event MembershipContractUpdated(address indexed newMembershipContract);
    event NodeContractUpdated(address indexed newNodeContract);
    event BaseURIUpdated(string newBaseURI);

    /**
     * @dev Constructor
     * @param name Name of the NFT collection
     * @param symbol Symbol of the NFT collection
     * @param baseURI Base URI for token metadata
     */
    constructor(string memory name, string memory symbol, string memory baseURI) ERC721(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _baseTokenURI = baseURI;
    }

    /**
     * @dev Mint a new NFT token
     * @param to Recipient of the NFT
     * @param uri URI for token metadata
     * @param itemType Type of the item (Digital or Physical)
     * @param royaltyPercent Royalty percentage for this specific NFT
     * @param physicalDetails Details for physical items (empty for digital)
     * @return uint256 ID of the newly minted token
     */
    function mint(
        address to,
        string memory uri,
        ItemType itemType,
        uint96 royaltyPercent,
        string memory physicalDetails
    ) public nonReentrant whenNotPaused onlyRole(MINTER_ROLE) returns (uint256) {
        require(to != address(0), "PasifikaNFT: mint to zero address");

        increment(_tokenIdCounter);
        uint256 tokenId = current(_tokenIdCounter);
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);

        // Store metadata
        _itemMetadata[tokenId] = ItemMetadata({
            creator: to,
            tokenURI: uri,
            itemType: itemType,
            royaltyPercent: royaltyPercent,
            physicalDetails: physicalDetails
        });

        emit NFTMinted(tokenId, to, to, itemType);
        return tokenId;
    }

    /**
     * @dev Set the token URI for a token
     * @param tokenId Token ID
     * @param _tokenURI URI for token metadata
     */
    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        require(exists(tokenId), "PasifikaNFT: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    /**
     * @dev Override tokenURI function to return custom URI
     * @param tokenId Token ID
     * @return string URI for token metadata
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(exists(tokenId), "PasifikaNFT: URI query for nonexistent token");

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via string.concat).
        if (bytes(_tokenURI).length > 0) {
            return string.concat(base, _tokenURI);
        }
        // If there is a baseURI but no tokenURI, concatenate the tokenID to the baseURI.
        return string.concat(base, Strings.toString(tokenId));
    }

    /**
     * @dev Return base URI for token metadata
     * @return string Base URI
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @dev Set the base URI for all tokens
     * @param newBaseURI New base URI
     */
    function setBaseURI(string memory newBaseURI) external onlyRole(ADMIN_ROLE) {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    /**
     * @dev Get the item type of a token
     * @param tokenId Token ID
     * @return ItemType Type of the item (Digital or Physical)
     */
    function getItemType(uint256 tokenId) external view returns (ItemType) {
        require(exists(tokenId), "PasifikaNFT: nonexistent token");
        return _itemMetadata[tokenId].itemType;
    }

    /**
     * @dev Set the royalty percentage for validators
     * @param _validatorRoyaltyPercent New validator royalty percentage
     */
    function setValidatorRoyalty(uint96 _validatorRoyaltyPercent) external onlyRole(ADMIN_ROLE) {
        require(_validatorRoyaltyPercent <= 1000, "PasifikaNFT: royalty too high"); // Max 10%
        validatorRoyaltyPercent = _validatorRoyaltyPercent;
        emit ValidatorRoyaltyUpdated(_validatorRoyaltyPercent);
    }

    /**
     * @dev Set the node contract for validator verification
     * @param _nodeContract Address of the node contract
     */
    function setNodeContract(address payable _nodeContract) external onlyRole(ADMIN_ROLE) {
        require(_nodeContract != address(0), "PasifikaNFT: zero address");
        nodeContract = PasifikaArbitrumNode(_nodeContract);
        emit NodeContractUpdated(_nodeContract);
    }

    /**
     * @dev Get the validator royalty percentage
     * @return uint96 Validator royalty percentage
     */
    function getValidatorRoyalty() external view returns (uint96) {
        return validatorRoyaltyPercent;
    }

    /**
     * @dev Get the node contract
     * @return PasifikaArbitrumNode address
     */
    function getNodeContract() external view returns (PasifikaArbitrumNode) {
        return nodeContract;
    }

    /**
     * @dev Check if a token exists
     * @param tokenId Token ID to check
     * @return bool Whether the token exists
     */
    function exists(uint256 tokenId) public view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    /**
     * @dev Returns royalty information for a token
     * @param _tokenId Token ID for which to get royalty info
     * @param _salePrice Sale price of the token
     * @return receiver Receiver of the royalty
     * @return royaltyAmount Amount of the royalty
     */
    function royaltyInfo(uint256 _tokenId, uint256 _salePrice) external view override returns (address, uint256) {
        if (exists(_tokenId)) {
            address creator = _itemMetadata[_tokenId].creator;
            uint96 royaltyPercentToUse = _itemMetadata[_tokenId].royaltyPercent;

            // Check if the buyer is a validator
            if (address(nodeContract) != address(0) && nodeContract.isActiveNodeOperator(msg.sender)) {
                royaltyPercentToUse = validatorRoyaltyPercent; // 0.25% for validators
            }
            // If not a validator, check if they're a member
            else if (address(membershipContract) != address(0) && membershipContract.checkMembership(msg.sender)) {
                royaltyPercentToUse = memberRoyaltyPercent; // 0.5% for members
            }

            return (creator, (_salePrice * royaltyPercentToUse) / 10000);
        }
        return (address(0), (_salePrice * defaultRoyaltyPercent) / 10000);
    }

    /**
     * @dev Get the default royalty percentage
     * @return uint96 Default royalty percentage
     */
    function getDefaultRoyalty() external view returns (uint96) {
        return defaultRoyaltyPercent;
    }

    /**
     * @dev Set default royalty percentage
     * @param royaltyPercent Default royalty percentage in basis points
     */
    function setDefaultRoyalty(uint96 royaltyPercent) external onlyRole(ADMIN_ROLE) {
        require(royaltyPercent <= 100, "PasifikaNFT: royalty too high (max 1%)");
        defaultRoyaltyPercent = royaltyPercent;
        emit DefaultRoyaltyUpdated(royaltyPercent);
    }

    /**
     * @dev Set member royalty percentage
     * @param royaltyPercent Member royalty percentage in basis points
     */
    function setMemberRoyalty(uint96 royaltyPercent) external onlyRole(ADMIN_ROLE) {
        require(royaltyPercent <= 100, "PasifikaNFT: royalty too high (max 1%)");
        memberRoyaltyPercent = royaltyPercent;
        emit MemberRoyaltyUpdated(royaltyPercent);
    }

    /**
     * @dev Get the member royalty percentage
     * @return uint96 Member royalty percentage
     */
    function getMemberRoyalty() external view returns (uint96) {
        return memberRoyaltyPercent;
    }

    /**
     * @dev Set the membership contract address
     * @param _membership New membership contract address
     */
    function setMembershipContract(address _membership) external onlyRole(ADMIN_ROLE) {
        require(_membership != address(0), "PasifikaNFT: zero address");
        membershipContract = PasifikaMembership(payable(_membership));
        emit MembershipContractUpdated(_membership);
    }

    /**
     * @dev Get the membership contract
     * @return address of the membership contract
     */
    function getMembershipContract() external view returns (PasifikaMembership) {
        return membershipContract;
    }

    /**
     * @dev Get the creator of a token
     * @param tokenId Token ID
     * @return Creator address
     */
    function getCreator(uint256 tokenId) external view returns (address) {
        require(exists(tokenId), "PasifikaNFT: nonexistent token");
        return _itemMetadata[tokenId].creator;
    }

    /**
     * @dev Burns a token
     * @param tokenId The token ID to burn
     */
    function burn(uint256 tokenId) external {
        address owner = ownerOf(tokenId);
        require(
            owner == _msgSender() || isApprovedForAll(owner, _msgSender()) || getApproved(tokenId) == _msgSender(),
            "PasifikaNFT: caller is not owner nor approved"
        );
        _update(address(0), tokenId, _msgSender());
    }

    /**
     * @dev Get the complete metadata for a token
     * @param tokenId Token ID
     * @return creator Address of the creator
     * @return uri URI of the token
     * @return itemType Type of the item
     * @return royaltyPercent Royalty percentage
     * @return physicalDetails Physical details (if applicable)
     */
    function getMetadata(uint256 tokenId)
        external
        view
        returns (
            address creator,
            string memory uri,
            ItemType itemType,
            uint96 royaltyPercent,
            string memory physicalDetails
        )
    {
        require(exists(tokenId), "PasifikaNFT: nonexistent token");
        ItemMetadata storage metadata = _itemMetadata[tokenId];
        return
            (metadata.creator, metadata.tokenURI, metadata.itemType, metadata.royaltyPercent, metadata.physicalDetails);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Custom implementation for burning tokens
     * @param tokenId The token ID to burn
     */
    function _afterBurn(uint256 tokenId) internal virtual {
        // If there is a tokenURI, delete it
        if (bytes(_tokenURIs[tokenId]).length != 0) {
            delete _tokenURIs[tokenId];
        }

        // Clean up metadata
        delete _itemMetadata[tokenId];
    }

    // Override the _update function to catch burn operations
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address from = super._update(to, tokenId, auth);

        // If this is a burn operation (transfer to zero address)
        if (to == address(0)) {
            _afterBurn(tokenId);
        }

        return from;
    }
}
