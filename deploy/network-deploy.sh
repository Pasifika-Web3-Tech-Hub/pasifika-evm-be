#!/bin/bash
# Network Deployment Selector Script for Pasifika contracts
# This script allows you to deploy to Arbitrum, Linea, or RootStock networks

# Display usage information
show_help() {
    echo "Pasifika Multi-Network Deployment Script"
    echo ""
    echo "Usage: $0 <network> [option]"
    echo ""
    echo "Networks:"
    echo "  arbitrum       Deploy to Arbitrum"
    echo "  linea          Deploy to Linea"
    echo "  rootstock      Deploy to RootStock"
    echo ""
    echo "Options:"
    echo "  all             Deploy all contracts in the correct order"
    echo "  token-adapter   Deploy network token adapter only"
    echo "  node            Deploy network node only"
    echo "  treasury        Deploy PasifikaTreasury only"
    echo "  membership      Deploy PasifikaMembership only"
    echo "  money-transfer  Deploy PasifikaMoneyTransfer only"
    echo "  help            Show this help message"
    echo ""
    echo "Example: $0 linea all"
    echo "Example: $0 rootstock treasury"
}

# Check if a network is provided
if [ $# -lt 1 ]; then
    show_help
    exit 1
fi

NETWORK=$1
shift  # Remove the first argument (network) from the args list

# Validate network
case "$NETWORK" in
    arbitrum)
        DEPLOY_SCRIPT="./deploy/arbitrum-deploy.sh"
        ENV_FILE=".env.arbitrum"
        echo "Selected network: Arbitrum"
        ;;
    linea)
        DEPLOY_SCRIPT="./deploy/linea-deploy.sh"
        ENV_FILE=".env.linea"
        echo "Selected network: Linea"
        ;;
    rootstock)
        DEPLOY_SCRIPT="./deploy/rootstock-deploy.sh"
        ENV_FILE=".env.rootstock"
        echo "Selected network: RootStock"
        ;;
    help|--help|-h)
        show_help
        exit 0
        ;;
    *)
        echo "Error: Unknown network '$NETWORK'"
        show_help
        exit 1
        ;;
esac

# Check if the deployment script exists
if [ ! -f "$DEPLOY_SCRIPT" ]; then
    echo "Error: Deployment script '$DEPLOY_SCRIPT' not found"
    exit 1
fi

# Ensure the script is executable
chmod +x "$DEPLOY_SCRIPT"

# Create the environment file if it doesn't exist
if [ ! -f "$ENV_FILE" ]; then
    echo "Notice: Environment file '$ENV_FILE' not found. Creating a template..."
    
    cat > "$ENV_FILE" << EOF
# Pasifika $NETWORK Deployment Configuration

# Network configuration
$([ "$NETWORK" = "arbitrum" ] && echo "ARBITRUM_NETWORK=testnet  # Change to mainnet for production")
$([ "$NETWORK" = "linea" ] && echo "LINEA_NETWORK=testnet  # Change to mainnet for production")
$([ "$NETWORK" = "rootstock" ] && echo "RSK_NETWORK=testnet  # Change to mainnet for production")

# Wallet configuration
WALLET_ALIAS=pasifika-deployer  # Your Foundry wallet alias
# Alternative: PRIVATE_KEY=your_private_key_here

# Contract configuration
FEE_RECIPIENT=   # Address to receive marketplace fees
TREASURY_WALLET= # Address for treasury operations

# Optional: RPC configuration
# RPC_URL=       # Custom RPC URL (defaults to public endpoint)

# Optional: Gas configuration
# GAS_PRICE=     # Custom gas price in wei
# GAS_LIMIT=     # Custom gas limit

# Optional: Contract verification
# VERIFY_CONTRACTS=true
# $([ "$NETWORK" = "arbitrum" ] && echo "ARBISCAN_API_KEY=")
# $([ "$NETWORK" = "linea" ] && echo "LINEASCAN_API_KEY=")
# $([ "$NETWORK" = "rootstock" ] && echo "ROOTSCAN_API_KEY=")

# Optional: Existing contract addresses
# These will be populated automatically during deployment
EOF
    
    echo "Created template environment file: $ENV_FILE"
    echo "Please edit it with your configuration before deployment"
    echo ""
fi

# Create a frontend helper to read multi-chain contracts
create_frontend_helper() {
    FE_DIR="/home/user/Documents/pasifika-web3-tech-hub/pasifika-web3-fe/deployed_contracts"
    mkdir -p "$FE_DIR"
    
    cat > "$FE_DIR/contract-loader.js" << EOF
/**
 * Pasifika Multi-Chain Contract Loader
 * This helper provides easy access to contract addresses across multiple chains
 */

/**
 * Get the contract address for a specific network
 * @param {string} contractName - The name of the contract (e.g., "PasifikaTreasury")
 * @param {string} network - The network name ("arbitrum", "linea", "rootstock")
 * @returns {string|null} The contract address or null if not found
 */
export function getContractAddress(contractName, network) {
  try {
    const contract = require(\`./$\{contractName}_$\{network}.json\`);
    return contract?.address || null;
  } catch (e) {
    console.error(\`Contract \${contractName} not found for network \${network}\`);
    return null;
  }
}

/**
 * Get the contract ABI
 * @param {string} contractName - The name of the contract
 * @returns {Array|null} The contract ABI or null if not found
 */
export function getContractABI(contractName) {
  try {
    const abi = require(\`./$\{contractName}_ABI.json\`);
    return abi?.abi || null;
  } catch (e) {
    console.error(\`ABI for \${contractName} not found\`);
    return null;
  }
}

/**
 * Get contract info for all available networks
 * @param {string} contractName - The name of the contract
 * @returns {Object} Object with network names as keys and addresses as values
 */
export function getAllNetworkAddresses(contractName) {
  const networks = ["arbitrum", "linea", "rootstock"];
  const addresses = {};
  
  for (const network of networks) {
    try {
      const contract = require(\`./$\{contractName}_$\{network}.json\`);
      if (contract?.address) {
        addresses[network] = {
          address: contract.address,
          chainId: contract.chainId,
          explorer: contract.explorer
        };
      }
    } catch (e) {
      // Contract not deployed on this network, skip
    }
  }
  
  return addresses;
}

/**
 * Get all deployed contracts for a specific network
 * @param {string} network - The network name
 * @returns {Object} Object with contract names as keys and addresses as values
 */
export function getNetworkContracts(network) {
  const contractTypes = [
    "PasifikaTreasury",
    "PasifikaMembership",
    "PasifikaMoneyTransfer"
  ];
  
  const contracts = {};
  
  for (const contractName of contractTypes) {
    try {
      const contract = require(\`./$\{contractName}_$\{network}.json\`);
      if (contract?.address) {
        contracts[contractName] = contract.address;
      }
    } catch (e) {
      // Contract not deployed, skip
    }
  }
  
  return contracts;
}
EOF

    echo "Created frontend helper: $FE_DIR/contract-loader.js"
}

# Create frontend helper file if needed
if [ ! -f "/home/user/Documents/pasifika-web3-tech-hub/pasifika-web3-fe/deployed_contracts/contract-loader.js" ]; then
    create_frontend_helper
fi

# Run the appropriate deployment script with remaining arguments
echo "Running $DEPLOY_SCRIPT with options: $@"
"$DEPLOY_SCRIPT" "$@"

exit $?
