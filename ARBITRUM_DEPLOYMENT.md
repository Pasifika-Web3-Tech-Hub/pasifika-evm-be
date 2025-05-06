# Pasifika Web3 - Arbitrum Deployment Guide

This guide provides step-by-step instructions for deploying the Pasifika contracts to the Arbitrum network.

## Prerequisites

1. Make sure you have Foundry installed and updated to the latest version:
   ```bash
   foundryup
   ```

2. Create a `.env` file by copying the example file:
   ```bash
   cp .env.example .env
   ```

3. Fill in your `.env` file with the appropriate values:
   - `PRIVATE_KEY`: Your deployer wallet's private key
   - `ARBITRUM_RPC_URL`: URL for the Arbitrum network (mainnet or testnet)
   - `FEE_RECIPIENT`: Address that will receive marketplace fees
   - `TREASURY_WALLET`: Address for treasury operations
   - `ARBISCAN_API_KEY`: Your Arbiscan API key (for contract verification)

## Deployment Options

### Option 1: Deploy All Contracts Together

Use the comprehensive deployment script to deploy all contracts at once:

```bash
forge script script/ArbitrumDeployment.s.sol --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
```

This script will:
1. Deploy ArbitrumTokenAdapter
2. Deploy PasifikaArbitrumNode
3. Deploy PasifikaTreasury
4. Create default funds in Treasury
5. Deploy PasifikaMembership
6. Deploy PasifikaNFT
7. Deploy PasifikaMoneyTransfer
8. Deploy PasifikaMarketplace
9. Configure all the connections between contracts

### Option 2: Deploy Contracts Individually

#### 1. Deploy PasifikaTreasury

```bash
forge script script/PasifikaTreasury.s.sol --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
```

Set the deployed address in your `.env` file:
```
ARBITRUM_TREASURY_ADDRESS=0x...
```

#### 2. Deploy PasifikaMembership

```bash
forge script script/PasifikaMembership.s.sol --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
```

Set the deployed address in your `.env` file:
```
ARBITRUM_MEMBERSHIP_ADDRESS=0x...
```

#### 3. Deploy PasifikaMoneyTransfer

```bash
forge script script/PasifikaMoneyTransfer.s.sol --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
```

Set the deployed address in your `.env` file:
```
ARBITRUM_MONEY_TRANSFER_ADDRESS=0x...
```

#### 4. Deploy Other Contracts

Continue with the deployment of any other contracts as needed.

## Post-Deployment Verification

After deployment, verify that all contracts are working correctly:

1. Check contract integrations:
   ```bash
   cast call $ARBITRUM_MONEY_TRANSFER_ADDRESS "membershipContract()" --rpc-url $ARBITRUM_RPC_URL
   ```

2. Verify fee configurations:
   ```bash
   cast call $ARBITRUM_MONEY_TRANSFER_ADDRESS "baseFeePercent()" --rpc-url $ARBITRUM_RPC_URL
   cast call $ARBITRUM_MONEY_TRANSFER_ADDRESS "memberFeePercent()" --rpc-url $ARBITRUM_RPC_URL
   cast call $ARBITRUM_MONEY_TRANSFER_ADDRESS "validatorFeePercent()" --rpc-url $ARBITRUM_RPC_URL
   ```

3. Check treasury funds:
   ```bash
   cast call $ARBITRUM_TREASURY_ADDRESS "getTotalBalance()" --rpc-url $ARBITRUM_RPC_URL
   ```

## Running Tests

### Local Testing

To run tests in a local environment:

```bash
forge test
```

### Forked Testing

To run tests against a fork of the Arbitrum network:

```bash
forge test --fork-url $ARBITRUM_RPC_URL
```

## Common Issues and Solutions

1. **Contract Verification Fails**: If contract verification fails, try manually verifying through Arbiscan using the flattened contract:
   ```bash
   forge flatten src/PasifikaMoneyTransfer.sol > PasifikaMoneyTransfer_flat.sol
   ```

2. **Gas Estimation Errors**: Arbitrum may require different gas settings. Try adding `--legacy` flag for transactions:
   ```bash
   forge script script/ArbitrumDeployment.s.sol --rpc-url $ARBITRUM_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify --legacy
   ```

3. **Arbitrum Node Connectivity**: If experiencing RPC issues, try an alternative RPC provider or increase timeout settings.

## Contract Addresses

After deployment, update the following section with your deployed contract addresses:

- ArbitrumTokenAdapter: `0x...`
- PasifikaArbitrumNode: `0x...`
- PasifikaTreasury: `0x...`
- PasifikaMembership: `0x...`
- PasifikaMoneyTransfer: `0x...`
- PasifikaNFT: `0x...`
- PasifikaMarketplace: `0x...`

## Notes on Arbitrum Specifics

1. The contracts now use native ETH instead of RBTC
2. Gas fees on Arbitrum are typically lower than Ethereum mainnet
3. Membership fee is set to 0.0001 ETH to be appropriate for Arbitrum
4. All contracts handle native ETH transactions without any token wrappers

For any assistance, please contact the development team.
