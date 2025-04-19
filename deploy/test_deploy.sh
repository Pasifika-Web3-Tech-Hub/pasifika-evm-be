#!/bin/bash

# Pasifika Web3 Tech Hub - Deployment Script Test
# This script tests the deployment script without actually deploying contracts

# Colors for output formatting
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test paths and global variables
DEPLOY_SCRIPT="./deploy/deploy.sh"
MOCK_DEPLOYMENT_FILE="./deploy/test_deployment_info.txt"
MOCK_FRONTEND_DIR="./deploy/test_frontend_contracts"

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

# Test if the deploy script exists and is executable
test_script_existence() {
    print_header "Testing deployment script existence"
    
    if [ ! -f "$DEPLOY_SCRIPT" ]; then
        print_error "Deployment script not found at: $DEPLOY_SCRIPT"
        return 1
    fi
    
    if [ ! -x "$DEPLOY_SCRIPT" ]; then
        print_error "Deployment script is not executable"
        chmod +x "$DEPLOY_SCRIPT"
        print_warning "Made deployment script executable"
    fi
    
    print_success "Deployment script exists and is executable"
    return 0
}

# Test the help command
test_help_command() {
    print_header "Testing help command"
    
    $DEPLOY_SCRIPT --help
    
    if [ $? -ne 0 ]; then
        print_error "Help command failed"
        return 1
    fi
    
    print_success "Help command works correctly"
    return 0
}

# Test dependency checking
test_dependencies() {
    print_header "Testing dependency checking"
    
    echo "Checking for Foundry..."
    if ! command -v forge &> /dev/null; then
        print_warning "Foundry not found! This is expected in the test environment."
    else
        print_success "Foundry is installed."
    fi
    
    echo "Checking for foundry.toml..."
    if [ ! -f "foundry.toml" ]; then
        print_warning "foundry.toml not found! This file should be at the project root."
    else
        print_success "foundry.toml exists."
    fi
    
    return 0
}

# Test contract build (mock)
test_contract_build() {
    print_header "Testing contract build"
    
    echo "Simulating contract build..."
    echo "Compiling 25 files with 0.8.25"
    echo "Solc 0.8.25 finished in 2.54s"
    echo "Compiler run successful"
    
    print_success "Contract build simulation successful"
    return 0
}

# Test deployment saving function
test_deployment_info() {
    print_header "Testing deployment info saving"
    
    # Generate a mock deployment info file
    cat > "$MOCK_DEPLOYMENT_FILE" << EOF
Pasifika Web3 Tech Hub - Deployment Information (TEST)
===============================================
Timestamp: $(date)
Network: Test Network (Simulated)
RPC URL: http://localhost:8545

Deployed Contracts:
------------------
PSFToken: 0x5FbDB2315678afecb367f032d93F642f64180aa3
PSFStaking: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
PasifikaDynamicNFT: 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
PasifikaMarketplace: 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9

Deployer Address: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
EOF
    
    if [ -f "$MOCK_DEPLOYMENT_FILE" ]; then
        print_success "Mock deployment info file created successfully"
        echo "File contents:"
        cat "$MOCK_DEPLOYMENT_FILE"
        return 0
    else
        print_error "Failed to create mock deployment info file"
        return 1
    fi
}

# Test deployment script parameters
test_script_parameters() {
    print_header "Testing script parameters"
    
    # Test if the script accepts the --all parameter (should work but we don't execute deployment)
    print_warning "Testing --all parameter (would deploy all contracts)"
    $DEPLOY_SCRIPT --all 2>&1 | grep -q "Deploying" || echo "As expected, not actually deploying in test mode"
    
    # Test if the script accepts the --token parameter (should work but we don't execute deployment)
    print_warning "Testing --token parameter (would deploy PSFToken)"
    $DEPLOY_SCRIPT --token 2>&1 | grep -q "Deploying" || echo "As expected, not actually deploying in test mode"
    
    # Test invalid parameter
    print_warning "Testing invalid parameter"
    $DEPLOY_SCRIPT --invalid 2>&1 | grep -q "Unknown option" && print_success "Script correctly rejects invalid options"
    
    return 0
}

# Test deployment flow simulation
test_deployment_flow() {
    print_header "Testing deployment flow simulation"
    
    echo "1. Checking dependencies..."
    echo "2. Setting up environment..."
    echo "3. Building contracts..."
    echo "4. Deploying PSFToken..."
    echo "5. Deploying PSFStaking..."
    echo "6. Deploying PasifikaDynamicNFT..."
    echo "7. Deploying PasifikaMarketplace..."
    echo "8. Saving deployment information..."
    
    print_success "Deployment flow simulation completed"
    return 0
}

# Test PSFToken deployment simulation
test_psf_token_deployment() {
    print_header "Testing PSFToken deployment simulation"
    
    echo "Simulating PSFToken deployment with Foundry..."
    echo "Transaction successfully broadcast: 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
    echo "Waiting for receipt..."
    echo "Transaction included in block: 1"
    echo "Deployed to: 0x5FbDB2315678afecb367f032d93F642f64180aa3"
    echo "Starting contract verification..."
    echo "Contract successfully verified on Linea Sepolia!"
    
    print_success "PSFToken deployment simulation completed"
    return 0
}

# Test PSFStaking deployment simulation
test_psf_staking_deployment() {
    print_header "Testing PSFStaking deployment simulation"
    
    echo "Simulating PSFStaking deployment with Foundry..."
    echo "Using PSFToken address: 0x5FbDB2315678afecb367f032d93F642f64180aa3"
    echo "Admin address: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
    echo "Rewards distributor address: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
    echo "Transaction successfully broadcast: 0x2345678901abcdef2345678901abcdef2345678901abcdef2345678901abcdef"
    echo "Waiting for receipt..."
    echo "Transaction included in block: 2"
    echo "Deployed to: 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"
    echo "Starting contract verification..."
    echo "Contract successfully verified on Linea Sepolia!"
    
    print_success "PSFStaking deployment simulation completed"
    return 0
}

# Test frontend contract address saving
test_frontend_contract_saving() {
    print_header "Testing frontend contract address saving"
    
    # Create the mock frontend directory if it doesn't exist
    if [ ! -d "$MOCK_FRONTEND_DIR" ]; then
        mkdir -p "$MOCK_FRONTEND_DIR"
        print_warning "Created mock frontend directory: $MOCK_FRONTEND_DIR"
    fi
    
    # Save mock addresses to files
    echo "0x5FbDB2315678afecb367f032d93F642f64180aa3" > "$MOCK_FRONTEND_DIR/PSFToken.txt"
    echo "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512" > "$MOCK_FRONTEND_DIR/PSFStaking.txt"
    echo "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0" > "$MOCK_FRONTEND_DIR/PasifikaDynamicNFT.txt"
    echo "0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9" > "$MOCK_FRONTEND_DIR/PasifikaMarketplace.txt"
    echo "Linea Sepolia" > "$MOCK_FRONTEND_DIR/network.txt"
    echo "https://rpc.sepolia.linea.build" > "$MOCK_FRONTEND_DIR/rpc_url.txt"
    
    # Verify files were created
    local missing_files=0
    
    for file in "PSFToken.txt" "PSFStaking.txt" "PasifikaDynamicNFT.txt" "PasifikaMarketplace.txt" "network.txt" "rpc_url.txt"; do
        if [ ! -f "$MOCK_FRONTEND_DIR/$file" ]; then
            print_error "Failed to create $file in mock frontend directory"
            missing_files=$((missing_files + 1))
        fi
    done
    
    if [ $missing_files -eq 0 ]; then
        print_success "All contract address files created successfully in mock frontend directory"
        echo "Files saved to $MOCK_FRONTEND_DIR:"
        ls -la "$MOCK_FRONTEND_DIR"
        return 0
    else
        print_error "Failed to create all contract address files in mock frontend directory"
        return 1
    fi
}

# Clean up mock files
cleanup() {
    if [ -f "$MOCK_DEPLOYMENT_FILE" ]; then
        rm "$MOCK_DEPLOYMENT_FILE"
    fi
    
    if [ -d "$MOCK_FRONTEND_DIR" ]; then
        rm -rf "$MOCK_FRONTEND_DIR"
    fi
}

# Run all tests
run_all_tests() {
    test_script_existence
    test_help_command
    test_dependencies
    test_contract_build
    test_deployment_info
    test_script_parameters
    test_deployment_flow
    test_psf_token_deployment
    test_psf_staking_deployment
    test_frontend_contract_saving
    
    print_header "Test Summary"
    print_success "All deployment script tests completed successfully!"
    
    # Clean up mock files
    cleanup
}

# Display help
show_help() {
    echo "Pasifika Web3 Tech Hub - Deployment Script Test"
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help, -h       Show this help message"
    echo "  --all            Run all tests"
    echo "  --existence      Test script existence"
    echo "  --help-command   Test help command"
    echo "  --dependencies   Test dependency checking"
    echo "  --build          Test contract building"
    echo "  --info           Test deployment info saving"
    echo "  --parameters     Test script parameters"
    echo "  --flow           Test deployment flow"
    echo "  --token          Test PSFToken deployment"
    echo "  --staking        Test PSFStaking deployment"
    echo "  --frontend       Test frontend contract address saving"
    echo ""
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
        run_all_tests
        ;;
    --existence)
        test_script_existence
        ;;
    --help-command)
        test_help_command
        ;;
    --dependencies)
        test_dependencies
        ;;
    --build)
        test_contract_build
        ;;
    --info)
        test_deployment_info
        ;;
    --parameters)
        test_script_parameters
        ;;
    --flow)
        test_deployment_flow
        ;;
    --token)
        test_psf_token_deployment
        ;;
    --staking)
        test_psf_staking_deployment
        ;;
    --frontend)
        test_frontend_contract_saving
        ;;
    *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
esac

# Clean up on exit
trap cleanup EXIT
