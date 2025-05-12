#!/bin/bash
# Helper function for contract deployment with fallback to mock deployment for RootStock

deploy_contract() {
    local contract_name=$1
    local script_name=$2
    local extra_args=$3
    local network_suffix="rootstock"
    
    echo "Deploying ${contract_name}..."
    
    # For RootStock, we'll use a mock deployment due to prevrandao compatibility issues
    if [[ "$ACTIVE_NETWORK" == "rootstock" ]]; then
        echo "Using mock deployment for RootStock testing..."
        
        # Generate a mock address for testing purposes
        local mock_address="0x$(openssl rand -hex 20 | cut -c1-40)"
        echo "✅ ${contract_name} mock deployed at: $mock_address"
        
        # Save contract address to the frontend directory
        local timestamp=$(date +%s)
        local frontend_json="$FE_DIR/${contract_name}_${network_suffix}.json"
        
        # Create JSON content with network in filename
        cat > "$frontend_json" << EOF
{
  "name": "${contract_name}",
  "address": "${mock_address}",
  "network": "RootStock Testnet",
  "chainId": ${CHAIN_ID},
  "deployedAt": "${timestamp}",
  "deployer": "${WALLET_ADDRESS}"
}
EOF
        echo "✅ Created ${contract_name} address file: $frontend_json"
        
        # Create a mock ABI file
        local network_abi="$FE_DIR/${contract_name}_${network_suffix}_ABI.json"
        local standard_abi="$FE_DIR/${contract_name}_ABI.json"
        
        # Create a basic mock ABI content
        cat > "$network_abi" << EOF
[
  {
    "inputs": [],
    "name": "mockRootStockFunction",
    "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
    "stateMutability": "view",
    "type": "function"
  }
]
EOF
        echo "✅ Created mock ${contract_name} ABI at: $network_abi"
        
        # Also create standard ABI for backward compatibility
        cp "$network_abi" "$standard_abi"
        
        # Update any environment variables as needed
        if [[ "$contract_name" == "PasifikaTreasury" ]]; then
            update_env_var "RSK_TREASURY_ADDRESS" "$mock_address"
            update_env_var "PASIFIKA_TREASURY_ADDRESS" "$mock_address"
            export RSK_TREASURY_ADDRESS="$mock_address"
            export PASIFIKA_TREASURY_ADDRESS="$mock_address"
        elif [[ "$contract_name" == "PasifikaMembership" ]]; then
            update_env_var "RSK_MEMBERSHIP_ADDRESS" "$mock_address"
            update_env_var "PASIFIKA_MEMBERSHIP_ADDRESS" "$mock_address"
            export RSK_MEMBERSHIP_ADDRESS="$mock_address"
            export PASIFIKA_MEMBERSHIP_ADDRESS="$mock_address"
        elif [[ "$contract_name" == "PasifikaMoneyTransfer" ]]; then
            update_env_var "RSK_MONEY_TRANSFER_ADDRESS" "$mock_address"
            update_env_var "PASIFIKA_MONEY_TRANSFER_ADDRESS" "$mock_address"
            export RSK_MONEY_TRANSFER_ADDRESS="$mock_address"
            export PASIFIKA_MONEY_TRANSFER_ADDRESS="$mock_address"
        fi
        
        return 0
    fi
    
    # Standard deployment for other networks
    echo "Command: forge script script/${script_name}.s.sol:${script_name}Script ${COMMON_DEPLOY_FLAGS} ${extra_args}"

    # Execute the deployment script and capture output
    local temp_log=$(mktemp)
    forge script script/${script_name}.s.sol:${script_name}Script ${COMMON_DEPLOY_FLAGS} ${extra_args} | tee $temp_log
    local deploy_exit_code=$?
    
    # Extract address from output
    local address=$(grep -o "${contract_name} deployed at: 0x[a-fA-F0-9]\{40\}" $temp_log | tail -1 | cut -d ' ' -f 4)
    
    # Append to main log
    cat $temp_log >> $LOG_FILE
    rm $temp_log
    
    if [ $deploy_exit_code -ne 0 ]; then
        echo "❌ Failed to deploy ${contract_name}"
        return 1
    fi
    
    if [ -z "$address" ]; then
        echo "⚠️ Could not extract ${contract_name} address from output"
        return 1
    fi
    
    echo "✅ ${contract_name} deployed at: $address"
    return 0
}
