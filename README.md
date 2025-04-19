# The Pasifika Web3 Tech Hub Backend

<p align="center">
 <img width="1000" src="/pasifika.png">
</p>

## Overview

The Pasifika Web3 Tech Hub backend is a decentralized physical infrastructure network (DePIN) designed for Pacific Island communities. The platform leverages Linea's zkEVM Layer-2 technology and the native PASIFIKA token (PSF) to create a sustainable economic ecosystem.

## Technical Specifications

- **Solidity Version:** 0.8.19 and 0.8.20
- **OpenZeppelin:** v5.3.0
- **Development Framework:** Foundry

## Current Components

The backend currently consists of the following implemented components:

### Smart Contract System

The smart contract system is built using Solidity and Foundry development toolkit:

- **PSFToken Contract**: Core ERC-20 token (PSF) with:
  - Governance extensions (ERC20Votes)
  - Permit functionality (ERC20Permit)
  - Access control for roles
  - Token burning mechanism
  - Vesting schedules for team, investors, and partners
  - Staking functionality
  - Pausability for emergency situations

- **PSFStaking Contract**: Advanced staking mechanism with:
  - Multiple staking tiers (Basic, Silver, Gold, Platinum, Validator, NodeOperator)
  - Duration-based reward multipliers for longer staking periods
  - Special roles for validators and node operators
  - Dynamic governance weight calculation
  - Flexible admin controls for tier requirements and bonuses
  - Reward distribution system
  - Security features including pausability and emergency withdrawals

- **PasifikaDynamicNFT Contract**: NFT system with:
  - Customizable metadata and on-chain state
  - Cultural context verification
  - Usage permissions and attestations
  - State history tracking
  - Transfer restrictions
  
- **PasifikaMarketplace Contract**: NFT marketplace with:
  - Fixed price and auction listings
  - Bidding mechanism for auctions
  - Escrow functionality
  - Dispute resolution
  - Fee management system
  - Admin controls

### Planned Future Components

Additional components from the smart contracts documentation are planned for future implementation:

- Advanced Governance System
- Oracle Integration
- Cultural Protection System Enhancements
- Treasury Management
- AI Agent Coordination
- API Layer
- Database Layer
- Infrastructure components

## Smart Contract Architecture

### Dependencies and Libraries

#### OpenZeppelin Contracts

This project uses **OpenZeppelin Contracts v5.3.0** for implementing secure, standard-compliant smart contracts.

- All contracts use the same version (v5.3.0) to ensure compatibility
- Contracts inherit from OpenZeppelin's battle-tested implementations
- Compiler uses IR-based pipeline for optimization

**Key OpenZeppelin components used:**
- Access Control (`AccessControl.sol`)
- Token Standards (`ERC20.sol`, `ERC721.sol`)
- Token Extensions (`ERC20Votes.sol`, `ERC721URIStorage.sol`) 
- Security Utilities (`Pausable.sol`, `ReentrancyGuard.sol`)

**Best Practices for OpenZeppelin Integration:**
1. **Version Consistency**: Always maintain consistent versions across all OpenZeppelin dependencies
2. **Inheritance**: Use inheritance instead of reimplementing standard functionality
3. **Override Safety**: When overriding OpenZeppelin functions, always call the parent implementation
4. **Import Specificity**: Import only the specific contracts you need rather than full libraries
5. **Testing**: Thoroughly test all custom extensions to OpenZeppelin contracts

### Currently Implemented

#### PSFToken.sol

Core ERC-20 token contract for the PASIFIKA token (PSF).

**Key Features:**
- Standard ERC-20 functionality
- Governance extensions (ERC20Votes)
- Vesting schedules for team, investors, and partners
- Staking functionality
- Role-based access control
- Pausability for emergency situations

**Contract Components:**
- Max supply of 1 billion tokens
- Role definitions (ADMIN, MINTER, BURNER, TREASURY)
- Vesting schedule management
- Staking functionality
- Token burning mechanism

#### PSFStaking.sol

Advanced staking contract that enables users to stake PSF tokens with varying tiers and durations.

**Key Features:**
- Tiered staking system with different rewards based on amount and duration
- Duration-based multipliers for longer-term stakers
- Special validator and node operator tiers with additional permissions
- Dynamic governance weight calculation based on stake amount, tier, and remaining duration
- Comprehensive reward calculation system
- Administrative controls for adjusting tiers, rewards, and bonuses
- Emergency controls including pausability and emergency withdrawals

**Contract Components:**
- StakeInfo structure for tracking stakes
- TierRequirement structure for defining tier parameters
- DurationBonus structure for rewarding longer-term stakers
- Role-based access control (ADMIN, REWARDS_DISTRIBUTOR, VALIDATOR, NODE_OPERATOR)
- Functions for creating, increasing, extending, and unstaking
- Reward calculation and claiming mechanism
- Governance weight calculation

#### PasifikaMarketplace.sol

NFT marketplace contract that enables buying, selling, and auctioning NFTs.

**Key Features:**
- Fixed price and auction listings
- Bidding mechanism for auctions
- Escrow functionality
- Dispute resolution
- Fee management
- Admin controls

**Contract Components:**
- Listing structure for tracking listed items
- Bid structure for tracking auction bids
- Role-based access control (ADMIN, MODERATOR, FEE_MANAGER)
- Escrow management
- Auction timing and finalization

## Process Flow Diagram

```mermaid
graph TD
    A[User] --> B[PSFToken Contract]
    B --> C[Token Transfers]
    B --> D[Governance Voting]
    B --> E1[Basic Staking]
    B --> F[Vesting Management]
    
    A --> G[PSFStaking Contract]
    G --> E2[Advanced Staking]
    G --> H[Validator Management]
    G --> I[Node Operator Management]
    G --> J[Reward Distribution]
    G --> K[Governance Weight]
    
    L[Admin] --> M[Role Management]
    M --> B
    M --> G
    
    N[Treasury] --> O[Token Distribution]
    O --> B
    
    subgraph "Smart Contract System"
        B
        C
        D
        E1
        F
        G
        E2
        H
        I
        J
        K
        M
    end
```

## Development Tools

### Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

### Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
