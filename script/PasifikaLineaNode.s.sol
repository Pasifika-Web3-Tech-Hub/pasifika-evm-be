// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/PasifikaLineaNode.sol";

/**
 * @title PasifikaLineaNodeScript
 * @dev Deployment script for the PasifikaLineaNode contract
 */
contract PasifikaLineaNodeScript is Script {
    PasifikaLineaNode public lineaNode;

    /**
     * @dev The main function that deploys the PasifikaLineaNode contract
     */
    function run() external {
        // Get private key for deployment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(deployerPrivateKey);

        // Attempt to use the pasifika-account if set
        try vm.envAddress("ADMIN_ADDRESS") returns (address pasifikaAccount) {
            admin = pasifikaAccount;
            console.log("Using admin address from env:", admin);
        } catch {
            console.log("No ADMIN_ADDRESS found. Using deployer as admin:", admin);
        }

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the LineaNode contract
        lineaNode = new PasifikaLineaNode(admin);
        console.log("PasifikaLineaNode deployed to:", address(lineaNode));

        // Register an initial node operator if specified
        try vm.envAddress("INITIAL_NODE_OPERATOR") returns (address initialOperator) {
            try vm.envUint("INITIAL_NODE_STAKE") returns (uint256 initialStake) {
                if (initialStake > 0 && address(this).balance >= initialStake) {
                    lineaNode.registerNode{value: initialStake}(initialOperator);
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
