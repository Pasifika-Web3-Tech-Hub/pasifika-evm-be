#!/bin/bash

# This is a test script that extracts functions from deploy.sh file and runs only the build function
# This allows us to test the script without actually deploying anything

# Source required functions
source <(grep -A 500 "^print_header" ./deploy/deploy.sh)
source <(grep -A 500 "^print_success" ./deploy/deploy.sh)
source <(grep -A 500 "^print_warning" ./deploy/deploy.sh)
source <(grep -A 500 "^print_error" ./deploy/deploy.sh)
source <(grep -A 500 "^check_dependencies" ./deploy/deploy.sh)
source <(grep -A 500 "^build_contracts" ./deploy/deploy.sh)

# Define colors used in functions
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header "Testing deployment script functions"
echo "Running dependency check..."
check_dependencies

echo "Running build contracts function..."
build_contracts

echo -e "${GREEN}Test completed successfully!${NC}"
