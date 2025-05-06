#!/bin/bash
# Script to test Pasifika contracts on Arbitrum Sepolia fork

# Load environment variables
echo "Loading Arbitrum Sepolia configuration..."
set -a
source .env.testnet
set +a

# Run tests with verbosity on Arbitrum Sepolia fork
echo "Running tests on Arbitrum Sepolia fork..."
forge test --fork-url $ARBITRUM_TESTNET_RPC_URL -vv

# Check test status
if [ $? -eq 0 ]; then
  echo "✅ Tests passed on Arbitrum Sepolia fork!"
else
  echo "❌ Tests failed on Arbitrum Sepolia fork."
  exit 1
fi
