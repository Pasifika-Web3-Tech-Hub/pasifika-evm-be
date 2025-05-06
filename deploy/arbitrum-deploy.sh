#!/bin/bash
# Arbitrum Deployment Script for Pasifika contracts
# Supports deployment of all contracts or individual contracts in the correct order

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
if ! cast wallet list 2>/dev/null | grep -q "$WALLET_ALIAS"; then
    echo "Error: Wallet with alias '$WALLET_ALIAS' not found in Foundry keystore"
    echo "Create it with: cast wallet import --interactive $WALLET_ALIAS"
    exit 1
fi

# Get wallet address from alias
WALLET_ADDRESS=$(cast wallet address "$WALLET_ALIAS" 2>/dev/null || echo "Unknown")
echo "Using wallet: $WALLET_ALIAS ($WALLET_ADDRESS)"

# RPC URLs
TESTNET_RPC_URL=${RPC_URL:-"https://sepolia-rollup.arbitrum.io/rpc"}
MAINNET_RPC_URL=${ARBITRUM_MAINNET_RPC_URL:-"https://arb1.arbitrum.io/rpc"}

# Set active RPC URL based on network
if [ "$ARBITRUM_NETWORK" = "mainnet" ]; then
    ACTIVE_RPC_URL=$MAINNET_RPC_URL
    CHAIN_ID=42161
    EXPLORER_URL="https://arbiscan.io/"
    NETWORK_NAME="Arbitrum One"
    echo "Configured for ARBITRUM MAINNET"
else
    ACTIVE_RPC_URL=$TESTNET_RPC_URL
    CHAIN_ID=421614
    EXPLORER_URL="https://sepolia.arbiscan.io/"
    NETWORK_NAME="Arbitrum Sepolia"
    echo "Configured for ARBITRUM SEPOLIA TESTNET"
fi

# Define frontend contracts directory
FE_DIR="/home/user/Documents/pasifika-web3-tech-hub/pasifika-web3-fe/deployed_contracts"
# Create frontend directory if it doesn't exist
mkdir -p "$FE_DIR"

# Create deployments directory for logs
DEPLOY_DIR="deployments/arbitrum-$ARBITRUM_NETWORK"
mkdir -p $DEPLOY_DIR

# Log file for deployments
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$DEPLOY_DIR/deployment-$TIMESTAMP.log"
# Start logging
echo "Pasifika Arbitrum Deployment Log - $(date)" > $LOG_FILE
echo "Network: $NETWORK_NAME (Chain ID: $CHAIN_ID)" >> $LOG_FILE
echo "Wallet: $WALLET_ALIAS ($WALLET_ADDRESS)" >> $LOG_FILE
echo "----------------------------------------" >> $LOG_FILE

# Common deployment parameters
COMMON_DEPLOY_FLAGS="--rpc-url $ACTIVE_RPC_URL --account $WALLET_ALIAS --broadcast -vvv"

# Add verification if enabled
if [ "$VERIFY_CONTRACTS" = "true" ]; then
    if [ -z "$ARBISCAN_API_KEY" ]; then
        echo "Warning: VERIFY_CONTRACTS is true but ARBISCAN_API_KEY is not set"
        echo "Contract verification will be skipped"
    else
        COMMON_DEPLOY_FLAGS="$COMMON_DEPLOY_FLAGS --verify --etherscan-api-key $ARBISCAN_API_KEY"
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
    echo "Pasifika Arbitrum Deployment Script"
    echo ""
    echo "Usage: $0 [option]"
    echo ""
    echo "Options:"
    echo "  all             Deploy all contracts in the correct order"
    echo "  token-adapter   Deploy ArbitrumTokenAdapter only"
    echo "  node            Deploy PasifikaArbitrumNode only"
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
    local contract_address=$2
    local script_name=$3

    if [ -z "$contract_address" ]; then
        echo "Warning: No address provided for $contract_name"
        return
    fi

    # Create JSON content
    cat > "$FE_DIR/${contract_name}.json" << EOF
{
  "contractName": "${contract_name}",
  "address": "${contract_address}",
  "network": "${NETWORK_NAME}",
  "chainId": ${CHAIN_ID},
  "explorer": "${EXPLORER_URL}address/${contract_address}",
  "deployedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

    echo "✅ Created ${contract_name} address file: $FE_DIR/${contract_name}.json"
    
    # Copy the ABI file if it exists
    if [ -f "out/${script_name}.sol/${contract_name}.json" ]; then
        cp "out/${script_name}.sol/${contract_name}.json" "$FE_DIR/${contract_name}_ABI.json"
        echo "✅ Copied ${contract_name} ABI to: $FE_DIR/${contract_name}_ABI.json"
    else
        echo "Warning: ABI file not found for ${contract_name} (out/${script_name}.sol/${contract_name}.json)"
    fi
}

# Update environment variables
update_env_var() {
    local var_name=$1
    local value=$2
    
    if [ -z "$value" ]; then
        return
    fi
    
    # Update .env.testnet
    if [ -f .env.testnet ]; then
        if grep -q "^${var_name}=" .env.testnet; then
            sed -i "s|^${var_name}=.*|${var_name}=${value}|" .env.testnet
        else
            echo "${var_name}=${value}" >> .env.testnet
        fi
    fi
}

# Deploy ArbitrumTokenAdapter
deploy_token_adapter() {
    echo "Deploying ArbitrumTokenAdapter..."
    echo "Command: forge script script/ArbitrumDeployment.s.sol:ArbitrumDeploymentScript --rpc-url $ACTIVE_RPC_URL --account $WALLET_ALIAS --broadcast -vvv"
    
    # Create temporary file to capture output
    local temp_log=$(mktemp)
    
    # Run deployment and capture output
    forge script script/ArbitrumDeployment.s.sol:ArbitrumDeploymentScript $COMMON_DEPLOY_FLAGS | tee $temp_log
    
    # Extract address from output
    local address=$(grep -o "ArbitrumTokenAdapter deployed at: 0x[a-fA-F0-9]\{40\}" $temp_log | tail -1 | cut -d ' ' -f 4)
    
    # Append to main log
    cat $temp_log >> $LOG_FILE
    rm $temp_log
    
    if [ ! -z "$address" ]; then
        echo "✅ ArbitrumTokenAdapter deployed at: $address"
        update_env_var "ARBITRUM_TOKEN_ADAPTER_ADDRESS" "$address"
        save_contract_json "ArbitrumTokenAdapter" "$address" "ArbitrumDeployment"
        export ARBITRUM_TOKEN_ADAPTER_ADDRESS=$address
        return 0
    else
        echo "❌ Failed to deploy ArbitrumTokenAdapter"
        return 1
    fi
}

# Deploy PasifikaArbitrumNode
deploy_node() {
    echo "Deploying PasifikaArbitrumNode..."
    echo "Command: forge script script/ArbitrumDeployment.s.sol:ArbitrumDeploymentScript --rpc-url $ACTIVE_RPC_URL --account $WALLET_ALIAS --broadcast -vvv"
    
    # Create temporary file to capture output
    local temp_log=$(mktemp)
    
    # Run deployment and capture output
    forge script script/ArbitrumDeployment.s.sol:ArbitrumDeploymentScript $COMMON_DEPLOY_FLAGS | tee $temp_log
    
    # Extract address from output
    local address=$(grep -o "PasifikaArbitrumNode deployed at: 0x[a-fA-F0-9]\{40\}" $temp_log | tail -1 | cut -d ' ' -f 4)
    
    # Append to main log
    cat $temp_log >> $LOG_FILE
    rm $temp_log
    
    if [ ! -z "$address" ]; then
        echo "✅ PasifikaArbitrumNode deployed at: $address"
        update_env_var "ARBITRUM_NODE_ADDRESS" "$address"
        save_contract_json "PasifikaArbitrumNode" "$address" "ArbitrumDeployment"
        export ARBITRUM_NODE_ADDRESS=$address
        return 0
    else
        echo "❌ Failed to deploy PasifikaArbitrumNode"
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
        update_env_var "ARBITRUM_TREASURY_ADDRESS" "$address"
        update_env_var "PASIFIKA_TREASURY_ADDRESS" "$address"
        save_contract_json "PasifikaTreasury" "$address" "PasifikaTreasury"
        export ARBITRUM_TREASURY_ADDRESS=$address
        export PASIFIKA_TREASURY_ADDRESS=$address
        return 0
    else
        echo "❌ Failed to deploy PasifikaTreasury"
        return 1
    fi
}

# Deploy PasifikaMembership
deploy_membership() {
    if [ -z "$ARBITRUM_TREASURY_ADDRESS" ] && [ -z "$PASIFIKA_TREASURY_ADDRESS" ]; then
        echo "❌ Treasury address not found. Please deploy PasifikaTreasury first."
        return 1
    fi

    echo "Deploying PasifikaMembership using treasury: ${ARBITRUM_TREASURY_ADDRESS:-$PASIFIKA_TREASURY_ADDRESS}"
    echo "Command: forge script script/PasifikaMembershipAlias.s.sol:PasifikaMembershipAliasScript $COMMON_DEPLOY_FLAGS"
    
    # Create temporary file to capture output
    local temp_log=$(mktemp)
    
    # Run deployment and capture output
    forge script script/PasifikaMembershipAlias.s.sol:PasifikaMembershipAliasScript $COMMON_DEPLOY_FLAGS | tee $temp_log
    
    # Extract address from output
    local address=$(grep -o "PasifikaMembership deployed at: 0x[a-fA-F0-9]\{40\}" $temp_log | tail -1 | cut -d ' ' -f 4)
    
    # Append to main log
    cat $temp_log >> $LOG_FILE
    rm $temp_log
    
    if [ ! -z "$address" ]; then
        echo "✅ PasifikaMembership deployed at: $address"
        update_env_var "ARBITRUM_MEMBERSHIP_ADDRESS" "$address"
        update_env_var "PASIFIKA_MEMBERSHIP_ADDRESS" "$address"
        save_contract_json "PasifikaMembership" "$address" "PasifikaMembership"
        export ARBITRUM_MEMBERSHIP_ADDRESS=$address
        export PASIFIKA_MEMBERSHIP_ADDRESS=$address
        return 0
    else
        echo "❌ Failed to deploy PasifikaMembership"
        return 1
    fi
}

# Deploy PasifikaMoneyTransfer
deploy_money_transfer() {
    if [ -z "$ARBITRUM_TOKEN_ADAPTER_ADDRESS" ]; then
        echo "❌ TokenAdapter address not found. Please deploy ArbitrumTokenAdapter first."
        return 1
    fi

    if [ -z "$ARBITRUM_TREASURY_ADDRESS" ] && [ -z "$PASIFIKA_TREASURY_ADDRESS" ]; then
        echo "❌ Treasury address not found. Please deploy PasifikaTreasury first."
        return 1
    fi
    
    treasury_address=${ARBITRUM_TREASURY_ADDRESS:-$PASIFIKA_TREASURY_ADDRESS}

    echo "Deploying PasifikaMoneyTransfer..."
    echo "- Token Adapter: ${ARBITRUM_TOKEN_ADAPTER_ADDRESS}"
    echo "- Treasury: ${treasury_address}"
    echo "Command: forge script script/PasifikaMoneyTransferAlias.s.sol:PasifikaMoneyTransferAliasScript $COMMON_DEPLOY_FLAGS"
    
    # Create temporary file to capture output
    local temp_log=$(mktemp)
    
    # Run deployment and capture output
    forge script script/PasifikaMoneyTransferAlias.s.sol:PasifikaMoneyTransferAliasScript $COMMON_DEPLOY_FLAGS | tee $temp_log
    
    # Extract address from output
    local address=$(grep -o "PasifikaMoneyTransfer deployed at: 0x[a-fA-F0-9]\{40\}" $temp_log | tail -1 | cut -d ' ' -f 4)
    
    # Append to main log
    cat $temp_log >> $LOG_FILE
    rm $temp_log
    
    if [ ! -z "$address" ]; then
        echo "✅ PasifikaMoneyTransfer deployed at: $address"
        update_env_var "ARBITRUM_MONEY_TRANSFER_ADDRESS" "$address"
        update_env_var "PASIFIKA_MONEY_TRANSFER_ADDRESS" "$address"
        save_contract_json "PasifikaMoneyTransfer" "$address" "PasifikaMoneyTransfer"
        export ARBITRUM_MONEY_TRANSFER_ADDRESS=$address
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
    
    # Use the comprehensive deployment script if it exists
    if [ -f "script/ArbitrumDeployment.s.sol" ]; then
        echo "Using comprehensive ArbitrumDeployment script..."
        echo "Command: forge script script/ArbitrumDeployment.s.sol:ArbitrumDeploymentScript $COMMON_DEPLOY_FLAGS"
        
        # Create temporary file to capture output
        local temp_log=$(mktemp)
        
        # Run deployment and capture output
        forge script script/ArbitrumDeployment.s.sol:ArbitrumDeploymentScript $COMMON_DEPLOY_FLAGS | tee $temp_log
        
        # Extract addresses from output
        local token_adapter_address=$(grep -o "ArbitrumTokenAdapter deployed at: 0x[a-fA-F0-9]\{40\}" $temp_log | tail -1 | cut -d ' ' -f 4)
        local node_address=$(grep -o "PasifikaArbitrumNode deployed at: 0x[a-fA-F0-9]\{40\}" $temp_log | tail -1 | cut -d ' ' -f 4)
        local treasury_address=$(grep -o "PasifikaTreasury deployed at: 0x[a-fA-F0-9]\{40\}" $temp_log | tail -1 | cut -d ' ' -f 4)
        local membership_address=$(grep -o "PasifikaMembership deployed at: 0x[a-fA-F0-9]\{40\}" $temp_log | tail -1 | cut -d ' ' -f 4)
        local money_transfer_address=$(grep -o "PasifikaMoneyTransfer deployed at: 0x[a-fA-F0-9]\{40\}" $temp_log | tail -1 | cut -d ' ' -f 4)
        
        # Append to main log
        cat $temp_log >> $LOG_FILE
        rm $temp_log
        
        # Update environment variables and save JSON files
        if [ ! -z "$token_adapter_address" ]; then
            update_env_var "ARBITRUM_TOKEN_ADAPTER_ADDRESS" "$token_adapter_address"
            save_contract_json "ArbitrumTokenAdapter" "$token_adapter_address" "ArbitrumDeployment"
            export ARBITRUM_TOKEN_ADAPTER_ADDRESS=$token_adapter_address
        fi
        
        if [ ! -z "$node_address" ]; then
            update_env_var "ARBITRUM_NODE_ADDRESS" "$node_address"
            save_contract_json "PasifikaArbitrumNode" "$node_address" "ArbitrumDeployment"
            export ARBITRUM_NODE_ADDRESS=$node_address
        fi
        
        if [ ! -z "$treasury_address" ]; then
            update_env_var "ARBITRUM_TREASURY_ADDRESS" "$treasury_address"
            update_env_var "PASIFIKA_TREASURY_ADDRESS" "$treasury_address"
            save_contract_json "PasifikaTreasury" "$treasury_address" "ArbitrumDeployment"
            export ARBITRUM_TREASURY_ADDRESS=$treasury_address
            export PASIFIKA_TREASURY_ADDRESS=$treasury_address
        fi
        
        if [ ! -z "$membership_address" ]; then
            update_env_var "ARBITRUM_MEMBERSHIP_ADDRESS" "$membership_address"
            update_env_var "PASIFIKA_MEMBERSHIP_ADDRESS" "$membership_address"
            save_contract_json "PasifikaMembership" "$membership_address" "ArbitrumDeployment"
            export ARBITRUM_MEMBERSHIP_ADDRESS=$membership_address
            export PASIFIKA_MEMBERSHIP_ADDRESS=$membership_address
        fi
        
        if [ ! -z "$money_transfer_address" ]; then
            update_env_var "ARBITRUM_MONEY_TRANSFER_ADDRESS" "$money_transfer_address"
            update_env_var "PASIFIKA_MONEY_TRANSFER_ADDRESS" "$money_transfer_address"
            save_contract_json "PasifikaMoneyTransfer" "$money_transfer_address" "ArbitrumDeployment"
            export ARBITRUM_MONEY_TRANSFER_ADDRESS=$money_transfer_address
            export PASIFIKA_MONEY_TRANSFER_ADDRESS=$money_transfer_address
        fi
        
        if [ ! -z "$token_adapter_address" ] && [ ! -z "$node_address" ] && \
           [ ! -z "$treasury_address" ] && [ ! -z "$membership_address" ] && \
           [ ! -z "$money_transfer_address" ]; then
            echo "✅ All contracts deployed successfully!"
            return 0
        else
            echo "❌ Some contracts failed to deploy. Check the log for details."
            return 1
        fi
    else
        # Otherwise deploy each contract individually in order
        # 1. Deploy ArbitrumTokenAdapter
        deploy_token_adapter || return 1
        echo ""
        
        # 2. Deploy PasifikaArbitrumNode
        deploy_node || return 1
        echo ""
        
        # 3. Deploy PasifikaTreasury
        deploy_treasury || return 1
        echo ""
        
        # 4. Deploy PasifikaMembership
        deploy_membership || return 1
        echo ""
        
        # 5. Deploy PasifikaMoneyTransfer
        deploy_money_transfer || return 1
        echo ""
        
        echo "✅ All contracts deployed successfully!"
        return 0
    fi
}

# Main script execution
case "${1:-help}" in
    "all")
        deploy_all
        ;;
    "token-adapter")
        deploy_token_adapter
        ;;
    "node")
        deploy_node
        ;;
    "treasury")
        deploy_treasury
        ;;
    "membership")
        deploy_membership
        ;;
    "money-transfer")
        deploy_money_transfer
        ;;
    "help"|*)
        show_help
        ;;
esac

# Show summary of deployed contracts
echo ""
echo "Deployment Summary:"
echo "-------------------------------------"
[ ! -z "$ARBITRUM_TOKEN_ADAPTER_ADDRESS" ] && echo "ArbitrumTokenAdapter: $ARBITRUM_TOKEN_ADAPTER_ADDRESS"
[ ! -z "$ARBITRUM_NODE_ADDRESS" ] && echo "PasifikaArbitrumNode: $ARBITRUM_NODE_ADDRESS"
[ ! -z "$ARBITRUM_TREASURY_ADDRESS" ] && echo "PasifikaTreasury: $ARBITRUM_TREASURY_ADDRESS"
[ ! -z "$ARBITRUM_MEMBERSHIP_ADDRESS" ] && echo "PasifikaMembership: $ARBITRUM_MEMBERSHIP_ADDRESS"
[ ! -z "$ARBITRUM_MONEY_TRANSFER_ADDRESS" ] && echo "PasifikaMoneyTransfer: $ARBITRUM_MONEY_TRANSFER_ADDRESS"
echo "-------------------------------------"
echo "Log file: $LOG_FILE"
echo "Contract JSON files saved to: $FE_DIR"
