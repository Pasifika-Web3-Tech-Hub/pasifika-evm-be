#!/bin/bash
# Script to deploy PasifikaMoneyTransfer to Arbitrum Sepolia

echo "Loading Arbitrum Sepolia configuration..."
set -a
source .env.testnet
set +a

echo "Deploying PasifikaMoneyTransfer using:"
echo "- Treasury: $ARBITRUM_TREASURY_ADDRESS"
echo "- Membership: $ARBITRUM_MEMBERSHIP_ADDRESS"
echo "- TokenAdapter: $ARBITRUM_TOKEN_ADAPTER_ADDRESS"

# Define frontend contracts directory
FRONTEND_DIR="/home/user/Documents/pasifika-web3-tech-hub/pasifika-web3-fe/deployed_contracts"

# Create frontend directory if it doesn't exist
mkdir -p $FRONTEND_DIR

# Deploy parameters without --via-ir to avoid stack issues
DEPLOY_PARAMS="--rpc-url $ARBITRUM_TESTNET_RPC_URL --account $WALLET_ALIAS --broadcast -vvv"

# Deploy PasifikaMoneyTransfer
forge script script/PasifikaMoneyTransfer.s.sol $DEPLOY_PARAMS | tee deployment.log

# Extract address from logs
MONEY_TRANSFER_ADDRESS=$(grep -o "PasifikaMoneyTransfer deployed at: 0x[a-fA-F0-9]\{40\}" deployment.log | cut -d ' ' -f 4)

if [ ! -z "$MONEY_TRANSFER_ADDRESS" ]; then
  sed -i "s|^ARBITRUM_MONEY_TRANSFER_ADDRESS=.*|ARBITRUM_MONEY_TRANSFER_ADDRESS=$MONEY_TRANSFER_ADDRESS|" .env.testnet
  sed -i "s|^PASIFIKA_MONEY_TRANSFER_ADDRESS=.*|PASIFIKA_MONEY_TRANSFER_ADDRESS=$MONEY_TRANSFER_ADDRESS|" .env.testnet
  echo "✅ Updated MoneyTransfer address: $MONEY_TRANSFER_ADDRESS"
  
  # Create JSON file with contract address for frontend
  echo "Creating JSON files with MoneyTransfer contract address for frontend..."
  
  # Copy ABI to frontend
  if [ -f "out/PasifikaMoneyTransfer.sol/PasifikaMoneyTransfer.json" ]; then
    cp "out/PasifikaMoneyTransfer.sol/PasifikaMoneyTransfer.json" "$FRONTEND_DIR/PasifikaMoneyTransfer_ABI.json"
    echo "✅ Copied PasifikaMoneyTransfer ABI to frontend"
  else
    echo "⚠️ ABI file not found for PasifikaMoneyTransfer"
  fi
  
  # Create contract info JSON
  cat > "$FRONTEND_DIR/PasifikaMoneyTransfer_Address.json" << EOF
{
  "address": "$MONEY_TRANSFER_ADDRESS",
  "chainId": $CHAIN_ID,
  "network": "arbitrum-sepolia",
  "deployedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
  echo "✅ Created PasifikaMoneyTransfer address file for frontend"
  
  # Update the combined contracts file if it exists
  if [ -f "$FRONTEND_DIR/contracts.json" ]; then
    # Use temporary file for sed in-place editing
    sed -i "s|\"PasifikaMoneyTransfer\": \"[^\"]*\"|\"PasifikaMoneyTransfer\": \"$MONEY_TRANSFER_ADDRESS\"|" "$FRONTEND_DIR/contracts.json"
    echo "✅ Updated combined contracts.json with PasifikaMoneyTransfer address"
  else
    # Create a new combined contracts file
    cat > "$FRONTEND_DIR/contracts.json" << EOF
{
  "network": {
    "name": "Arbitrum Sepolia",
    "chainId": $CHAIN_ID,
    "rpcUrl": "$ARBITRUM_TESTNET_RPC_URL",
    "blockExplorer": "https://sepolia.arbiscan.io/"
  },
  "contracts": {
    "PasifikaMoneyTransfer": "$MONEY_TRANSFER_ADDRESS",
    "PasifikaMembership": "$ARBITRUM_MEMBERSHIP_ADDRESS",
    "PasifikaTreasury": "$ARBITRUM_TREASURY_ADDRESS",
    "ArbitrumTokenAdapter": "$ARBITRUM_TOKEN_ADAPTER_ADDRESS",
    "PasifikaArbitrumNode": "$ARBITRUM_NODE_ADDRESS"
  },
  "deployedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    echo "✅ Created combined contracts.json with PasifikaMoneyTransfer address"
  fi
else
  echo "❌ Failed to extract MoneyTransfer address"
fi

# Clean up
rm -f deployment.log

echo "MoneyTransfer deployment completed!"
