# The Pasifika - Arbitrum Implementation

<div align="center">
  <img src="./pasifika.png" alt="Pasifika" width="300" height="300" />
  <h2>Building the Future of Pacific Island Web3 Technology on Arbitrum</h2>
  <p><em>Established 2025</em></p>
  <hr />
  <p><strong>"If we take care of our own, they will take care of us"</strong></p>
</div>

## Overview

The Pasifika backend is a decentralized physical infrastructure network (DePIN) designed for Pacific Island communities. This implementation leverages Arbitrum's Layer-2 scaling solution to create a sustainable economic ecosystem for Pacific Islanders.

## Pasifika Philosophy

At the heart of the Pasifika is our core philosophy:

> **"If we take care of our own, they will take care of us"**

This traditional Pacific Island value of communal support and shared prosperity guides our platform's design and economic model. We believe in building technology that reinforces our cultural values of community, reciprocity, and sustainability.

## Pasifika Annual Profit-Sharing Event

Inspired by our philosophy and the Bitcoin halving event, we've implemented the **Pasifika Annual Profit-Sharing Event** with the following features:

- **Equal Distribution**: 50% of all profits incurred within the Pasifika Treasury are distributed equally to all eligible registered members
- **Pasifika Financial Year**: Runs from December 27 (after Boxing Day) to December 24 (Christmas Eve)
- **Initial Treasury**: Seeded with ETH to provide a foundation for our ecosystem
- **Fully On-Chain**: All distributions are recorded on the Arbitrum blockchain, ensuring transparency and fairness
- **Eligibility Requirements**: Members must complete at least 100 transactions AND have a transaction volume of at least 1 ETH during the financial year to qualify for profit sharing

This event exemplifies our commitment to community wealth-sharing and ensuring that the benefits of technology reach all active members of our ecosystem, while encouraging platform participation.

## Technical Specifications

- **Blockchain**: Arbitrum - Ethereum Layer 2 scaling solution
- **Native Currency**: ETH (Ethereum)
- **Development Framework:** Foundry
- **Solidity Version:** 0.8.19 and 0.8.20
- **OpenZeppelin:** v5.3.0

## Arbitrum-Specific Components

The backend consists of the following Arbitrum-specific implementations:

### 3-Tier System

We've simplified our membership and fee structure to a 3-tier system:

1. **Tier 0: Guest** 
   - Default tier for all users
   - 1% fee on all transactions
   - No special requirements

2. **Tier 1: Member**
   - 0.5% fee on all transactions (50% discount)
   - Requires membership (0.005 ETH)

3. **Tier 2: Member Node Operator**
   - 0.25% fee on all transactions (75% discount)
   - Requires operating a validator node on the network

## Smart Contract System

The smart contract system leverages the native assets of the Arbitrum network:

- **ArbitrumTokenAdapter Contract**: Implementation of the 3-tier system for Arbitrum, handling:
  - User tier management
  - Fee calculation based on tier level
  - Tier verification

- **PasifikaArbitrumNode Contract**: Node management for the Arbitrum network with:
  - Node registration and activation
  - Staking mechanism using ETH
  - Validator status tracking
  - Role-based access control

- **PasifikaMembership Contract**: Membership management with:
  - Membership registration using 0.005 ETH
  - Annual profit-sharing distribution of ETH to eligible members
  - Transaction tracking for profit sharing eligibility
  - Financial year calculations
  - Member verification

- **PasifikaMoneyTransfer Contract**: Arbitrum-native money transfer with:
  - Fee calculation based on user tier
  - Integration with ArbitrumTokenAdapter
  - Support for ETH transfers
  - Secure transaction handling

- **PasifikaTreasury Contract**: Multi-signature treasury management with:
  - Budget categories and allocations
  - Spending proposals and approvals
  - Fund recovery mechanisms
  - ETH management for profit-sharing events

### Membership System

Our membership system is designed to provide clear benefits to platform participants:

1. **Transaction Fee Discounts**:
   - Members receive 50% off transaction fees
   - Node operators receive 75% off transaction fees

2. **Annual Profit Sharing**:
   - Eligible members receive an equal share of 50% of treasury profits
   - Distribution happens at the end of the Pasifika Financial Year

3. **Platform Governance Rights**:
   - Members gain voting rights on platform decisions
   - Node operators receive additional voting weight

### Deployment Process

The deployment process is streamlined with Foundry's powerful toolkit:

1. **Setup**:
   ```bash
   $ forge build
   ```

2. **Testing**:
   ```bash
   $ forge test
   ```

3. **Deployment to Arbitrum Network**:
   ```bash
   $ ./deploy/arbitrum-deploy.sh
   ```

For testnet deployments, use the `.env.testnet` configuration file.

## Security and Transparency

Our contracts implement best practices for security:

- OpenZeppelin v5.3.0 libraries for access control, pausability, and reentrancy protection
- Multi-signature requirements for treasury operations
- Role-based access control for administrative functions
- Fee collection mechanisms with transparent allocation

## License

This project is licensed under the MIT License - see the LICENSE file for details.
