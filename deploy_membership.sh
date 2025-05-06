#!/bin/bash
# Script to deploy PasifikaMembership to Arbitrum Sepolia

echo "Loading Arbitrum Sepolia configuration..."
set -a
source .env.testnet
set +a

echo "Deploying PasifikaMembership using Treasury: $ARBITRUM_TREASURY_ADDRESS"

# Define frontend contracts directory
FRONTEND_DIR="/home/user/Documents/pasifika-web3-tech-hub/pasifika-web3-fe/deployed_contracts"

# Create frontend directory if it doesn't exist
mkdir -p $FRONTEND_DIR

# Deploy parameters without --via-ir to avoid stack issues
DEPLOY_PARAMS="--rpc-url $ARBITRUM_TESTNET_RPC_URL --account $WALLET_ALIAS --broadcast -vvv"

# Deploy PasifikaMembership
forge script script/PasifikaMembership.s.sol $DEPLOY_PARAMS | tee deployment.log

# Extract address from logs
MEMBERSHIP_ADDRESS=$(grep -o "PasifikaMembership deployed at: 0x[a-fA-F0-9]\{40\}" deployment.log | cut -d ' ' -f 4)

if [ ! -z "$MEMBERSHIP_ADDRESS" ]; then
  sed -i "s|^ARBITRUM_MEMBERSHIP_ADDRESS=.*|ARBITRUM_MEMBERSHIP_ADDRESS=$MEMBERSHIP_ADDRESS|" .env.testnet
  sed -i "s|^PASIFIKA_MEMBERSHIP_ADDRESS=.*|PASIFIKA_MEMBERSHIP_ADDRESS=$MEMBERSHIP_ADDRESS|" .env.testnet
  echo "✅ Updated Membership address: $MEMBERSHIP_ADDRESS"
  
  # Create JSON file with contract address for frontend
  echo "Creating JSON files with Membership contract address for frontend..."
  
  # Copy ABI to frontend
  if [ -f "out/PasifikaMembership.sol/PasifikaMembership.json" ]; then
    cp "out/PasifikaMembership.sol/PasifikaMembership.json" "$FRONTEND_DIR/PasifikaMembership_ABI.json"
    echo "✅ Copied PasifikaMembership ABI to frontend"
  else
    echo "⚠️ ABI file not found for PasifikaMembership"
  fi
  
  # Create contract info JSON
  cat > "$FRONTEND_DIR/PasifikaMembership_Address.json" << EOF
{
  "address": "$MEMBERSHIP_ADDRESS",
  "chainId": $CHAIN_ID,
  "network": "arbitrum-sepolia",
  "deployedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
  echo "✅ Created PasifikaMembership address file for frontend"
  
  # Update the combined contracts file if it exists
  if [ -f "$FRONTEND_DIR/contracts.json" ]; then
    # Use temporary file for sed in-place editing
    sed -i "s|\"PasifikaMembership\": \"[^\"]*\"|\"PasifikaMembership\": \"$MEMBERSHIP_ADDRESS\"|" "$FRONTEND_DIR/contracts.json"
    echo "✅ Updated combined contracts.json with PasifikaMembership address"
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
    "PasifikaMembership": "$MEMBERSHIP_ADDRESS",
    "PasifikaTreasury": "$ARBITRUM_TREASURY_ADDRESS",
    "PasifikaMoneyTransfer": "$ARBITRUM_MONEY_TRANSFER_ADDRESS",
    "ArbitrumTokenAdapter": "$ARBITRUM_TOKEN_ADAPTER_ADDRESS",
    "PasifikaArbitrumNode": "$ARBITRUM_NODE_ADDRESS"
  },
  "deployedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    echo "✅ Created combined contracts.json with PasifikaMembership address"
  fi
else
  echo "❌ Failed to extract Membership address"
fi

# Clean up
rm -f deployment.log

echo "Membership deployment completed!"
