#!/bin/bash

# Pasifika Web3 Tech Hub - Official Keystore Deployment Script
# For deploying OpenZeppelin v5.3.0 contracts to Linea Sepolia using keystore

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Pasifika Web3 Tech Hub - Official Contract Deployment ===${NC}"

# Load environment variables
if [ -f .env ]; then
    source .env
fi

# Contract paths
PSF_TOKEN="src/PSFToken.sol:PSFToken"
PASIFIKA_DYNAMIC_NFT="src/PasifikaDynamicNFT.sol:PasifikaDynamicNFT"
PSF_STAKING="src/PSFStaking.sol:PSFStaking"
PASIFIKA_MARKETPLACE="src/PasifikaMarketplace.sol:PasifikaMarketplace"

# Account name to use (default to pasifika-account)
ACCOUNT_NAME="${2:-pasifika-account}"

# RPC URL from environment or default
RPC_URL="${LINEA_SEPOLIA_RPC:-https://rpc.sepolia.linea.build}"

# Check keystore account
DEPLOYER_ADDRESS=$(cast wallet address --account $ACCOUNT_NAME 2>/dev/null)
if [ -z "$DEPLOYER_ADDRESS" ]; then
    echo -e "${RED}Error: Keystore account '$ACCOUNT_NAME' not accessible!${NC}"
    echo -e "${YELLOW}Available accounts:${NC}"
    cast wallet list
    exit 1
fi

echo -e "${YELLOW}Using account: $ACCOUNT_NAME ($DEPLOYER_ADDRESS)${NC}"

# Skip compilation if already built
if [ -d "out" ]; then
    echo -e "\n${BLUE}Using existing build artifacts...${NC}"
else
    echo -e "\n${BLUE}Building contracts...${NC}"
    forge build
fi

# Contract selection menu if not provided as parameter
if [ -z "$1" ]; then
    echo -e "\n${BLUE}Which contract would you like to deploy?${NC}"
    echo "1) PSFToken"
    echo "2) PasifikaDynamicNFT"
    echo "3) PSFStaking"
    echo "4) PasifikaMarketplace"
    echo "5) Custom contract path"
    read -p "Enter your choice (1-5): " contract_choice
    
    case $contract_choice in
        1)
            CONTRACT=$PSF_TOKEN
            CONTRACT_NAME="PSFToken"
            CONSTRUCTOR_ARGS=""
            ;;
        2)
            CONTRACT=$PASIFIKA_DYNAMIC_NFT
            CONTRACT_NAME="PasifikaDynamicNFT"
            NFT_NAME="Pasifika Dynamic NFT"
            NFT_SYMBOL="PNFT"
            CONSTRUCTOR_ARGS="\"$NFT_NAME\" \"$NFT_SYMBOL\" $DEPLOYER_ADDRESS"
            ;;
        3)
            CONTRACT=$PSF_STAKING
            CONTRACT_NAME="PSFStaking"
            echo -e "\n${YELLOW}PSFStaking requires PSFToken address. Please enter it:${NC}"
            read PSF_TOKEN_ADDRESS
            
            if [[ ! "$PSF_TOKEN_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
                echo -e "${RED}Invalid PSFToken address format!${NC}"
                exit 1
            fi
            
            CONSTRUCTOR_ARGS="$PSF_TOKEN_ADDRESS $DEPLOYER_ADDRESS $DEPLOYER_ADDRESS"
            ;;
        4)
            CONTRACT=$PASIFIKA_MARKETPLACE
            CONTRACT_NAME="PasifikaMarketplace"
            echo -e "\n${YELLOW}PasifikaMarketplace requires PSFToken address. Please enter it:${NC}"
            read PSF_TOKEN_ADDRESS
            
            if [[ ! "$PSF_TOKEN_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
                echo -e "${RED}Invalid PSFToken address format!${NC}"
                exit 1
            fi
            
            FEE_PERCENTAGE="250" # 2.5% fee
            CONSTRUCTOR_ARGS="$PSF_TOKEN_ADDRESS $FEE_PERCENTAGE $DEPLOYER_ADDRESS"
            ;;
        5)
            echo -e "\n${YELLOW}Enter the full contract path (e.g., src/CustomContract.sol:ContractName):${NC}"
            read custom_contract
            
            if [[ ! "$custom_contract" =~ .*":" ]]; then
                echo -e "${RED}Invalid contract path format! Must be in format path/to/Contract.sol:ContractName${NC}"
                exit 1
            fi
            
            CONTRACT=$custom_contract
            CONTRACT_NAME=$(echo "$CONTRACT" | cut -d':' -f2)
            
            echo -e "\n${YELLOW}Does this contract require constructor arguments? (y/n)${NC}"
            read needs_args
            
            if [[ "$needs_args" == "y" || "$needs_args" == "Y" ]]; then
                echo -e "${YELLOW}Enter constructor arguments separated by spaces:${NC}"
                read custom_args
                CONSTRUCTOR_ARGS=$custom_args
            else
                CONSTRUCTOR_ARGS=""
            fi
            ;;
        *)
            echo -e "${RED}Invalid choice!${NC}"
            exit 1
            ;;
    esac
else
    # Contract provided as parameter
    CONTRACT=$1
    CONTRACT_NAME=$(echo "$CONTRACT" | cut -d':' -f2)
    
    # Set constructor args based on contract type
    if [[ "$CONTRACT_NAME" == "PSFToken" ]]; then
        CONSTRUCTOR_ARGS=""
    elif [[ "$CONTRACT_NAME" == "PasifikaDynamicNFT" ]]; then
        NFT_NAME="Pasifika Dynamic NFT"
        NFT_SYMBOL="PNFT"
        CONSTRUCTOR_ARGS="\"$NFT_NAME\" \"$NFT_SYMBOL\" $DEPLOYER_ADDRESS"
    elif [[ "$CONTRACT_NAME" == "PSFStaking" || "$CONTRACT_NAME" == "PasifikaMarketplace" ]]; then
        echo -e "\n${YELLOW}${CONTRACT_NAME} requires PSFToken address. Please enter it:${NC}"
        read PSF_TOKEN_ADDRESS
        
        if [[ ! "$PSF_TOKEN_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            echo -e "${RED}Invalid PSFToken address format!${NC}"
            exit 1
        fi
        
        if [[ "$CONTRACT_NAME" == "PSFStaking" ]]; then
            CONSTRUCTOR_ARGS="$PSF_TOKEN_ADDRESS $DEPLOYER_ADDRESS $DEPLOYER_ADDRESS"
        else
            FEE_PERCENTAGE="250" # 2.5% fee
            CONSTRUCTOR_ARGS="$PSF_TOKEN_ADDRESS $FEE_PERCENTAGE $DEPLOYER_ADDRESS"
        fi
    else
        echo -e "${YELLOW}Using default constructor for $CONTRACT_NAME${NC}"
        CONSTRUCTOR_ARGS=""
    fi
fi

# Display deployment info
echo -e "\n${BLUE}Deploying $CONTRACT_NAME to Linea Sepolia...${NC}"

# Deploy the contract
echo -e "\n${YELLOW}You will be prompted for your keystore password...${NC}"

# Construct deployment command with optimized gas settings
DEPLOY_CMD="forge create --rpc-url $RPC_URL --account $ACCOUNT_NAME --broadcast $CONTRACT --legacy --gas-limit 2000000 --gas-price 100000000"

# Add constructor args if needed
if [ ! -z "$CONSTRUCTOR_ARGS" ]; then
    DEPLOY_CMD="$DEPLOY_CMD --constructor-args $CONSTRUCTOR_ARGS"
fi

# Add verification if API key available
if [ ! -z "$LINEASCAN_API_KEY" ]; then
    DEPLOY_CMD="$DEPLOY_CMD --verify --verifier-url https://api-sepolia.lineascan.build/api --etherscan-api-key $LINEASCAN_API_KEY"
fi

# Display command (hiding any private keys)
echo -e "${YELLOW}Executing deployment for $CONTRACT_NAME...${NC}"

# Execute deployment
DEPLOY_OUTPUT=$(eval $DEPLOY_CMD)
DEPLOY_RESULT=$?

# Extract the deployed contract address
if [ $DEPLOY_RESULT -eq 0 ]; then
    # Extract the contract address from the output
    CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -oP "Deployed to: \K0x[a-fA-F0-9]{40}")
    TRANSACTION_HASH=$(echo "$DEPLOY_OUTPUT" | grep -oP "Transaction hash: \K0x[a-fA-F0-9]{64}")
    
    # Fall back to alternative extraction if the above didn't work
    if [ -z "$CONTRACT_ADDRESS" ]; then
        CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -o "0x[a-fA-F0-9]\{40\}" | head -1)
    fi
    
    if [ -z "$TRANSACTION_HASH" ]; then
        TRANSACTION_HASH=$(echo "$DEPLOY_OUTPUT" | grep -o "0x[a-fA-F0-9]\{64\}" | head -1)
    fi
    
    echo -e "\n${GREEN}Deployment successful!${NC}"
    echo -e "${GREEN}Contract: $CONTRACT_NAME${NC}"
    echo -e "${GREEN}Address: $CONTRACT_ADDRESS${NC}"
    echo -e "${GREEN}TX Hash: $TRANSACTION_HASH${NC}"
    
    # Create deployment directory if it doesn't exist
    FRONTEND_DIR="/home/user/Documents/pasifika-web3-tech-hub/pasifika-web3-fe/deployed_contracts"
    mkdir -p "$FRONTEND_DIR"
    
    # Save the contract info to a single reference file
    REFERENCE_FILE="$FRONTEND_DIR/${CONTRACT_NAME}.json"
    
    # Create JSON with deployment details
    cat > "$REFERENCE_FILE" << EOF
{
  "contractName": "$CONTRACT_NAME",
  "address": "$CONTRACT_ADDRESS",
  "network": "linea-sepolia",
  "deploymentDate": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "transactionHash": "$TRANSACTION_HASH",
  "deployer": "$DEPLOYER_ADDRESS"
}
EOF
    
    echo -e "${GREEN}Deployment details saved to: $REFERENCE_FILE${NC}"
    
    # If this is the PSFToken, save it as the main token address for reference
    if [[ "$CONTRACT_NAME" == "PSFToken" ]]; then
        echo "$CONTRACT_ADDRESS" > "$FRONTEND_DIR/psf_token_address.txt"
        echo -e "${GREEN}Token address saved to psf_token_address.txt${NC}"
    fi
    
    # Print Linea Sepolia explorer link
    echo -e "\n${BLUE}View your contract on Linea Sepolia Explorer:${NC}"
    echo -e "${YELLOW}https://sepolia.lineascan.build/address/$CONTRACT_ADDRESS${NC}"
else
    echo -e "\n${RED}Deployment failed!${NC}"
    echo "$DEPLOY_OUTPUT"
    echo -e "${YELLOW}Check the error details above${NC}"
    echo -e "${YELLOW}Make sure you have sufficient Linea Sepolia testnet ETH${NC}"
    echo -e "${YELLOW}Visit a Linea Sepolia faucet to get testnet ETH${NC}"
    exit 1
fi
