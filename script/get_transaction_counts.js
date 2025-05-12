const { ethers } = require('ethers');
const fs = require('fs');

// Network RPC endpoints
const NETWORKS = {
  arbitrum: {
    name: 'Arbitrum Sepolia',
    rpc: 'https://sepolia-rollup.arbitrum.io/rpc',
    explorer: 'https://sepolia.arbiscan.io/address/',
  },
  linea: {
    name: 'Linea Testnet',
    rpc: 'https://rpc.sepolia.linea.build',
    explorer: 'https://sepolia.lineascan.build/address/',
  },
  rsk: {
    name: 'RSK Testnet',
    rpc: 'https://public-node.testnet.rsk.co',
    explorer: 'https://explorer.testnet.rootstock.io/address/',
  },
};

// Pasifika account and contract addresses
const PASIFIKA_ACCOUNT = '0x58a60a9cBEDC8E7d3f9ec9a96312BEDe8fc147b8';

// Contract addresses from ARBITRUM_DEPLOYMENT.md
const CONTRACTS = {
  arbitrum: {
    ArbitrumTokenAdapter: '0x80d3c57b95a2fca3900f3EAC71196Bf133aaa517',
    PasifikaArbitrumNode: '0xc79C57a047AD9B45B70D85000e9412C61f8fE336',
    PasifikaTreasury: '0x80d3c57b95a2fca3900f3EAC71196Bf133aaa517',
    PasifikaMembership: '0x80d3c57b95a2fca3900f3EAC71196Bf133aaa517',
    PasifikaMoneyTransfer: '0x80d3c57b95a2fca3900f3EAC71196Bf133aaa517',
  },
  linea: {
    // Add your Linea contract addresses here if available
    // Example: 
    // PasifikaTreasury: '0x...',
  },
  rsk: {
    // Add your RSK contract addresses here if available
    // Example:
    // PasifikaTreasury: '0x...',
  },
};

// Add any additional contract addresses via command line arguments
// Format: network:contractName:address
const args = process.argv.slice(2);
args.forEach(arg => {
  const [network, contractName, address] = arg.split(':');
  if (network && contractName && address && NETWORKS[network] && ethers.utils.isAddress(address)) {
    if (!CONTRACTS[network]) CONTRACTS[network] = {};
    CONTRACTS[network][contractName] = address;
    console.log(`Added ${contractName} at ${address} to ${network}`);
  }
});

// Function to get transaction count for an address
async function getTransactionCount(provider, address) {
  try {
    const txCount = await provider.getTransactionCount(address);
    const code = await provider.getCode(address);
    
    // Check if this is a contract address
    const isContract = code !== '0x';
    
    return {
      txCount,
      isContract,
      code: isContract ? code.substring(0, 20) + '...' : 'Not a contract',
    };
  } catch (error) {
    return {
      txCount: 0,
      isContract: false,
      error: error.message,
    };
  }
}

// Function to get transaction history for an address
async function getTransactionHistory(provider, address) {
  // Note: This is a simplified approach - ethers.js doesn't directly support
  // historical transaction queries, we would need to use the explorer API
  // or scan blocks for a proper implementation
  try {
    const blockNumber = await provider.getBlockNumber();
    const startBlock = Math.max(0, blockNumber - 10000); // Last 10,000 blocks as sample
    
    console.log(`  Checking from block ${startBlock} to ${blockNumber} (sample range)`);
    
    // For a proper implementation, you would need to:
    // 1. Use the explorer API, or
    // 2. Scan each block for transactions to/from the address (very time-consuming)
    // 3. Use a third-party service like Etherscan, Covalent, etc.
    
    return {
      message: "For detailed transaction history, check the blockchain explorer",
      explorerUrl: `${NETWORKS[network].explorer}${address}`,
    };
  } catch (error) {
    return {
      error: error.message,
    };
  }
}

// Main function to get transaction counts for all addresses
async function main() {
  const results = {
    account: {},
    contracts: {},
  };
  
  const totalCounts = {
    arbitrum: 0,
    linea: 0,
    rsk: 0,
    total: 0,
  };

  // Check the Pasifika account on each network
  console.log(`\n🔍 Checking Pasifika account: ${PASIFIKA_ACCOUNT}`);
  for (const [network, networkInfo] of Object.entries(NETWORKS)) {
    console.log(`\n📡 Network: ${networkInfo.name}`);
    
    try {
      const provider = new ethers.providers.JsonRpcProvider(networkInfo.rpc);
      
      // Get account transaction count
      console.log(`  Checking account transactions...`);
      const accountData = await getTransactionCount(provider, PASIFIKA_ACCOUNT);
      results.account[network] = accountData;
      
      console.log(`  Account transactions: ${accountData.txCount}`);
      totalCounts[network] += accountData.txCount;
      totalCounts.total += accountData.txCount;
      
      // Check each contract on this network
      if (CONTRACTS[network]) {
        results.contracts[network] = {};
        
        for (const [contractName, contractAddress] of Object.entries(CONTRACTS[network])) {
          if (!contractAddress) continue;
          
          console.log(`  Checking ${contractName} (${contractAddress})...`);
          const contractData = await getTransactionCount(provider, contractAddress);
          results.contracts[network][contractName] = contractData;
          
          console.log(`  ${contractName} transactions: ${contractData.txCount}`);
          totalCounts[network] += contractData.txCount;
          totalCounts.total += contractData.txCount;
        }
      }
    } catch (error) {
      console.error(`  Error connecting to ${networkInfo.name}: ${error.message}`);
      results.account[network] = { error: error.message };
    }
  }

  // Output summary
  console.log("\n📊 TRANSACTION COUNT SUMMARY");
  console.log("==========================");
  console.log(`Arbitrum Sepolia: ${totalCounts.arbitrum} transactions`);
  console.log(`Linea Testnet: ${totalCounts.linea} transactions`);
  console.log(`RSK Testnet: ${totalCounts.rsk} transactions`);
  console.log("--------------------------");
  console.log(`TOTAL: ${totalCounts.total} transactions\n`);
  
  // Write results to file
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const resultsFile = `./transactions-${timestamp}.json`;
  fs.writeFileSync(resultsFile, JSON.stringify(results, null, 2));
  console.log(`Detailed results saved to ${resultsFile}`);
  
  // Write summary to file
  const summaryFile = `./transactions-summary-${timestamp}.txt`;
  const summary = `
PASIFIKA TRANSACTION COUNT SUMMARY
==================================
Generated: ${new Date().toLocaleString()}

Account address: ${PASIFIKA_ACCOUNT}

NETWORKS:
---------
Arbitrum Sepolia: ${totalCounts.arbitrum} transactions
Linea Testnet: ${totalCounts.linea} transactions
RSK Testnet: ${totalCounts.rsk} transactions

TOTAL: ${totalCounts.total} transactions

For detailed transaction history, visit:
- Arbitrum Sepolia: ${NETWORKS.arbitrum.explorer}${PASIFIKA_ACCOUNT}
- Linea Testnet: ${NETWORKS.linea.explorer}${PASIFIKA_ACCOUNT}
- RSK Testnet: ${NETWORKS.rsk.explorer}${PASIFIKA_ACCOUNT}
  `;
  fs.writeFileSync(summaryFile, summary);
  console.log(`Summary saved to ${summaryFile}`);
}

// Run the main function
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Error:', error);
    process.exit(1);
  });
