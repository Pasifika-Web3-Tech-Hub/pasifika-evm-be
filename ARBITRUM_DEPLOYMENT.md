# Pasifika Web3 - Arbitrum Deployment Guide

This guide provides step-by-step instructions for deploying the Pasifika contracts to the Arbitrum network.

## Deployment Status

**May 2025 Update**: Successfully deployed to Arbitrum Sepolia testnet!

| Contract | Address |
|----------|---------|
| ArbitrumTokenAdapter | 0x80d3c57b95a2fca3900f3EAC71196Bf133aaa517 |
| PasifikaArbitrumNode | 0xc79C57a047AD9B45B70D85000e9412C61f8fE336 |
| PasifikaTreasury | 0x96F1C4fE633bD7fE6DeB30411979bE3d0e2246b4 |
| PasifikaMembership | 0x80d3c57b95a2fca3900f3EAC71196Bf133aaa517 |
| PasifikaMoneyTransfer | 0x80d3c57b95a2fca3900f3EAC71196Bf133aaa517 |

All contract addresses and ABIs are saved in the frontend directory for easy integration.

## Prerequisites

1. Make sure you have Foundry installed and updated to the latest version:
   ```bash
   foundryup
   ```

2. Create a `.env.testnet` file by copying the example file:
   ```bash
   cp .env.example .env.testnet
   ```

3. Setup your wallet using Foundry's secure keystore:
   ```bash
   cast wallet import --interactive pasifika-account
   ```
   
   This will prompt you to enter a password and your private key. The wallet will be stored securely in Foundry's keystore.

4. Fill in your `.env.testnet` file with the appropriate values:
   ```
   # Network Configuration
   ARBITRUM_NETWORK=testnet  # or "mainnet" for production
   RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
   ARBITRUM_MAINNET_RPC_URL=https://arb1.arbitrum.io/rpc
   
   # Wallet Configuration
   WALLET_ALIAS=pasifika-account
   
   # Application Configuration
   FEE_RECIPIENT=0xEd752dCE9f6c1Db35FeDABca445617A0d2B0b674
   TREASURY_WALLET=0x24B5e5e80825bBFb76591258C6D9F7C43aA72c50
   
   # Contract Verification
   VERIFY_CONTRACTS=true
   ARBISCAN_API_KEY=your_arbiscan_api_key
   ```

## Deployment Options

Our new `arbitrum-deploy.sh` script provides a flexible way to deploy contracts:

### Deploy All Contracts

To deploy all contracts in the correct dependency order:

```bash
./deploy/arbitrum-deploy.sh all
```

This will deploy:
1. ArbitrumTokenAdapter
2. PasifikaArbitrumNode
3. PasifikaTreasury
4. PasifikaMembership
5. PasifikaMoneyTransfer

### Deploy Individual Contracts

You can also deploy individual contracts as needed:

```bash
# Deploy the token adapter
./deploy/arbitrum-deploy.sh token-adapter

# Deploy the node contract
./deploy/arbitrum-deploy.sh node

# Deploy the treasury
./deploy/arbitrum-deploy.sh treasury

# Deploy the membership contract
./deploy/arbitrum-deploy.sh membership

# Deploy the money transfer contract
./deploy/arbitrum-deploy.sh money-transfer
```

The script automatically:
- Checks for required dependencies before deployment
- Saves contract addresses to individual JSON files in the frontend directory
- Copies ABI files to the frontend directory
- Updates environment variables in `.env.testnet`
- Creates detailed deployment logs

## Post-Deployment Configuration

After deploying the contracts, the admin must perform the following steps to complete the integration:

1. Add PasifikaMembership as a fee collector in PasifikaTreasury:
   ```solidity
   // Call from admin account
   treasury.addFeeCollector(membershipAddress);
   ```

2. Add PasifikaMoneyTransfer as a fee collector in PasifikaTreasury:
   ```solidity
   // Call from admin account
   treasury.addFeeCollector(moneyTransferAddress);
   ```

3. Initialize the Treasury connection in PasifikaMoneyTransfer:
   ```solidity
   // Call from admin account
   moneyTransfer.initializeTreasury();
   ```

4. Set appropriate fee percentages:
   ```solidity
   // Call from admin account
   moneyTransfer.setBaseFeePercent(100);     // 1%
   moneyTransfer.setMemberFeePercent(50);    // 0.5%
   moneyTransfer.setValidatorFeePercent(25); // 0.25%
   ```

5. Connect contracts together:
   ```solidity
   // Call from admin account
   moneyTransfer.setMembershipContract(membershipAddress);
   moneyTransfer.setNodeContract(nodeAddress);
   ```

## Frontend Integration

The deployment script automatically saves contract addresses and ABIs to the frontend directory:

```
/home/user/Documents/pasifika-web3-tech-hub/pasifika-web3-fe/deployed_contracts/
```

Each contract has:
- `ContractName.json` - Contains the contract address and network information
- `ContractName_ABI.json` - Contains the contract ABI for integration

## Troubleshooting

1. **Insufficient Funds Error**:
   - Make sure your wallet has enough ETH to cover the deployment costs
   - For Arbitrum Sepolia testnet, get ETH from a faucet

2. **Access Control Issues**:
   - These are expected during deployment and are handled by the post-deployment configuration
   - Only admins can perform certain operations like adding fee collectors

3. **Contract Verification Failure**:
   - Ensure your ARBISCAN_API_KEY is correctly set in .env.testnet
   - Check that the VERIFY_CONTRACTS flag is set to true

## Mainnet Deployment

For mainnet deployment, follow the same steps but update your `.env.testnet` file:

```
ARBITRUM_NETWORK=mainnet
RPC_URL=https://arb1.arbitrum.io/rpc
```

Ensure you have sufficient ETH in your wallet to cover deployment costs on mainnet.

## Contract Addresses Reference

Keep a record of all deployed contract addresses:

```
ArbitrumTokenAdapter: 0x80d3c57b95a2fca3900f3EAC71196Bf133aaa517
PasifikaArbitrumNode: 0xc79C57a047AD9B45B70D85000e9412C61f8fE336
PasifikaTreasury: 0x96F1C4fE633bD7fE6DeB30411979bE3d0e2246b4
PasifikaMembership: 0x80d3c57b95a2fca3900f3EAC71196Bf133aaa517
PasifikaMoneyTransfer: 0x80d3c57b95a2fca3900f3EAC71196Bf133aaa517
```

These addresses should match what's updated in your `.env.testnet` file and saved to the frontend directory.
