// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title PasifikaLineaNode
 * @dev Manages Pasifika node operations on Linea network
 * @notice Optimized for Linea transactions and gas efficiency
 */
contract PasifikaLineaNode is AccessControl, Pausable {
    bytes32 public constant NODE_OPERATOR_ROLE = keccak256("NODE_OPERATOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    uint256 public minimumStake;
    mapping(address => bool) public activeNodes;
    mapping(address => uint256) public nodeStakes;
    uint256 public totalNodes;

    // Linea-specific settings - lower gas costs on Linea can allow for more operations
    uint256 public nodeOperationFee;
    bool public autoCompounding;

    event NodeRegistered(address indexed operator, uint256 stake);
    event NodeDeactivated(address indexed operator);
    event NodeReactivated(address indexed operator);
    event StakeUpdated(address indexed operator, uint256 newStake);
    event MinimumStakeUpdated(uint256 newMinimumStake);
    event NodeOperationFeeUpdated(uint256 newFee);
    event AutoCompoundingToggled(bool enabled);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        minimumStake = 0.05 ether; // Lower minimum stake for Linea (0.05 ETH)
        nodeOperationFee = 0.001 ether; // Small fee for node operations
        autoCompounding = true; // Default to auto-compounding for rewards
    }

    /**
     * @dev Registers a new node operator
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
        require(!activeNodes[operator] && nodeStakes[operator] > 0, "Node not properly registered");

        activeNodes[operator] = true;
        _grantRole(NODE_OPERATOR_ROLE, operator);
        emit NodeReactivated(operator);
    }

    /**
     * @dev Updates the minimum stake required for node operation
     * @param newMinimumStake New minimum stake amount in ETH
     */
    function updateMinimumStake(uint256 newMinimumStake) external onlyRole(ADMIN_ROLE) {
        minimumStake = newMinimumStake;
        emit MinimumStakeUpdated(newMinimumStake);
    }

    /**
     * @dev Updates the node operation fee
     * @param newFee New fee amount in ETH
     */
    function updateNodeOperationFee(uint256 newFee) external onlyRole(ADMIN_ROLE) {
        nodeOperationFee = newFee;
        emit NodeOperationFeeUpdated(newFee);
    }

    /**
     * @dev Toggles auto-compounding of rewards
     * @param enabled Whether auto-compounding should be enabled
     */
    function toggleAutoCompounding(bool enabled) external onlyRole(ADMIN_ROLE) {
        autoCompounding = enabled;
        emit AutoCompoundingToggled(enabled);
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
     * @dev Adds additional stake to an existing node
     * @param operator Address of the node operator
     */
    function addStake(address operator) external payable onlyRole(ADMIN_ROLE) whenNotPaused {
        require(nodeStakes[operator] > 0, "Node not registered");

        nodeStakes[operator] += msg.value;
        emit StakeUpdated(operator, nodeStakes[operator]);
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
     * @dev Get the total stake of all active nodes
     * @return Total stake amount in ETH
     */
    function getTotalStake() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Get the fee tier for a specific address (optimized for Linea's low gas costs)
     * @param userAddress Address to check
     * @return Fee percentage (in basis points: 25 = 0.25%, 50 = 0.5%, 100 = 1%)
     */
    function getFeeTier(address userAddress) external view returns (uint256) {
        if (activeNodes[userAddress] && hasRole(NODE_OPERATOR_ROLE, userAddress)) {
            return 25; // 0.25% for node operators
        }
        return 100; // 1% default fee
    }
}
