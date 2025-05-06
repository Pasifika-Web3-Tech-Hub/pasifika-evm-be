#!/bin/bash
# Script to deploy Pasifika contracts to Arbitrum Sepolia testnet using Foundry keystore

# Load environment variables
echo "Loading Arbitrum Sepolia configuration..."
set -a
source .env.testnet
set +a

# Check if wallet alias is provided
if [ -z "$WALLET_ALIAS" ]; then
  echo "❌ WALLET_ALIAS not found in .env.testnet"
  echo "Please add your WALLET_ALIAS to .env.testnet and try again."
  exit 1
fi

echo "Using account: $WALLET_ALIAS from Foundry keystore"

# Check if Arbiscan API key is provided
if [ "$ARBISCAN_API_KEY" == "YourArbiscanApiKey" ]; then
  echo "⚠️ Using default ARBISCAN_API_KEY. Contract verification may fail."
  echo "Update ARBISCAN_API_KEY in .env.testnet for contract verification."
  VERIFY_FLAG=""
else
  VERIFY_FLAG="--verify"
fi

# Define frontend contracts directory
FRONTEND_DIR="/home/user/Documents/pasifika-web3-tech-hub/pasifika-web3-fe/deployed_contracts"

# Create frontend directory if it doesn't exist
mkdir -p $FRONTEND_DIR

# Common deployment parameters - removed --via-ir due to stack depth errors
DEPLOY_PARAMS="--rpc-url $ARBITRUM_TESTNET_RPC_URL --account $WALLET_ALIAS --broadcast $VERIFY_FLAG -vvv"

# Skip individual deployments and use combined ArbitrumDeployment script
echo "Deploying all contracts using ArbitrumDeployment script..."
echo "This will deploy all contracts in the correct order and set up integrations."
forge script script/ArbitrumDeployment.s.sol $DEPLOY_PARAMS | tee deployment.log

# Extract contract addresses from deployment logs
TOKEN_ADAPTER_ADDRESS=$(grep -o "ArbitrumTokenAdapter deployed at: 0x[a-fA-F0-9]\{40\}" deployment.log | cut -d ' ' -f 4)
NODE_ADDRESS=$(grep -o "PasifikaArbitrumNode deployed at: 0x[a-fA-F0-9]\{40\}" deployment.log | cut -d ' ' -f 4)
TREASURY_ADDRESS=$(grep -o "PasifikaTreasury deployed at: 0x[a-fA-F0-9]\{40\}" deployment.log | cut -d ' ' -f 4)
MEMBERSHIP_ADDRESS=$(grep -o "PasifikaMembership deployed at: 0x[a-fA-F0-9]\{40\}" deployment.log | cut -d ' ' -f 4)
MONEY_TRANSFER_ADDRESS=$(grep -o "PasifikaMoneyTransfer deployed at: 0x[a-fA-F0-9]\{40\}" deployment.log | cut -d ' ' -f 4)

# Update .env.testnet with the deployed addresses
if [ ! -z "$TREASURY_ADDRESS" ]; then
  sed -i "s|^ARBITRUM_TREASURY_ADDRESS=.*|ARBITRUM_TREASURY_ADDRESS=$TREASURY_ADDRESS|" .env.testnet
  sed -i "s|^PASIFIKA_TREASURY_ADDRESS=.*|PASIFIKA_TREASURY_ADDRESS=$TREASURY_ADDRESS|" .env.testnet
  echo "✅ Updated Treasury address: $TREASURY_ADDRESS"
fi

if [ ! -z "$MEMBERSHIP_ADDRESS" ]; then
  sed -i "s|^ARBITRUM_MEMBERSHIP_ADDRESS=.*|ARBITRUM_MEMBERSHIP_ADDRESS=$MEMBERSHIP_ADDRESS|" .env.testnet
  sed -i "s|^PASIFIKA_MEMBERSHIP_ADDRESS=.*|PASIFIKA_MEMBERSHIP_ADDRESS=$MEMBERSHIP_ADDRESS|" .env.testnet
  echo "✅ Updated Membership address: $MEMBERSHIP_ADDRESS"
fi

if [ ! -z "$TOKEN_ADAPTER_ADDRESS" ]; then
  sed -i "s|^ARBITRUM_TOKEN_ADAPTER_ADDRESS=.*|ARBITRUM_TOKEN_ADAPTER_ADDRESS=$TOKEN_ADAPTER_ADDRESS|" .env.testnet
  echo "✅ Updated TokenAdapter address: $TOKEN_ADAPTER_ADDRESS"
fi

if [ ! -z "$MONEY_TRANSFER_ADDRESS" ]; then
  sed -i "s|^ARBITRUM_MONEY_TRANSFER_ADDRESS=.*|ARBITRUM_MONEY_TRANSFER_ADDRESS=$MONEY_TRANSFER_ADDRESS|" .env.testnet
  sed -i "s|^PASIFIKA_MONEY_TRANSFER_ADDRESS=.*|PASIFIKA_MONEY_TRANSFER_ADDRESS=$MONEY_TRANSFER_ADDRESS|" .env.testnet
  echo "✅ Updated MoneyTransfer address: $MONEY_TRANSFER_ADDRESS"
fi

if [ ! -z "$NODE_ADDRESS" ]; then
  echo "ARBITRUM_NODE_ADDRESS=$NODE_ADDRESS" >> .env.testnet
  echo "✅ Updated Node address: $NODE_ADDRESS"
fi

# Create JSON file with contract addresses for the frontend
echo "Creating JSON files with contract addresses for frontend..."

# Function to copy ABI files to frontend
copy_abi_to_frontend() {
  local contract=$1
  local address=$2
  
  if [ ! -z "$address" ]; then
    # Copy ABI
    if [ -f "out/$contract.sol/$contract.json" ]; then
      cp "out/$contract.sol/$contract.json" "$FRONTEND_DIR/${contract}_ABI.json"
      echo "✅ Copied $contract ABI to frontend"
      
      # Create contract info JSON
      cat > "$FRONTEND_DIR/${contract}_Address.json" << EOF
{
  "address": "$address",
  "chainId": $CHAIN_ID,
  "network": "arbitrum-sepolia",
  "deployedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
      echo "✅ Created $contract address file for frontend"
    else
      echo "⚠️ ABI file not found for $contract"
    fi
  fi
}

# Create a network info file
cat > "$FRONTEND_DIR/network_info.json" << EOF
{
  "name": "Arbitrum Sepolia",
  "chainId": $CHAIN_ID,
  "rpcUrl": "$ARBITRUM_TESTNET_RPC_URL",
  "blockExplorer": "https://sepolia.arbiscan.io/",
  "deployedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

# Create a combined contracts file
cat > "$FRONTEND_DIR/contracts.json" << EOF
{
  "network": {
    "name": "Arbitrum Sepolia",
    "chainId": $CHAIN_ID,
    "rpcUrl": "$ARBITRUM_TESTNET_RPC_URL",
    "blockExplorer": "https://sepolia.arbiscan.io/"
  },
  "contracts": {
    "ArbitrumTokenAdapter": "$TOKEN_ADAPTER_ADDRESS",
    "PasifikaArbitrumNode": "$NODE_ADDRESS",
    "PasifikaTreasury": "$TREASURY_ADDRESS",
    "PasifikaMembership": "$MEMBERSHIP_ADDRESS",
    "PasifikaMoneyTransfer": "$MONEY_TRANSFER_ADDRESS"
  },
  "deployedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

# Copy ABIs and create address files
copy_abi_to_frontend "ArbitrumTokenAdapter" "$TOKEN_ADAPTER_ADDRESS"
copy_abi_to_frontend "PasifikaArbitrumNode" "$NODE_ADDRESS"
copy_abi_to_frontend "PasifikaTreasury" "$TREASURY_ADDRESS"
copy_abi_to_frontend "PasifikaMembership" "$MEMBERSHIP_ADDRESS"
copy_abi_to_frontend "PasifikaMoneyTransfer" "$MONEY_TRANSFER_ADDRESS"

# Clean up
rm -f deployment.log

echo "✅ Deployment to Arbitrum Sepolia completed!"
echo "Contract addresses have been updated in .env.testnet"
echo "Contract addresses and ABIs have been saved to $FRONTEND_DIR"
echo ""
echo "Deployed Contracts:"
echo "- Token Adapter: $TOKEN_ADAPTER_ADDRESS"
echo "- Node: $NODE_ADDRESS" 
echo "- Treasury: $TREASURY_ADDRESS"
echo "- Membership: $MEMBERSHIP_ADDRESS"
echo "- Money Transfer: $MONEY_TRANSFER_ADDRESS"
echo ""
echo "Next steps:"
echo "1. Update your frontend with these new contract addresses"
echo "2. Test the contracts on Arbitrum Sepolia to verify functionality"
echo "3. When ready, deploy to Arbitrum Mainnet by updating environment variables"
