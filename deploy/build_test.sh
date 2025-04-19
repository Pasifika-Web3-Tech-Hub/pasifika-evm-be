#!/bin/bash

# Colors for better output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "\n${BLUE}===========================================================${NC}"
echo -e "${BLUE}Testing the build process for Pasifika Web3 contracts${NC}"
echo -e "${BLUE}===========================================================${NC}\n"

echo -e "Checking for Foundry..."
if ! command -v forge &> /dev/null; then
    echo -e "${RED}Foundry not found! Please install Foundry first.${NC}"
    exit 1
fi

echo -e "Checking for foundry.toml..."
if [ ! -f "foundry.toml" ]; then
    echo -e "${RED}foundry.toml not found! Please run this script from the project root.${NC}"
    exit 1
fi

echo -e "${GREEN}All dependencies satisfied!${NC}"

echo -e "\n${BLUE}===========================================================${NC}"
echo -e "${BLUE}Building contracts${NC}"
echo -e "${BLUE}===========================================================${NC}\n"

forge build --force

if [ $? -ne 0 ]; then
    echo -e "${RED}Contract build failed!${NC}"
    exit 1
fi

echo -e "${GREEN}Contracts built successfully!${NC}"
echo -e "${GREEN}The deployment script is ready to use.${NC}"
echo -e "${YELLOW}To deploy contracts, use: ./deploy/deploy.sh --all${NC}"
echo -e "${YELLOW}For more options, use: ./deploy/deploy.sh --help${NC}"
