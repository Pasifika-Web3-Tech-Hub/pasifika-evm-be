// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title PasifikaArbitrumNode
 * @dev Manages Pasifika node operations on Arbitrum network
 */
contract PasifikaArbitrumNode is AccessControl, Pausable {
    bytes32 public constant NODE_OPERATOR_ROLE = keccak256("NODE_OPERATOR_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    uint256 public minimumStake;
    mapping(address => bool) public activeNodes;
    mapping(address => uint256) public nodeStakes;
    uint256 public totalNodes;

    event NodeRegistered(address indexed operator, uint256 stake);
    event NodeDeactivated(address indexed operator);
    event NodeReactivated(address indexed operator);
    event StakeUpdated(address indexed operator, uint256 newStake);
    event MinimumStakeUpdated(uint256 newMinimumStake);

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        minimumStake = 0.1 ether; // Default minimum stake (0.1 ETH)
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
}
