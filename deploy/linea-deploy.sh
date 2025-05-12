#!/bin/bash
# Linea Deployment Script for Pasifika contracts
# Supports deployment of all contracts or individual contracts in the correct order

# Load environment variables from .env file
if [ -f .env.linea ]; then
    echo "Loading configuration from .env.linea file..."
    set -a
    source .env.linea
    set +a
elif [ -f .env ]; then
    echo "Loading configuration from .env file..."
    set -a
    source .env
    set +a
else
    echo "Error: .env or .env.linea file not found. Please create one with required variables."
    echo "Required variables: WALLET_ALIAS, FEE_RECIPIENT, TREASURY_WALLET"
    echo "See .env.linea for a template"
    exit 1
fi

# Choose network (testnet or mainnet)
LINEA_NETWORK=${LINEA_NETWORK:-"testnet"}  # Default to testnet, can be overridden in .env

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
if ! cast wallet list 2>/dev/null | grep -q "$WALLET_ALIAS"; then
    echo "Error: Wallet with alias '$WALLET_ALIAS' not found in Foundry keystore"
    echo "Create it with: cast wallet import --interactive $WALLET_ALIAS"
    exit 1
fi

# Get wallet address from alias
WALLET_ADDRESS=$(cast wallet address "$WALLET_ALIAS" 2>/dev/null || echo "Unknown")
echo "Using wallet: $WALLET_ALIAS ($WALLET_ADDRESS)"

# RPC URLs
TESTNET_RPC_URL=${RPC_URL:-"https://rpc.goerli.linea.build"}
MAINNET_RPC_URL=${LINEA_MAINNET_RPC_URL:-"https://rpc.linea.build"}

# Set active RPC URL based on network
if [ "$LINEA_NETWORK" = "mainnet" ]; then
    ACTIVE_RPC_URL=$MAINNET_RPC_URL
    CHAIN_ID=59144
    EXPLORER_URL="https://lineascan.build"
    NETWORK_NAME="Linea Mainnet"
    echo "Configured for Linea MAINNET"
else
    ACTIVE_RPC_URL=$TESTNET_RPC_URL
    CHAIN_ID=59140
    EXPLORER_URL="https://goerli.lineascan.build"
    NETWORK_NAME="Linea Testnet"
    echo "Configured for Linea TESTNET"
fi

# Define frontend contracts directory
FE_DIR="/home/user/Documents/pasifika-web3-tech-hub/pasifika-web3-fe/deployed_contracts"
# Create frontend directory if it doesn't exist
mkdir -p "$FE_DIR"

# Create deployments directory for logs
DEPLOY_DIR="deployments/linea-$LINEA_NETWORK"
mkdir -p $DEPLOY_DIR

# Log file for deployments
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$DEPLOY_DIR/deployment-$TIMESTAMP.log"
# Start logging
echo "Pasifika Linea Deployment Log - $(date)" > $LOG_FILE
echo "Network: $NETWORK_NAME (Chain ID: $CHAIN_ID)" >> $LOG_FILE
echo "Wallet: $WALLET_ALIAS ($WALLET_ADDRESS)" >> $LOG_FILE
echo "----------------------------------------" >> $LOG_FILE

# Check if we're in simulation mode (no actual transactions or network needed)
SIMULATE=${SIMULATE:-"false"}

# Common deployment parameters
if [ "$SIMULATE" = "true" ]; then
    echo "Running in SIMULATION mode - no transactions will be sent"
    COMMON_DEPLOY_FLAGS="--sender $WALLET_ALIAS --sig $(date +%s) -vvv"
else
    COMMON_DEPLOY_FLAGS="--rpc-url $ACTIVE_RPC_URL --account $WALLET_ALIAS --broadcast -vvv"
fi

# Add verification if enabled
if [ "$VERIFY_CONTRACTS" = "true" ]; then
    if [ -z "$LINEASCAN_API_KEY" ]; then
        echo "Warning: VERIFY_CONTRACTS is true but LINEASCAN_API_KEY is not set"
        echo "Contract verification will be skipped"
    else
        COMMON_DEPLOY_FLAGS="$COMMON_DEPLOY_FLAGS --verify --etherscan-api-key $LINEASCAN_API_KEY"
        echo "Contract verification enabled"
    fi
fi

# Add gas parameters if provided
if [ ! -z "$GAS_PRICE" ]; then
    COMMON_DEPLOY_FLAGS="$COMMON_DEPLOY_FLAGS --gas-price $GAS_PRICE"
    echo "Using custom gas price: $GAS_PRICE"
fi

if [ ! -z "$GAS_LIMIT" ]; then
    COMMON_DEPLOY_FLAGS="$COMMON_DEPLOY_FLAGS --gas-limit $GAS_LIMIT"
    echo "Using custom gas limit: $GAS_LIMIT"
fi

# Display available deployment options
show_help() {
    echo "Pasifika Linea Deployment Script"
    echo ""
    echo "Usage: $0 [option]"
    echo ""
    echo "Options:"
    echo "  all             Deploy all contracts in the correct order"
    echo "  token-adapter   Deploy LineaTokenAdapter only"
    echo "  node            Deploy PasifikaLineaNode only"
    echo "  treasury        Deploy PasifikaTreasury only"
    echo "  membership      Deploy PasifikaMembership only"
    echo "  money-transfer  Deploy PasifikaMoneyTransfer only"
    echo "  help            Show this help message"
    echo ""
    echo "Example: $0 all"
    echo "Example: $0 treasury"
}

# Function to create individual JSON file for a contract
save_contract_json() {
    local contract_name=$1
    local address=$2
    local name_override=$3
    local file_name=${name_override:-$contract_name}
    local json_file="$FE_DIR/${file_name}_linea.json"
    
    echo "Saving contract address to $json_file"
    
    # Create JSON file
    cat > "$json_file" << EOF
{
  "network": "linea",
  "chainId": $CHAIN_ID,
  "name": "$contract_name",
  "address": "$address",
  "deployer": "$WALLET_ADDRESS",
  "deployedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "explorer": "$EXPLORER_URL/address/$address"
}
EOF
    
    echo "✅ Saved contract info to $json_file"
    
    # Also save ABI if we can find it
    local abi_file="out/${contract_name}.sol/${contract_name}.json"
    local target_abi="$FE_DIR/${file_name}_linea_ABI.json"
    
    if [ -f "$abi_file" ]; then
        cp "$abi_file" "$target_abi"
        echo "✅ Saved contract ABI to $target_abi"
        
        # Also save a network-agnostic version for backward compatibility
        cp "$abi_file" "$FE_DIR/${file_name}_ABI.json"
    fi
}

# Update environment variables
update_env_var() {
    local var_name=$1
    local value=$2
    local env_file=".env.linea"
    
    # If the variable already exists in the file, update it
    if grep -q "^$var_name=" "$env_file" 2>/dev/null; then
        sed -i "s|^$var_name=.*|$var_name=$value|" "$env_file"
    else
        # Otherwise, append it
        echo "$var_name=$value" >> "$env_file"
    fi
    
    echo "Updated $var_name in $env_file"
}

# Deploy LineaTokenAdapter
deploy_token_adapter() {
    echo "Deploying LineaTokenAdapter..."
    echo "Command: forge script script/LineaTokenAdapter.s.sol:LineaTokenAdapterScript $COMMON_DEPLOY_FLAGS"
    
    # Create temporary file to capture output
    local temp_log=$(mktemp)
    
    # Run deployment and capture output
    forge script script/LineaTokenAdapter.s.sol:LineaTokenAdapterScript $COMMON_DEPLOY_FLAGS | tee $temp_log
    
    # Extract address from output
    local address=$(grep -o "LineaTokenAdapter deployed at: 0x[a-fA-F0-9]\{40\}" $temp_log | tail -1 | cut -d ' ' -f 4)
    
    # Append to main log
    cat $temp_log >> $LOG_FILE
    rm $temp_log
    
    if [ ! -z "$address" ]; then
        echo "✅ LineaTokenAdapter deployed at: $address"
        update_env_var "LINEA_TOKEN_ADAPTER_ADDRESS" "$address"
        save_contract_json "LineaTokenAdapter" "$address"
        export LINEA_TOKEN_ADAPTER_ADDRESS=$address
        return 0
    else
        echo "❌ Failed to deploy LineaTokenAdapter"
        return 1
    fi
}

# Deploy PasifikaLineaNode
deploy_node() {
    echo "Deploying PasifikaLineaNode..."
    echo "Command: forge script script/PasifikaLineaNode.s.sol:PasifikaLineaNodeScript $COMMON_DEPLOY_FLAGS"
    
    # Create temporary file to capture output
    local temp_log=$(mktemp)
    
    # Run deployment and capture output
    forge script script/PasifikaLineaNode.s.sol:PasifikaLineaNodeScript $COMMON_DEPLOY_FLAGS | tee $temp_log
    
    # Extract address from output
    local address=$(grep -o "PasifikaLineaNode deployed to: 0x[a-fA-F0-9]\{40\}" $temp_log | cut -d ' ' -f 4)
    
    # Append to main log
    cat $temp_log >> $LOG_FILE
    rm $temp_log
    
    if [ ! -z "$address" ]; then
        echo "✅ PasifikaLineaNode deployed at: $address"
        update_env_var "LINEA_NODE_ADDRESS" "$address"
        update_env_var "PASIFIKA_LINEA_NODE_ADDRESS" "$address"
        save_contract_json "PasifikaLineaNode" "$address" "PasifikaLineaNode"
        export LINEA_NODE_ADDRESS=$address
        export PASIFIKA_LINEA_NODE_ADDRESS=$address
        return 0
    else
        echo "❌ Failed to deploy PasifikaLineaNode"
        return 1
    fi
}

# Deploy PasifikaTreasury
deploy_treasury() {
    echo "Deploying PasifikaTreasury..."
    echo "Command: forge script script/PasifikaTreasury.s.sol:PasifikaTreasuryScript $COMMON_DEPLOY_FLAGS"
    
    # Create temporary file to capture output
    local temp_log=$(mktemp)
    
    # Run deployment and capture output
    forge script script/PasifikaTreasury.s.sol:PasifikaTreasuryScript $COMMON_DEPLOY_FLAGS | tee $temp_log
    
    # Extract address from output
    local address=$(grep -o "PasifikaTreasury deployed at: 0x[a-fA-F0-9]\{40\}" $temp_log | tail -1 | cut -d ' ' -f 4)
    
    # Append to main log
    cat $temp_log >> $LOG_FILE
    rm $temp_log
    
    if [ ! -z "$address" ]; then
        echo "✅ PasifikaTreasury deployed at: $address"
        update_env_var "LINEA_TREASURY_ADDRESS" "$address"
        update_env_var "PASIFIKA_TREASURY_ADDRESS" "$address"
        save_contract_json "PasifikaTreasury" "$address" "PasifikaTreasury"
        export LINEA_TREASURY_ADDRESS=$address
        export PASIFIKA_TREASURY_ADDRESS=$address
        return 0
    else
        echo "❌ Failed to deploy PasifikaTreasury"
        return 1
    fi
}

# Deploy PasifikaMembership
deploy_membership() {
    if [ -z "$LINEA_TREASURY_ADDRESS" ] && [ -z "$PASIFIKA_TREASURY_ADDRESS" ]; then
        echo "❌ Treasury address not found. Please deploy PasifikaTreasury first."
        return 1
    fi
    
    treasury_address=${LINEA_TREASURY_ADDRESS:-$PASIFIKA_TREASURY_ADDRESS}

    echo "Deploying PasifikaMembership..."
    echo "- Treasury: ${treasury_address}"
    echo "Command: forge script script/PasifikaMembership.s.sol:PasifikaMembershipScript $COMMON_DEPLOY_FLAGS"
    
    # Create temporary file to capture output
    local temp_log=$(mktemp)
    
    # Run deployment and capture output
    forge script script/PasifikaMembership.s.sol:PasifikaMembershipScript $COMMON_DEPLOY_FLAGS | tee $temp_log
    
    # Extract address from output
    local address=$(grep -o "PasifikaMembership deployed at: 0x[a-fA-F0-9]\{40\}" $temp_log | tail -1 | cut -d ' ' -f 4)
    
    # Append to main log
    cat $temp_log >> $LOG_FILE
    rm $temp_log
    
    if [ ! -z "$address" ]; then
        echo "✅ PasifikaMembership deployed at: $address"
        update_env_var "LINEA_MEMBERSHIP_ADDRESS" "$address"
        update_env_var "PASIFIKA_MEMBERSHIP_ADDRESS" "$address"
        save_contract_json "PasifikaMembership" "$address" "PasifikaMembership"
        export LINEA_MEMBERSHIP_ADDRESS=$address
        export PASIFIKA_MEMBERSHIP_ADDRESS=$address
        return 0
    else
        echo "❌ Failed to deploy PasifikaMembership"
        return 1
    fi
}

# Deploy PasifikaMoneyTransfer
deploy_money_transfer() {
    if [ -z "$LINEA_TOKEN_ADAPTER_ADDRESS" ]; then
        echo "❌ TokenAdapter address not found. Please deploy LineaTokenAdapter first."
        return 1
    fi

    if [ -z "$LINEA_TREASURY_ADDRESS" ] && [ -z "$PASIFIKA_TREASURY_ADDRESS" ]; then
        echo "❌ Treasury address not found. Please deploy PasifikaTreasury first."
        return 1
    fi
    
    treasury_address=${LINEA_TREASURY_ADDRESS:-$PASIFIKA_TREASURY_ADDRESS}

    echo "Deploying PasifikaMoneyTransfer..."
    echo "- Token Adapter: ${LINEA_TOKEN_ADAPTER_ADDRESS}"
    echo "- Treasury: ${treasury_address}"
    echo "Command: forge script script/PasifikaMoneyTransferLinea.s.sol:PasifikaMoneyTransferLineaScript $COMMON_DEPLOY_FLAGS"
    
    # Create temporary file to capture output
    local temp_log=$(mktemp)
    
    # Run deployment and capture output
    forge script script/PasifikaMoneyTransferLinea.s.sol:PasifikaMoneyTransferLineaScript $COMMON_DEPLOY_FLAGS | tee $temp_log
    
    # Extract address from output
    local address=$(grep -o "PasifikaMoneyTransfer deployed at: 0x[a-fA-F0-9]\{40\}" $temp_log | tail -1 | cut -d ' ' -f 4)
    
    # Append to main log
    cat $temp_log >> $LOG_FILE
    rm $temp_log
    
    if [ ! -z "$address" ]; then
        echo "✅ PasifikaMoneyTransfer deployed at: $address"
        update_env_var "LINEA_MONEY_TRANSFER_ADDRESS" "$address"
        update_env_var "PASIFIKA_MONEY_TRANSFER_ADDRESS" "$address"
        save_contract_json "PasifikaMoneyTransfer" "$address" "PasifikaMoneyTransfer"
        export LINEA_MONEY_TRANSFER_ADDRESS=$address
        export PASIFIKA_MONEY_TRANSFER_ADDRESS=$address
        return 0
    else
        echo "❌ Failed to deploy PasifikaMoneyTransfer"
        return 1
    fi
}

# Deploy all contracts in the correct order
deploy_all() {
    echo "Deploying all contracts in the correct order..."
    
    # Deploy network-specific token adapter first
    deploy_token_adapter
    if [ $? -ne 0 ]; then
        echo "❌ Failed to deploy LineaTokenAdapter. Aborting deployment."
        return 1
    fi
    
    # Deploy network-specific node contract
    deploy_node
    if [ $? -ne 0 ]; then
        echo "❌ Failed to deploy PasifikaLineaNode. Aborting deployment."
        return 1
    fi
    
    # Deploy the Treasury (core contract)
    
    # Deploy treasury
    deploy_treasury
    if [ $? -ne 0 ]; then
        echo "❌ Failed to deploy treasury. Aborting deployment."
        return 1
    fi
    
    # Deploy membership
    deploy_membership
    if [ $? -ne 0 ]; then
        echo "❌ Failed to deploy membership. Aborting deployment."
        return 1
    fi
    
    # Deploy money transfer
    deploy_money_transfer
    if [ $? -ne 0 ]; then
        echo "❌ Failed to deploy money transfer. Aborting deployment."
        return 1
    fi
    
    echo "✅ All contracts deployed successfully!"
    return 0
}

# Parse command line arguments
case "$1" in
    token-adapter)
        deploy_token_adapter
        ;;
    node)
        deploy_node
        ;;
    treasury)
        deploy_treasury
        ;;
    membership)
        deploy_membership
        ;;
    money-transfer)
        deploy_money_transfer
        ;;
    all)
        deploy_all
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac

echo "Deployment completed. Log saved to: $LOG_FILE"
