// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/PasifikaArbitrumNode.sol";

/**
 * @title PasifikaArbitrumNodeScript
 * @dev Deployment script for the PasifikaArbitrumNode contract
 */
contract PasifikaArbitrumNodeScript is Script {
    PasifikaArbitrumNode public arbitrumNode;

    /**
     * @dev The main function that deploys the PasifikaArbitrumNode contract
     */
    function run() external {
        // Get private key for deployment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(deployerPrivateKey);

        // Attempt to use the pasifika-account if set (from memory in checkpoint)
        try vm.envAddress("ADMIN_ADDRESS") returns (address pasifikaAccount) {
            admin = pasifikaAccount;
            console.log("Using admin address from env:", admin);
        } catch {
            // As per memory, the pasifika-account should be 0x58a60a9cBEDC8E7d3f9ec9a96312BEDe8fc147b8
            try vm.envAddress("WALLET_ADDRESS") returns (address walletAddress) {
                admin = walletAddress;
                console.log("Using wallet address from env:", admin);
            } catch {
                console.log("No ADMIN_ADDRESS found. Using deployer as admin:", admin);
            }
        }

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the ArbitrumNode contract
        arbitrumNode = new PasifikaArbitrumNode(admin);
        console.log("PasifikaArbitrumNode deployed to:", address(arbitrumNode));

        // Register an initial node operator if specified
        try vm.envAddress("INITIAL_NODE_OPERATOR") returns (address initialOperator) {
            try vm.envUint("INITIAL_NODE_STAKE") returns (uint256 initialStake) {
                if (initialStake > 0 && address(this).balance >= initialStake) {
                    arbitrumNode.registerNode{value: initialStake}(initialOperator);
                    console.log("Registered initial node operator:", initialOperator);
                    console.log("Initial stake:", initialStake);
                }
            } catch {
                console.log("No initial stake specified. Skipping node registration.");
            }
        } catch {
            console.log("No initial node operator specified. Skipping node registration.");
        }

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
