// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title ArbitrumTokenAdapter
 * @dev Adapter for handling native ETH on Arbitrum with tier functionality
 */
contract ArbitrumTokenAdapter is AccessControl {
    using Address for address payable;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TIER_MANAGER_ROLE = keccak256("TIER_MANAGER_ROLE");
    
    // Tier levels - matching the Pasifika membership model
    uint256 public constant GUEST_TIER = 0;
    uint256 public constant MEMBER_TIER = 1;
    uint256 public constant NODE_OPERATOR_TIER = 2;
    
    // Mapping to track user tiers
    mapping(address => uint256) public userTiers;
    
    event EthReceived(address indexed sender, uint256 amount);
    event EthSent(address indexed recipient, uint256 amount);
    event TierAssigned(address indexed user, uint256 tier);
    event TierRemoved(address indexed user);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(TIER_MANAGER_ROLE, admin);
    }

    /**
     * @dev Function to receive Ether. Emits a {EthReceived} event.
     */
    receive() external payable {
        emit EthReceived(msg.sender, msg.value);
    }

    /**
     * @dev Sends ETH to a recipient address.
     * @param recipient Address to send ETH to
     * @param amount Amount of ETH to send
     */
    function sendEther(address payable recipient, uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(address(this).balance >= amount, "ArbitrumTokenAdapter: Insufficient balance");
        recipient.sendValue(amount);
        emit EthSent(recipient, amount);
    }

    /**
     * @dev Get the balance of the contract in ETH
     * @return The balance in wei
     */
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
    
    /**
     * @dev Assign a tier to a user
     * @param user Address of the user
     * @param tier Tier to assign
     */
    function assignTier(address user, uint256 tier) external onlyRole(TIER_MANAGER_ROLE) {
        require(user != address(0), "ArbitrumTokenAdapter: Zero address");
        require(tier <= NODE_OPERATOR_TIER, "ArbitrumTokenAdapter: Invalid tier");
        
        userTiers[user] = tier;
        emit TierAssigned(user, tier);
    }
    
    /**
     * @dev Remove tier from a user
     * @param user Address of the user
     */
    function removeTier(address user) external onlyRole(TIER_MANAGER_ROLE) {
        require(user != address(0), "ArbitrumTokenAdapter: Zero address");
        require(userTiers[user] > 0, "ArbitrumTokenAdapter: User has no tier");
        
        delete userTiers[user];
        emit TierRemoved(user);
    }
    
    /**
     * @dev Check if a user has a specific tier
     * @param user Address of the user
     * @param tier Tier to check
     * @return Boolean indicating if user has the tier
     */
    function hasTier(address user, uint256 tier) external view returns (bool) {
        return userTiers[user] == tier;
    }
    
    /**
     * @dev Get user's tier
     * @param user Address of the user
     * @return User's tier level
     */
    function getUserTier(address user) external view returns (uint256) {
        return userTiers[user];
    }
}
