#!/bin/bash

# Pasifika Web3 Tech Hub - Deployment Script
# This script helps deploy and verify smart contracts on Linea Sepolia testnet

# Text colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Config variables - modify these as needed
RPC_URL="https://rpc.sepolia.linea.build"
VERIFIER_URL="https://api-sepolia.lineascan.build/api"
ACCOUNT_NAME="deployer-account" # Your Foundry account name
ETHERSCAN_API_KEY="LINEASCAN_API_KEY" # Replace with your actual API key

# Contract paths and names
PSF_TOKEN="src/PSFToken.sol:PSFToken"
PSF_STAKING="src/PSFStaking.sol:PSFStaking"
PASIFIKA_DYNAMIC_NFT="src/PasifikaDynamicNFT.sol:PasifikaDynamicNFT"
PASIFIKA_MARKETPLACE="src/PasifikaMarketplace.sol:PasifikaMarketplace"

# Frontend directory for saving contract addresses
FRONTEND_CONTRACT_DIR="/home/user/Documents/pasifika-web3-tech-hub/pasifika-web3-fe/deployed_contracts"

# Contract deployment constructor arguments
declare -A CONTRACT_ARGS
# Initially empty - to be set during deployment flow

print_header() {
    echo -e "\n${BLUE}===========================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===========================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}$1${NC}"
}

check_dependencies() {
    print_header "Checking dependencies"
    
    if ! command -v forge &> /dev/null; then
        print_error "Foundry not found! Please install Foundry first."
        exit 1
    fi
    
    if [ ! -f "foundry.toml" ]; then
        print_error "foundry.toml not found! Please run this script from the project root."
        exit 1
    fi
    
    print_success "All dependencies satisfied!"
}

setup_environment() {
    print_header "Setting up environment"
    
    # Prompt for API key if using placeholder
    if [[ "$ETHERSCAN_API_KEY" == "LINEASCAN_API_KEY" ]]; then
        read -p "Enter your LineaScan API key: " ETHERSCAN_API_KEY
    fi
    
    # Prompt for account if needed
    read -p "Use account '$ACCOUNT_NAME' for deployment? (y/n): " use_default_account
    if [[ "$use_default_account" != "y" ]]; then
        read -p "Enter the Foundry account name to use: " ACCOUNT_NAME
    fi
    
    # Check if account exists
    if ! forge account list | grep -q "$ACCOUNT_NAME"; then
        print_error "Account '$ACCOUNT_NAME' not found in Foundry!"
        print_warning "Available accounts:"
        forge account list
        exit 1
    fi
    
    print_success "Environment set up successfully!"
}

build_contracts() {
    print_header "Building contracts"
    
    forge build --force
    
    if [ $? -ne 0 ]; then
        print_error "Contract build failed!"
        exit 1
    fi
    
    print_success "Contracts built successfully!"
}

deploy_contract() {
    local contract_path=$1
    local contract_name=$2
    local constructor_args=$3
    
    echo -e "\nDeploying $contract_name..."
    
    local cmd="forge create --rpc-url $RPC_URL --account $ACCOUNT_NAME --broadcast --verify --verifier-url $VERIFIER_URL --etherscan-api-key $ETHERSCAN_API_KEY $contract_path"
    
    if [ ! -z "$constructor_args" ]; then
        cmd="$cmd --constructor-args $constructor_args"
    fi
    
    echo "Executing: $cmd"
    
    # Execute the command and capture output
    local output
    output=$(eval $cmd 2>&1)
    local exit_code=$?
    
    echo "$output"
    
    if [ $exit_code -ne 0 ]; then
        print_error "Failed to deploy $contract_name!"
        return 1
    fi
    
    # Extract deployed address from output
    local deployed_address
    deployed_address=$(echo "$output" | grep -oP 'Deployed to: \K0x[a-fA-F0-9]{40}')
    
    if [ -z "$deployed_address" ]; then
        print_warning "Couldn't extract deployed address for $contract_name"
        return 0
    fi
    
    print_success "$contract_name deployed to: $deployed_address"
    
    # Return the deployed address
    echo "$deployed_address"
}

deploy_psf_token() {
    print_header "Deploying PSFToken"
    
    # PSFToken constructor doesn't need arguments
    local psf_token_address
    psf_token_address=$(deploy_contract "$PSF_TOKEN" "PSFToken")
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    CONTRACT_ARGS["PSF_TOKEN_ADDRESS"]=$psf_token_address
    return 0
}

deploy_psf_staking() {
    print_header "Deploying PSFStaking"
    
    if [ -z "${CONTRACT_ARGS[PSF_TOKEN_ADDRESS]}" ]; then
        print_error "PSFToken address not found! Deploy PSFToken first."
        return 1
    fi
    
    # Get addresses for PSFStaking constructor
    local psf_token_address="${CONTRACT_ARGS[PSF_TOKEN_ADDRESS]}"
    local admin_address
    
    # Get the address of the account being used
    admin_address=$(forge account address "$ACCOUNT_NAME" | grep "$ACCOUNT_NAME" | awk '{print $2}')
    
    if [ -z "$admin_address" ]; then
        print_error "Failed to get address for account $ACCOUNT_NAME"
        return 1
    fi
    
    # Use the same address for rewards distributor initially
    local rewards_distributor_address=$admin_address
    
    # Prepare constructor arguments
    local constructor_args="$psf_token_address $admin_address $rewards_distributor_address"
    
    local psf_staking_address
    psf_staking_address=$(deploy_contract "$PSF_STAKING" "PSFStaking" "$constructor_args")
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    CONTRACT_ARGS["PSF_STAKING_ADDRESS"]=$psf_staking_address
    return 0
}

deploy_pasifika_dynamic_nft() {
    print_header "Deploying PasifikaDynamicNFT"
    
    # Get admin address
    local admin_address
    admin_address=$(forge account address "$ACCOUNT_NAME" | grep "$ACCOUNT_NAME" | awk '{print $2}')
    
    if [ -z "$admin_address" ]; then
        print_error "Failed to get address for account $ACCOUNT_NAME"
        return 1
    fi
    
    # Prepare constructor arguments (name, symbol, admin)
    local constructor_args="\"Pasifika Dynamic NFT\" \"PNFT\" $admin_address"
    
    local dynamic_nft_address
    dynamic_nft_address=$(deploy_contract "$PASIFIKA_DYNAMIC_NFT" "PasifikaDynamicNFT" "$constructor_args")
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    CONTRACT_ARGS["DYNAMIC_NFT_ADDRESS"]=$dynamic_nft_address
    return 0
}

deploy_pasifika_marketplace() {
    print_header "Deploying PasifikaMarketplace"
    
    if [ -z "${CONTRACT_ARGS[PSF_TOKEN_ADDRESS]}" ]; then
        print_error "PSFToken address not found! Deploy PSFToken first."
        return 1
    fi
    
    # Get admin address
    local admin_address
    admin_address=$(forge account address "$ACCOUNT_NAME" | grep "$ACCOUNT_NAME" | awk '{print $2}')
    
    if [ -z "$admin_address" ]; then
        print_error "Failed to get address for account $ACCOUNT_NAME"
        return 1
    fi
    
    # Prepare constructor arguments (payment token, fee percentage, admin address)
    local psf_token_address="${CONTRACT_ARGS[PSF_TOKEN_ADDRESS]}"
    local fee_percentage="250" # 2.5% fee
    
    local constructor_args="$psf_token_address $fee_percentage $admin_address"
    
    local marketplace_address
    marketplace_address=$(deploy_contract "$PASIFIKA_MARKETPLACE" "PasifikaMarketplace" "$constructor_args")
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    CONTRACT_ARGS["MARKETPLACE_ADDRESS"]=$marketplace_address
    return 0
}

save_deployment_info() {
    print_header "Saving deployment information"
    
    local timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
    local deployment_file="./deploy/deployment_$timestamp.txt"
    
    cat > "$deployment_file" << EOF
Pasifika Web3 Tech Hub - Deployment Information
===============================================
Timestamp: $(date)
Network: Linea Sepolia
RPC URL: $RPC_URL

Deployed Contracts:
------------------
PSFToken: ${CONTRACT_ARGS[PSF_TOKEN_ADDRESS]}
PSFStaking: ${CONTRACT_ARGS[PSF_STAKING_ADDRESS]}
PasifikaDynamicNFT: ${CONTRACT_ARGS[DYNAMIC_NFT_ADDRESS]}
PasifikaMarketplace: ${CONTRACT_ARGS[MARKETPLACE_ADDRESS]}

Deployer Address: $(forge account address "$ACCOUNT_NAME" | grep "$ACCOUNT_NAME" | awk '{print $2}')
EOF
    
    print_success "Deployment information saved to: $deployment_file"
    
    # Save contract addresses to frontend directory
    save_contracts_to_frontend
}

save_contracts_to_frontend() {
    print_header "Saving contract addresses to frontend directory"
    
    # Create the frontend directory if it doesn't exist
    if [ ! -d "$FRONTEND_CONTRACT_DIR" ]; then
        mkdir -p "$FRONTEND_CONTRACT_DIR"
        print_warning "Created frontend contracts directory: $FRONTEND_CONTRACT_DIR"
    fi
    
    # Save PSFToken address
    if [ ! -z "${CONTRACT_ARGS[PSF_TOKEN_ADDRESS]}" ]; then
        echo "${CONTRACT_ARGS[PSF_TOKEN_ADDRESS]}" > "$FRONTEND_CONTRACT_DIR/PSFToken.txt"
        print_success "Saved PSFToken address to $FRONTEND_CONTRACT_DIR/PSFToken.txt"
    fi
    
    # Save PSFStaking address
    if [ ! -z "${CONTRACT_ARGS[PSF_STAKING_ADDRESS]}" ]; then
        echo "${CONTRACT_ARGS[PSF_STAKING_ADDRESS]}" > "$FRONTEND_CONTRACT_DIR/PSFStaking.txt"
        print_success "Saved PSFStaking address to $FRONTEND_CONTRACT_DIR/PSFStaking.txt"
    fi
    
    # Save PasifikaDynamicNFT address
    if [ ! -z "${CONTRACT_ARGS[DYNAMIC_NFT_ADDRESS]}" ]; then
        echo "${CONTRACT_ARGS[DYNAMIC_NFT_ADDRESS]}" > "$FRONTEND_CONTRACT_DIR/PasifikaDynamicNFT.txt"
        print_success "Saved PasifikaDynamicNFT address to $FRONTEND_CONTRACT_DIR/PasifikaDynamicNFT.txt"
    fi
    
    # Save PasifikaMarketplace address
    if [ ! -z "${CONTRACT_ARGS[MARKETPLACE_ADDRESS]}" ]; then
        echo "${CONTRACT_ARGS[MARKETPLACE_ADDRESS]}" > "$FRONTEND_CONTRACT_DIR/PasifikaMarketplace.txt"
        print_success "Saved PasifikaMarketplace address to $FRONTEND_CONTRACT_DIR/PasifikaMarketplace.txt"
    fi
    
    # Also save network information
    echo "Linea Sepolia" > "$FRONTEND_CONTRACT_DIR/network.txt"
    print_success "Saved network information to $FRONTEND_CONTRACT_DIR/network.txt"
    
    # Save RPC URL
    echo "$RPC_URL" > "$FRONTEND_CONTRACT_DIR/rpc_url.txt"
    print_success "Saved RPC URL to $FRONTEND_CONTRACT_DIR/rpc_url.txt"
    
    print_success "Contract addresses successfully saved to frontend directory"
}

deploy_all() {
    check_dependencies
    setup_environment
    build_contracts
    
    deploy_psf_token
    if [ $? -ne 0 ]; then
        print_error "Failed to deploy PSFToken. Aborting deployment."
        exit 1
    fi
    
    deploy_psf_staking
    if [ $? -ne 0 ]; then
        print_warning "Failed to deploy PSFStaking. Continuing with other contracts."
    fi
    
    deploy_pasifika_dynamic_nft
    if [ $? -ne 0 ]; then
        print_warning "Failed to deploy PasifikaDynamicNFT. Continuing with other contracts."
    fi
    
    deploy_pasifika_marketplace
    if [ $? -ne 0 ]; then
        print_warning "Failed to deploy PasifikaMarketplace."
    fi
    
    save_deployment_info
    
    print_header "Deployment Summary"
    
    echo -e "PSFToken: ${GREEN}${CONTRACT_ARGS[PSF_TOKEN_ADDRESS]}${NC}"
    
    if [ ! -z "${CONTRACT_ARGS[PSF_STAKING_ADDRESS]}" ]; then
        echo -e "PSFStaking: ${GREEN}${CONTRACT_ARGS[PSF_STAKING_ADDRESS]}${NC}"
    else
        echo -e "PSFStaking: ${RED}Not deployed${NC}"
    fi
    
    if [ ! -z "${CONTRACT_ARGS[DYNAMIC_NFT_ADDRESS]}" ]; then
        echo -e "PasifikaDynamicNFT: ${GREEN}${CONTRACT_ARGS[DYNAMIC_NFT_ADDRESS]}${NC}"
    else
        echo -e "PasifikaDynamicNFT: ${RED}Not deployed${NC}"
    fi
    
    if [ ! -z "${CONTRACT_ARGS[MARKETPLACE_ADDRESS]}" ]; then
        echo -e "PasifikaMarketplace: ${GREEN}${CONTRACT_ARGS[MARKETPLACE_ADDRESS]}${NC}"
    else
        echo -e "PasifikaMarketplace: ${RED}Not deployed${NC}"
    fi
    
    print_success "Deployment process completed!"
}

show_help() {
    echo "Pasifika Web3 Tech Hub - Deployment Script"
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help, -h       Show this help message"
    echo "  --all            Deploy all contracts"
    echo "  --token          Deploy only PSFToken"
    echo "  --staking        Deploy only PSFStaking (requires PSFToken)"
    echo "  --nft            Deploy only PasifikaDynamicNFT"
    echo "  --marketplace    Deploy only PasifikaMarketplace (requires PSFToken)"
    echo ""
    echo "Environment variables (can be set directly in the script):"
    echo "  RPC_URL          RPC URL for the target network"
    echo "  VERIFIER_URL     Verifier URL for contract verification"
    echo "  ACCOUNT_NAME     Foundry account name to use for deployment"
    echo "  ETHERSCAN_API_KEY LineaScan API key for verification"
}

# Main execution
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

case "$1" in
    --help|-h)
        show_help
        ;;
    --all)
        deploy_all
        ;;
    --token)
        check_dependencies
        setup_environment
        build_contracts
        deploy_psf_token
        ;;
    --staking)
        check_dependencies
        setup_environment
        build_contracts
        read -p "Enter PSFToken address: " psf_token_address
        CONTRACT_ARGS["PSF_TOKEN_ADDRESS"]=$psf_token_address
        deploy_psf_staking
        ;;
    --nft)
        check_dependencies
        setup_environment
        build_contracts
        deploy_pasifika_dynamic_nft
        ;;
    --marketplace)
        check_dependencies
        setup_environment
        build_contracts
        read -p "Enter PSFToken address: " psf_token_address
        CONTRACT_ARGS["PSF_TOKEN_ADDRESS"]=$psf_token_address
        deploy_pasifika_marketplace
        ;;
    *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
esac
