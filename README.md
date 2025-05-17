# Pasifika Web3 Tech Hub - Multi-Network Exchange Implementation

<div align="center">
  <img src="./pasifika.png" alt="Pasifika" width="300" height="300" />
  <h2>Building the Future of Pacific Island Web3 Technology</h2>
  <p><em>Established 2025</em></p>
  <hr />
  <p><strong>"If we take care of our own, they will take care of us"</strong></p>
</div>

## Latest Updates (May 2025)

**Now with multi-network support for Linea, RootStock, and Arbitrum!**

### Arbitrum Deployment

| Contract | Address |
|----------|---------|
| ArbitrumTokenAdapter | 0x80d3c57b95a2fca3900f3EAC71196Bf133aaa517 |
| PasifikaArbitrumNode | 0xc79C57a047AD9B45B70D85000e9412C61f8fE336 |
| PasifikaTreasury | 0x96F1C4fE633bD7fE6DeB30411979bE3d0e2246b4 |
| PasifikaMembership | 0x80d3c57b95a2fca3900f3EAC71196Bf133aaa517 |
| PasifikaMoneyTransfer | 0x80d3c57b95a2fca3900f3EAC71196Bf133aaa517 |

### Linea & RootStock

Ready for deployment with network-specific scripts. See the [Multi-Network Deployment](#multi-network-deployment) section.

All contract addresses and ABIs are saved in the frontend directory with network-specific identifiers for easy integration.

## Pacific Values in Digital Form

At the heart of Pasifika Web3 Tech Hub is a philosophical principle that has guided Pacific Island communities for generations: **"If we take care of our own, they will take care of us."** This powerful concept of reciprocity and community care isn't just a nice sentiment, it's the architectural blueprint for our entire system.

EVM Compatible networks, with their focus on decentralization, community governance, and shared prosperity, provide the perfect technological expression of these Pacific values. When we examined various blockchain platforms, those supporting EVM compatibility aligned naturally with our cultural ethos while enabling cross-chain interoperability.

## Technical Advantages of Our Interoperability Approach

Our Pasifika Exchange operates across three complementary EVM Compatible chains: Linea, RSK (Rootstock), and Arbitrum. This wasn't a random selection, but a deliberate strategy to leverage the unique strengths of each while ensuring seamless interoperability for the first dedicated digital asset exchange for Pacific Islands:

### Linea: Scaling With Zero Knowledge
Linea's zkEVM Layer-2 technology dramatically reduces transaction costs while maintaining robust EVM compatibility and security. For communities where every fraction of a cent matters, this efficiency is crucial for financial inclusion.

### RSK: Bitcoin Integration with Smart Contracts
As a Bitcoin sidechain, RSK allows us to work with RBTC (Bitcoin on RSK) while leveraging the programmability of smart contracts. Our treasury was initially seeded with 27,281 RIF tokens received from the RSK Hactivator program, showcasing the real-world support this technology brings to Pacific innovation.

### Arbitrum: Optimistic Rollups for Scalability
Arbitrum's optimistic rollup technology provides exceptional throughput capabilities and security inherited from Ethereum, expanding trading options available to Pacific Islanders through the Pasifika Exchange.

## Building the First Pacific Islands Exchange

The technical architecture of our platform directly implements our community values through smart contracts and exchange functionality:

- **Exchange Features**: Our platform offers token swapping, liquidity provision, and cross-chain trading capabilities specifically designed for Pacific Island users and their unique needs.

- **Tiered Membership System**: We've created a simplified 3-tier structure (Guest, Member, Node Operator) with graduated fee structures (1%, 0.5%, 0.25%) that reward deeper community involvement with reduced trading fees.

- **Transparent Fund Management**: Our Pasifika Treasury contract enables transparent, secure management of exchange funds with multi-signature controls and clearly defined allocation processes.

## Beyond the Technology: Cultural Significance

While the technical implementations are impressive, what truly sets our approach apart is how these EVM Compatible technologies allow us to encode Pacific Island cultural values into digital infrastructure while enabling seamless interaction across multiple blockchain networks:

- **Reciprocity**: Just as traditional Pacific economies function on gift giving and mutual support, our profit sharing mechanism ensures value flows back to community members.

- **Shared Stewardship**: The graduated fee structure mirrors traditional systems where those with greater responsibility to the community receive greater benefits.

- **Accessibility**: By keeping fees low through Layer 2 scaling solutions, we ensure that participation remains accessible to all community members, regardless of economic status.

## Multi-Network Platform Overview

The Pasifika backend is a decentralized physical infrastructure network (DePIN) designed for Pacific Island communities. This implementation supports multiple networks:

- **Arbitrum**: Ethereum Layer-2 scaling solution with low gas fees
- **Linea**: Ethereum Layer-2 zkEVM for high throughput and security
- **RootStock (RSK)**: Bitcoin sidechain with smart contract capabilities

This multi-network approach provides flexibility, resilience, and increased accessibility for Pacific Island communities.

## Pasifika Annual Profit-Sharing Event

Inspired by our philosophy and the Bitcoin halving event, we've implemented the **Pasifika Annual Profit-Sharing Event** across all networks:

- **Equal Distribution**: 50% of all profits incurred within the Pasifika Treasury are distributed equally to all eligible registered members
- **Pasifika Financial Year**: Runs from December 27 (after Boxing Day) to December 24 (Christmas Eve)
- **Network-Specific Treasury**: Each network has its own treasury (initially seeded with ETH on Arbitrum/Linea, and with RIF/RBTC on RootStock)
- **Fully On-Chain**: All distributions are recorded on the respective blockchains, ensuring transparency and fairness
- **Eligibility Requirements**: Members must complete at least 100 transactions AND have a transaction volume of at least 1 ETH (or equivalent) during the financial year to qualify for profit sharing

This event exemplifies our commitment to community wealth-sharing and ensuring that the benefits of technology reach all active members of our ecosystem, while encouraging platform participation.

## Technical Specifications

- **Blockchains**:
  - Arbitrum - EVM Compatible Layer 2 scaling solution (ETH)
  - **Linea** - Layer 2 zkEVM with EVM Compatibility (ETH)
  - **RootStock** - EVM Compatible Bitcoin sidechain (RBTC)
- **Development Framework:** Foundry
- **Solidity Version:** 0.8.19 and 0.8.20
- **OpenZeppelin:** v5.3.0

## Cross-Chain Components

The backend consists of interoperable implementations for each supported blockchain network:

### 3-Tier System

We've simplified our membership and fee structure to a 3-tier system:

1. **Tier 0: Guest** 
   - Default tier for all users
   - 1% fee on all transactions
   - No special requirements

2. **Tier 1: Member**
   - 0.5% fee on all transactions (50% discount)
   - Requires membership (0.005 ETH on Arbitrum/Linea, 0.0001 RBTC on RootStock)

3. **Tier 2: Member Node Operator**
   - 0.25% fee on all transactions (75% discount)
   - Requires operating a validator node on the network

## Smart Contract System

The smart contract system leverages the native assets of the Arbitrum network:

### Network-Specific Adapters

- **ArbitrumTokenAdapter**: Implementation for Arbitrum using ETH
- **LineaTokenAdapter**: Implementation for Linea using ETH
- **RootstockTokenAdapter**: Implementation for RootStock using RBTC

Each adapter handles:
  - User tier management
  - Fee calculation based on tier level
  - Tier verification
  - Network-specific token operations

### Network Node Contracts

- **PasifikaArbitrumNode**: Node management for Arbitrum
- **PasifikaLineaNode**: Node management for Linea
- **PasifikaRootstockNode**: Node management for RootStock

Each node contract provides:
  - Node registration and activation
  - Staking mechanism using native tokens (ETH/RBTC)
  - Validator status tracking
  - Role-based access control

### Core Smart Contracts (Cross-Chain Interoperability)

- **PasifikaMembership Contract**: Membership management with:
  - Network-adaptive membership registration (0.005 ETH on Arbitrum/Linea, 0.0001 RBTC on RootStock)
  - Annual profit-sharing distribution of native tokens to eligible members
  - Transaction tracking for profit sharing eligibility
  - Financial year calculations
  - Member verification

- **PasifikaMoneyTransfer Contract**: Cross-network money transfer with:
  - Fee calculation based on user tier
  - Integration with network-specific token adapters
  - Support for native token transfers (ETH/RBTC)
  - Secure transaction handling

- **PasifikaTreasury Contract**: Multi-signature treasury management with:
  - Budget categories and allocations
  - Spending proposals and approvals
  - Fund recovery mechanisms
  - Native token management for profit-sharing events (ETH/RBTC)
  - Cross-network fund management

### Membership System

Our membership system is designed to provide clear benefits to platform participants:

1. **Transaction Fee Discounts**:
   - Members receive 50% off transaction fees
   - Node operators receive 75% off transaction fees

2. **Annual Profit Sharing**:
   - Eligible members receive an equal share of 50% of treasury profits
   - Distribution happens at the end of the Pasifika Financial Year

3. **Exchange Benefits**:
   - Members gain access to enhanced trading features
   - Node operators receive priority access to exchange services

### Deployment Process

The deployment process is streamlined with our comprehensive deployment script and Foundry's powerful toolkit:

1. **Setup**:
   ```bash
   $ forge build
   ```

2. **Testing**:
   ```bash
   $ forge test
   ```

3. **Multi-Network Deployment**:

   Our new deployment system supports flexible deployment options across multiple networks:

   ```bash
   # Deploy all contracts to a specific network
   $ ./deploy/network-deploy.sh arbitrum all
   $ ./deploy/network-deploy.sh linea all
   $ ./deploy/network-deploy.sh rootstock all

   # Deploy individual contracts to a specific network
   $ ./deploy/network-deploy.sh arbitrum treasury
   $ ./deploy/network-deploy.sh linea membership
   $ ./deploy/network-deploy.sh rootstock money-transfer
   ```

   Each network has its own deployment script and environment configuration:
   
   ```bash
   # Network-specific deployment scripts
   ./deploy/arbitrum-deploy.sh
   ./deploy/linea-deploy.sh
   ./deploy/rootstock-deploy.sh
   
   # Network-specific environment files
   .env.arbitrum
   .env.linea
   .env.rootstock
   ```

4. **Configuration**:
   
   Each network deployment script:
   - Saves all contract addresses to network-specific JSON files in the frontend directory (e.g., `PasifikaTreasury_linea.json`)
   - Updates environment variables automatically
   - Creates comprehensive deployment logs
   - Configures network-specific parameters

For testnet deployments, we use network-specific environment files (`.env.linea`, `.env.rootstock`, `.env.arbitrum`) with Foundry's keystore for secure wallet management.

### Post-Deployment Configuration

After deployment, the admin must perform the following steps to complete the integration:

1. Add PasifikaMembership as a fee collector in PasifikaTreasury
2. Add PasifikaMoneyTransfer as a fee collector in PasifikaTreasury
3. Initialize the Treasury connection in PasifikaMoneyTransfer
4. Set appropriate fee percentages
5. Connect contracts together by setting references

## Security and Transparency

Our contracts implement best practices for security:

- OpenZeppelin v5.3.0 libraries for access control, pausability, and reentrancy protection
- Multi-signature requirements for treasury operations
- Role-based access control for administrative functions
- Fee collection mechanisms with transparent allocation
- Secure keystore management for deployments
- Network-specific security considerations
- Cross-network contract interaction safeguards

## Multi-Network Frontend Integration

Our frontend provides seamless support for multiple networks:

- **Network Detection**: Automatically detects the current blockchain network
- **Cross-Chain Switching**: Allows users to seamlessly switch between supported EVM Compatible networks
- **Contract Loading**: Dynamically loads the appropriate contract addresses and ABIs across chains
- **Unified Interface**: Consistent UX across all blockchain networks with full interoperability

The contract loader utility (`deployed_contracts/contract-loader.js`) provides:

- Network-specific contract address resolution
- ABI loading for each network
- Helper functions for network switching
- Utility for creating web3 contract instances

Example usage:

```javascript
// Import the utilities
import { 
  getContractAddress, 
  getNetworkContracts,
  switchNetwork 
} from '../deployed_contracts/contract-loader';

// Get a specific contract address on a specific network
const treasuryAddress = await getContractAddress('PasifikaTreasury', 'linea');

// Get all contracts deployed on RootStock
const rskContracts = await getNetworkContracts('rootstock');

// Switch to Linea network
await switchNetwork(web3.currentProvider, 'linea');
```

We also provide a React hook (`useMultiNetworkContracts`) for easy integration in React applications.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
