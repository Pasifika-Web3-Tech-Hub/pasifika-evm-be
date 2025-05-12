// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/PasifikaRootStockNode.sol";

/**
 * @title PasifikaRootStockNodeScript
 * @dev Deployment script for the PasifikaRootStockNode contract
 */
contract PasifikaRootStockNodeScript is Script {
    PasifikaRootStockNode public rootstockNode;

    /**
     * @dev The main function that deploys the PasifikaRootStockNode contract
     */
    function run() external {
        // Get private key for deployment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(deployerPrivateKey);
        address rifToken;

        // Attempt to use the pasifika-account if set (from memory in checkpoint)
        try vm.envAddress("ADMIN_ADDRESS") returns (address pasifikaAccount) {
            admin = pasifikaAccount;
            console.log("Using admin address from env:", admin);
        } catch {
            console.log("No ADMIN_ADDRESS found. Using deployer as admin:", admin);
        }

        // Get RIF token address from environment
        try vm.envAddress("RIF_TOKEN_ADDRESS") returns (address rifTokenAddr) {
            rifToken = rifTokenAddr;
            console.log("Using RIF token address from env:", rifToken);
        } catch {
            // If no RIF token address is provided, use a mock address for testing
            rifToken = address(0x1234567890123456789012345678901234567890);
            console.log("No RIF_TOKEN_ADDRESS found. Using mock address:", rifToken);
        }

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the RootStockNode contract
        rootstockNode = new PasifikaRootStockNode(admin, rifToken);
        console.log("PasifikaRootStockNode deployed to:", address(rootstockNode));

        // Register an initial node operator if specified
        try vm.envAddress("INITIAL_NODE_OPERATOR") returns (address initialOperator) {
            try vm.envUint("INITIAL_NODE_STAKE") returns (uint256 initialStake) {
                if (initialStake > 0 && address(this).balance >= initialStake) {
                    rootstockNode.registerNode{ value: initialStake }(initialOperator);
                    console.log("Registered initial node operator:", initialOperator);
                    console.log("Initial stake (RBTC):", initialStake);
                }
            } catch {
                console.log("No initial stake specified. Skipping node registration.");
            }
        } catch {
            console.log("No initial node operator specified. Skipping node registration.");
        }

        // Set profit sharing percentage if specified in the environment
        try vm.envUint("PROFIT_SHARING_PERCENTAGE") returns (uint256 profitPercentage) {
            if (profitPercentage <= 100) {
                rootstockNode.updateProfitSharingPercentage(profitPercentage);
                console.log("Set profit sharing percentage to:", profitPercentage, "%");
            }
        } catch {
            console.log("Using default profit sharing percentage (50%)");
        }

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
