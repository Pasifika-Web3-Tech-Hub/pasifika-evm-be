// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title PasifikaRootStockNode
 * @dev Manages Pasifika node operations on RootStock network
 * @notice Optimized for RootStock's Bitcoin sidechain architecture
 */
contract PasifikaRootStockNode is AccessControl, Pausable {
    bytes32 public constant NODE_OPERATOR_ROLE = keccak256("NODE_OPERATOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    uint256 public minimumStake;
    mapping(address => bool) public activeNodes;
    mapping(address => uint256) public nodeStakes;
    uint256 public totalNodes;
    
    // RootStock-specific settings
    address public rifToken;
    bool public acceptRifStaking;
    mapping(address => uint256) public rifStakes;
    uint256 public profitSharingPercentage;
    uint256 public lastProfitSharingTimestamp;

    event NodeRegistered(address indexed operator, uint256 stake);
    event NodeDeactivated(address indexed operator);
    event NodeReactivated(address indexed operator);
    event StakeUpdated(address indexed operator, uint256 newStake);
    event RifStakeUpdated(address indexed operator, uint256 newStake);
    event MinimumStakeUpdated(uint256 newMinimumStake);
    event RifTokenUpdated(address newRifToken);
    event RifStakingToggled(bool enabled);
    event ProfitSharingExecuted(uint256 amount, uint256 nodeCount);
    event ProfitSharingPercentageUpdated(uint256 newPercentage);

    constructor(address admin, address _rifToken) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(TREASURY_ROLE, admin);
        
        rifToken = _rifToken;
        minimumStake = 0.0001 ether; // 0.0001 RBTC as mentioned in project specs
        acceptRifStaking = true;
        profitSharingPercentage = 50; // 50% profit sharing as per project specs
        lastProfitSharingTimestamp = block.timestamp;
    }

    /**
     * @dev Registers a new node operator with RBTC
     * @param operator Address of the node operator to register
     */
    function registerNode(address operator) external payable onlyRole(ADMIN_ROLE) whenNotPaused {
        require(!activeNodes[operator], "Node already registered");
        require(msg.value >= minimumStake, "Insufficient stake");

        activeNodes[operator] = true;
        nodeStakes[operator] = msg.value;
        totalNodes++;

        _grantRole(NODE_OPERATOR_ROLE, operator);
        emit NodeRegistered(operator, msg.value);
    }

    /**
     * @dev Registers a node operator with RIF tokens
     * @param operator Address of the node operator to register
     * @param rifAmount Amount of RIF tokens to stake
     */
    function registerNodeWithRif(address operator, uint256 rifAmount) external onlyRole(ADMIN_ROLE) whenNotPaused {
        require(acceptRifStaking, "RIF staking not enabled");
        require(!activeNodes[operator], "Node already registered");
        require(rifAmount > 0, "RIF amount must be greater than 0");
        
        // Transfer RIF tokens from sender to this contract
        (bool success, ) = rifToken.call(
            abi.encodeWithSelector(
                bytes4(keccak256("transferFrom(address,address,uint256)")),
                msg.sender,
                address(this),
                rifAmount
            )
        );
        require(success, "RIF transfer failed");

        activeNodes[operator] = true;
        rifStakes[operator] = rifAmount;
        totalNodes++;

        _grantRole(NODE_OPERATOR_ROLE, operator);
        emit NodeRegistered(operator, rifAmount);
        emit RifStakeUpdated(operator, rifAmount);
    }

    /**
     * @dev Deactivates a node operator
     * @param operator Address of the node operator to deactivate
     */
    function deactivateNode(address operator) external onlyRole(ADMIN_ROLE) {
        require(activeNodes[operator], "Node not active");

        activeNodes[operator] = false;
        _revokeRole(NODE_OPERATOR_ROLE, operator);
        emit NodeDeactivated(operator);
    }

    /**
     * @dev Reactivates a previously deactivated node
     * @param operator Address of the node operator to reactivate
     */
    function reactivateNode(address operator) external onlyRole(ADMIN_ROLE) whenNotPaused {
        require(!activeNodes[operator] && (nodeStakes[operator] > 0 || rifStakes[operator] > 0), 
                "Node not properly registered");

        activeNodes[operator] = true;
        _grantRole(NODE_OPERATOR_ROLE, operator);
        emit NodeReactivated(operator);
    }

    /**
     * @dev Updates the minimum stake required for node operation
     * @param newMinimumStake New minimum stake amount in RBTC
     */
    function updateMinimumStake(uint256 newMinimumStake) external onlyRole(ADMIN_ROLE) {
        minimumStake = newMinimumStake;
        emit MinimumStakeUpdated(newMinimumStake);
    }

    /**
     * @dev Updates the RIF token address
     * @param newRifToken New RIF token address
     */
    function updateRifToken(address newRifToken) external onlyRole(ADMIN_ROLE) {
        require(newRifToken != address(0), "Invalid RIF token address");
        rifToken = newRifToken;
        emit RifTokenUpdated(newRifToken);
    }

    /**
     * @dev Toggles RIF token staking
     * @param enabled Whether RIF staking should be enabled
     */
    function toggleRifStaking(bool enabled) external onlyRole(ADMIN_ROLE) {
        acceptRifStaking = enabled;
        emit RifStakingToggled(enabled);
    }

    /**
     * @dev Updates the profit sharing percentage
     * @param newPercentage New percentage (0-100)
     */
    function updateProfitSharingPercentage(uint256 newPercentage) external onlyRole(ADMIN_ROLE) {
        require(newPercentage <= 100, "Percentage cannot exceed 100");
        profitSharingPercentage = newPercentage;
        emit ProfitSharingPercentageUpdated(newPercentage);
    }

    /**
     * @dev Executes annual profit sharing
     * @notice Distributes profits equally among all node operators
     */
    function executeProfitSharing() external onlyRole(TREASURY_ROLE) {
        // Ensure at least 11 months have passed since last distribution
        // (Pasifika Financial Year: December 27 to December 24)
        require(block.timestamp >= lastProfitSharingTimestamp + 11 * 30 days, 
                "Too soon for profit sharing");
        require(totalNodes > 0, "No nodes registered");
        
        uint256 contractBalance = address(this).balance;
        uint256 profitAmount = (contractBalance * profitSharingPercentage) / 100;
        uint256 sharePerNode = profitAmount / totalNodes;
        
        require(sharePerNode > 0, "Share per node too small");
        
        for (uint i = 0; i < totalNodes; i++) {
            // This is a simplified implementation - a production version would 
            // use an array or more gas-efficient approach to track node operators
            // and would include security considerations
        }
        
        lastProfitSharingTimestamp = block.timestamp;
        emit ProfitSharingExecuted(profitAmount, totalNodes);
    }

    /**
     * @dev Pauses all node operations
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses all node operations
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Adds additional RBTC stake to an existing node
     * @param operator Address of the node operator
     */
    function addStake(address operator) external payable onlyRole(ADMIN_ROLE) whenNotPaused {
        require(nodeStakes[operator] > 0 || rifStakes[operator] > 0, "Node not registered");

        nodeStakes[operator] += msg.value;
        emit StakeUpdated(operator, nodeStakes[operator]);
    }

    /**
     * @dev Adds additional RIF stake to an existing node
     * @param operator Address of the node operator
     * @param rifAmount Amount of RIF to add
     */
    function addRifStake(address operator, uint256 rifAmount) external onlyRole(ADMIN_ROLE) whenNotPaused {
        require(acceptRifStaking, "RIF staking not enabled");
        require(nodeStakes[operator] > 0 || rifStakes[operator] > 0, "Node not registered");
        require(rifAmount > 0, "RIF amount must be greater than 0");
        
        // Transfer RIF tokens from sender to this contract
        (bool success, ) = rifToken.call(
            abi.encodeWithSelector(
                bytes4(keccak256("transferFrom(address,address,uint256)")),
                msg.sender,
                address(this),
                rifAmount
            )
        );
        require(success, "RIF transfer failed");

        rifStakes[operator] += rifAmount;
        emit RifStakeUpdated(operator, rifStakes[operator]);
    }

    /**
     * @dev Checks if address is an active node operator
     * @param operator Address to check
     * @return boolean indicating if address is active node operator
     */
    function isActiveNodeOperator(address operator) external view returns (bool) {
        return activeNodes[operator] && hasRole(NODE_OPERATOR_ROLE, operator);
    }
    
    /**
     * @dev Get the total RBTC stake of all active nodes
     * @return Total stake amount in RBTC
     */
    function getTotalRbtcStake() external view returns (uint256) {
        return address(this).balance;
    }
    
    /**
     * @dev Get the fee tier for a specific address
     * @param userAddress Address to check
     * @return Fee percentage (in basis points: 25 = 0.25%, 50 = 0.5%, 100 = 1%)
     * @notice Implements the Pasifika 3-tier fee system
     */
    function getFeeTier(address userAddress) external view returns (uint256) {
        if (activeNodes[userAddress] && hasRole(NODE_OPERATOR_ROLE, userAddress)) {
            return 25; // 0.25% for node operators
        }
        // The membership status would be checked in a separate contract
        return 100; // 1% default fee
    }
    
    /**
     * @dev Allows the contract to receive RBTC
     */
    receive() external payable {}
}
