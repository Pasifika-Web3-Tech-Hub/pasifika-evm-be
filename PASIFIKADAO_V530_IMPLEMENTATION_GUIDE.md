# PasifikaDAO v5.3.0 Implementation Guide

This guide provides a comprehensive overview of the changes required to make the PasifikaDAO fully compatible with OpenZeppelin v5.3.0.

## Key Changes for v5.3.0 Compatibility

### 1. MockToken Updates

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";

/**
 * @title MockToken
 * @dev A governance token for testing the PasifikaDAO
 * Compatible with OpenZeppelin v5.3.0
 */
contract MockToken is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /**
     * @dev Constructor for the MockToken contract 
     * Initializes with the name "Pasifika Governance Token" and symbol "PGT"
     */
    constructor() 
        ERC20("Pasifika Governance Token", "PGT") 
        ERC20Permit("Pasifika Governance Token")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    /**
     * @dev Mints new tokens to the specified address
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @dev Updates token balances with ERC20Votes support
     * OpenZeppelin v5.3.0 uses _update instead of _beforeTokenTransfer/_afterTokenTransfer
     */
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    /**
     * @dev Returns the current nonce for an address - required by ERC20Permit
     */
    function nonces(address owner) public view virtual override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
```

### 2. PasifikaDAO Override Changes

For the PasifikaDAO contract, the following changes are required in the function overrides:

#### Before v5.3.0
```solidity
function votingDelay() public view override(Governor, GovernorSettings) returns (uint256)
```

#### After v5.3.0
```solidity
function votingDelay() public view override(IGovernor, GovernorSettings) returns (uint256)
```

#### Key Changes in Function Overrides:

1. `propose` should override `Governor` and `IGovernor`
2. In `supportsInterface` method, include `IERC165` in the override list
3. Add the required function overrides for v5.3.0:
   ```solidity
   function _queueOperations(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
       internal
       override(Governor, GovernorTimelockControl)
       returns (uint48)
   {
       return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
   }
   
   function _executeOperations(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
       internal
       override(Governor, GovernorTimelockControl)
   {
       super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
   }
   ```

### 3. Constructor Pattern Changes

Ensure all constructors properly call parent constructors with required parameters:

```solidity
// Constructor
constructor(
    string memory _name,
    IVotes _token,
    TimelockController _timelock,
    uint48 _votingDelay,
    uint32 _votingPeriod,
    uint256 _proposalThreshold,
    uint256 _quorumFraction
)
    Governor(_name)
    GovernorSettings(_votingDelay, _votingPeriod, _proposalThreshold)
    GovernorVotes(_token)
    GovernorVotesQuorumFraction(_quorumFraction)
    GovernorTimelockControl(_timelock)
{
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _grantRole(GOVERNANCE_ADMIN_ROLE, msg.sender);
    _grantRole(COMMUNITY_VERIFIER_ROLE, msg.sender);
}
```

## Advanced Features Implemented

### 1. Quadratic Voting

The implementation includes support for quadratic voting, where voting power equals the square root of tokens:

```solidity
function sqrt(uint256 x) public pure returns (uint256 y) {
    if (x == 0) return 0;
    
    // Initial estimate
    uint256 z = (x + 1) / 2;
    y = x;
    
    // Find sqrt using Babylonian method
    while (z < y) {
        y = z;
        z = (x / z + z) / 2;
    }
}
```

Used in the voting mechanism:

```solidity
// Apply quadratic voting calculation (sqrt)
weight = sqrt(weight);
```

### 2. Pacific Islander Voting Power Multiplier

Pacific Islanders receive a voting power multiplier:

```solidity
// Apply Pacific Islander multiplier if applicable
if (hasRole(PACIFIC_ISLANDER_ROLE, voter)) {
    weight = (weight * pacificIslanderVotingPowerMultiplier) / 100;
}
```

### 3. Enhanced Proposal Management

The contract includes additional proposal metadata and extended states:

```solidity
struct ProposalMetadata {
    string title;
    string description;
    string category; // e.g., "Cultural", "Financial", "Technical"
    address proposer;
    uint256 creationTime;
    bool isQuadratic; // Whether this proposal uses quadratic voting
    bool isEmergency; // Emergency proposals have shorter voting periods
    string[] attachedDocuments; // IPFS hashes to additional documentation
}
```

### 4. Community Veto Mechanism

Allows authorized community members to veto proposals:

```solidity
function vetoProposal(uint256 proposalId) 
    external 
    onlyRole(COMMUNITY_VERIFIER_ROLE)
{
    // Verify the proposal is in a state that can be vetoed
    ProposalState currentState = state(proposalId);
    require(
        currentState == ProposalState.Pending ||
        currentState == ProposalState.Active ||
        currentState == ProposalState.Succeeded ||
        currentState == ProposalState.Queued,
        "Proposal cannot be vetoed in its current state"
    );
    
    // Mark as vetoed
    vetoed[proposalId] = true;
    
    // Emit event
    emit ProposalVetoed(proposalId, _msgSender());
}
```

## Testing

For testing this implementation, ensure:

1. A proper timelock controller is set up
2. Token delegation is properly configured before voting
3. Pacific Islander role assignments are tested
4. Quadratic voting calculations are verified
5. The execution flow from proposal creation to execution is tested

## Integration Steps

1. Replace existing MockToken with the v5.3.0 compatible version
2. Update PasifikaDAO with the correct override patterns
3. Run isolated tests to verify functionality
4. Update dependent contracts to use the new implementation

## Common Compilation Issues

1. When multiple Governor contracts are in the same project, use targeted test scripts
2. Ensure all imports are using the same version of OpenZeppelin
3. Pay special attention to the override patterns as they've changed in v5.3.0
