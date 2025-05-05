#!/bin/bash
# Arbitrum Deployment Configuration

# Load environment variables from .env file
if [ -f .env.testnet ]; then
    echo "Loading configuration from .env.testnet file..."
    set -a
    source .env.testnet
    set +a
elif [ -f .env ]; then
    echo "Loading configuration from .env file..."
    set -a
    source .env
    set +a
else
    echo "Error: .env or .env.testnet file not found. Please create one with required variables."
    echo "Required variables: WALLET_ALIAS, FEE_RECIPIENT, TREASURY_WALLET"
    echo "See .env.testnet for a template"
    exit 1
fi

# Choose network (testnet or mainnet)
ARBITRUM_NETWORK=${ARBITRUM_NETWORK:-"testnet"}  # Default to testnet, can be overridden in .env

# Verify required environment variables are set
if [ -z "$WALLET_ALIAS" ]; then
    echo "Error: WALLET_ALIAS is not set in the environment"
    exit 1
fi

if [ -z "$FEE_RECIPIENT" ]; then
    echo "Error: FEE_RECIPIENT is not set in the environment"
    exit 1
fi

if [ -z "$TREASURY_WALLET" ]; then
    echo "Error: TREASURY_WALLET is not set in the environment"
    exit 1
fi

# Check if the wallet exists in the keystore
if ! cast wallet list | grep -q "$WALLET_ALIAS"; then
    echo "Error: Wallet with alias '$WALLET_ALIAS' not found in Foundry keystore"
    echo "Create it with: cast wallet import --interactive $WALLET_ALIAS"
    exit 1
fi

# Get wallet address from alias
WALLET_ADDRESS=$(cast wallet address "$WALLET_ALIAS")
echo "Using wallet: $WALLET_ALIAS ($WALLET_ADDRESS)"

# RPC URLs
TESTNET_RPC_URL=${RPC_URL:-"https://sepolia-rollup.arbitrum.io/rpc"}
MAINNET_RPC_URL=${ARBITRUM_MAINNET_RPC_URL:-"https://arb1.arbitrum.io/rpc"}

# Set active RPC URL based on network
if [ "$ARBITRUM_NETWORK" = "mainnet" ]; then
    ACTIVE_RPC_URL=$MAINNET_RPC_URL
    CHAIN_ID=42161
    EXPLORER_URL="https://arbiscan.io/"
    echo "Configured for ARBITRUM MAINNET"
else
    ACTIVE_RPC_URL=$TESTNET_RPC_URL
    CHAIN_ID=421614
    EXPLORER_URL="https://sepolia.arbiscan.io/"
    echo "Configured for ARBITRUM SEPOLIA TESTNET"
fi

# Set environment variables for the deployment script
export $(echo "FEE_RECIPIENT=$FEE_RECIPIENT")
export $(echo "TREASURY_WALLET=$TREASURY_WALLET")
export $(echo "WALLET_ADDRESS=$WALLET_ADDRESS")

# Build forge command with optional parameters
FORGE_CMD="forge script script/ArbitrumDeployment.s.sol:ArbitrumDeploymentScript --rpc-url $ACTIVE_RPC_URL --broadcast --account $WALLET_ALIAS"

# Add optional gas parameters if provided
if [ ! -z "$GAS_PRICE" ]; then
    FORGE_CMD="$FORGE_CMD --gas-price $GAS_PRICE"
    echo "Using custom gas price: $GAS_PRICE"
fi

if [ ! -z "$GAS_LIMIT" ]; then
    FORGE_CMD="$FORGE_CMD --gas-limit $GAS_LIMIT"
    echo "Using custom gas limit: $GAS_LIMIT"
fi

# Add verification if enabled
if [ "$VERIFY_CONTRACTS" = "true" ]; then
    if [ -z "$ARBISCAN_API_KEY" ]; then
        echo "Error: VERIFY_CONTRACTS is true but ARBISCAN_API_KEY is not set"
        exit 1
    fi
    FORGE_CMD="$FORGE_CMD --verify --verifier etherscan --etherscan-api-key $ARBISCAN_API_KEY"
    echo "Contract verification enabled"
fi

# Display configuration
echo "Deployment Configuration:"
echo "- Network: Arbitrum $ARBITRUM_NETWORK (Chain ID: $CHAIN_ID)"
echo "- Wallet Address: $WALLET_ADDRESS"
echo "- Wallet Alias: $WALLET_ALIAS" 
echo "- Fee Recipient: $FEE_RECIPIENT"
echo "- Treasury Wallet: $TREASURY_WALLET"
echo "- RPC URL: $ACTIVE_RPC_URL"
echo ""

# Create deployments directory
DEPLOY_DIR="deployments/arbitrum-$ARBITRUM_NETWORK"
mkdir -p $DEPLOY_DIR

# Start a dry run first to check for issues
echo "Performing dry run deployment (no transactions will be sent)..."
DRY_RUN_CMD="${FORGE_CMD/--broadcast/--ffi}" 
echo "Running: $DRY_RUN_CMD"
echo ""
eval $DRY_RUN_CMD

# Check if dry run was successful
if [ $? -ne 0 ]; then
    echo "Error: Dry run deployment failed. Please fix the issues before attempting a real deployment."
    exit 1
fi

# Ask for confirmation before proceeding with the actual deployment
read -p "Dry run successful. Do you want to proceed with the actual deployment? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
fi

# Run deployment
echo "Starting Pasifika deployment on Arbitrum $ARBITRUM_NETWORK..."
echo "Running: $FORGE_CMD"
echo ""
eval $FORGE_CMD

# Check if deployment was successful
if [ $? -ne 0 ]; then
    echo "Error: Deployment failed"
    exit 1
fi

# Save deployment addresses to file
echo "Saving deployment addresses..."
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
ADDRESSES_FILE="$DEPLOY_DIR/deployment-addresses-$TIMESTAMP.txt"

echo "Deployment Addresses (Arbitrum $ARBITRUM_NETWORK) - $(date)" > $ADDRESSES_FILE
echo "TokenAdapter: $TOKEN_ADAPTER_ADDRESS" >> $ADDRESSES_FILE
echo "Treasury: $TREASURY_ADDRESS" >> $ADDRESSES_FILE
echo "Membership: $MEMBERSHIP_ADDRESS" >> $ADDRESSES_FILE
echo "NFT: $NFT_ADDRESS" >> $ADDRESSES_FILE
echo "Marketplace: $MARKETPLACE_ADDRESS" >> $ADDRESSES_FILE
echo "MoneyTransfer: $MONEY_TRANSFER_ADDRESS" >> $ADDRESSES_FILE

# Create JSON format for frontend integration
JSON_FILE="$DEPLOY_DIR/deployment-addresses-$TIMESTAMP.json"
FE_DIR="/home/user/Documents/pasifika-web3-tech-hub/pasifika-web3-fe/deployed_contracts"
FE_JSON_FILE="$FE_DIR/arbitrum-deployment-addresses.json"

# Create frontend directory if it doesn't exist
mkdir -p "$FE_DIR"

# Create JSON content
JSON_CONTENT=$(cat << EOL
{
  "network": "arbitrum-$ARBITRUM_NETWORK",
  "chainId": $CHAIN_ID,
  "timestamp": "$(date -Iseconds)",
  "deployedBy": "$WALLET_ADDRESS",
  "contracts": {
    "tokenAdapter": "$TOKEN_ADAPTER_ADDRESS",
    "treasury": "$TREASURY_ADDRESS",
    "membership": "$MEMBERSHIP_ADDRESS",
    "nft": "$NFT_ADDRESS",
    "marketplace": "$MARKETPLACE_ADDRESS",
    "moneyTransfer": "$MONEY_TRANSFER_ADDRESS"
  }
}
EOL
)

# Save to deployment directory
echo "$JSON_CONTENT" > "$JSON_FILE"

# Save to frontend directory
echo "$JSON_CONTENT" > "$FE_JSON_FILE"

echo "Deployment complete!"
echo "Addresses saved to:"
echo "- Text format: $ADDRESSES_FILE"
echo "- JSON format: $JSON_FILE"
echo "- Frontend JSON: $FE_JSON_FILE"
