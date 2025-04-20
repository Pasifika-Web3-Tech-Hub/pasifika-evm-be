// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title PasifikaDAO
 * @dev Governance contract for the Pasifika ecosystem, compatible with OpenZeppelin v5.3.0
 */
contract PasifikaDAO is 
    Governor,
    GovernorCountingSimple,
    GovernorSettings, 
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl,
    AccessControl 
{
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");

    constructor(
        string memory name,
        IVotes token,
        TimelockController timelock,
        uint48 initialVotingDelay,
        uint32 initialVotingPeriod,
        uint256 initialProposalThreshold,
        uint256 quorumNumerator
    )
        Governor(name)
        GovernorSettings(initialVotingDelay, initialVotingPeriod, initialProposalThreshold)
        GovernorVotes(token)
        GovernorVotesQuorumFraction(quorumNumerator)
        GovernorTimelockControl(timelock)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MODERATOR_ROLE, msg.sender);
    }

    /* Required overrides */

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(Governor, AccessControl)
        returns (bool)
    {
        return Governor.supportsInterface(interfaceId) || AccessControl.supportsInterface(interfaceId);
    }
    
    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return GovernorSettings.votingDelay();
    }

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return GovernorSettings.votingPeriod();
    }

    function quorum(uint256 blockNumber) public view override(Governor, GovernorVotesQuorumFraction) returns (uint256) {
        return GovernorVotesQuorumFraction.quorum(blockNumber);
    }

    function state(uint256 proposalId) public view override(Governor, GovernorTimelockControl) returns (ProposalState) {
        return GovernorTimelockControl.state(proposalId);
    }

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return GovernorSettings.proposalThreshold();
    }

    function proposalNeedsQueuing(uint256 proposalId) public view override(Governor, GovernorTimelockControl) returns (bool) {
        return GovernorTimelockControl.proposalNeedsQueuing(proposalId);
    }

    // Proposal lifecycle functions
    function propose(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
        public
        override(Governor)
        returns (uint256)
    {
        return Governor.propose(targets, values, calldatas, description);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return GovernorTimelockControl._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return GovernorTimelockControl._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return GovernorTimelockControl._executor();
    }

    // PasifikaDAO specific functionality

    /**
     * @dev Updates the voting delay - can only be called by an admin
     * @param newVotingDelay The new voting delay in blocks
     */
    function setVotingDelay(uint48 newVotingDelay) public override(GovernorSettings) onlyRole(ADMIN_ROLE) {
        _setVotingDelay(newVotingDelay);
    }

    /**
     * @dev Updates the voting period - can only be called by an admin
     * @param newVotingPeriod The new voting period in blocks
     */
    function setVotingPeriod(uint32 newVotingPeriod) public override(GovernorSettings) onlyRole(ADMIN_ROLE) {
        _setVotingPeriod(newVotingPeriod);
    }

    /**
     * @dev Updates the proposal threshold - can only be called by an admin
     * @param newProposalThreshold The new proposal threshold
     */
    function setProposalThreshold(uint256 newProposalThreshold) public override(GovernorSettings) onlyRole(ADMIN_ROLE) {
        _setProposalThreshold(newProposalThreshold);
    }

    /**
     * @dev Updates the quorum numerator - can only be called by an admin
     * @param newQuorumNumerator The new quorum numerator
     */
    function updateQuorumNumerator(uint256 newQuorumNumerator) public override(GovernorVotesQuorumFraction) onlyRole(ADMIN_ROLE) {
        _updateQuorumNumerator(newQuorumNumerator);
    }
}
