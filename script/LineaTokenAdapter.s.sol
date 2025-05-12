// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { LineaTokenAdapter } from "../src/LineaTokenAdapter.sol";

/**
 * @title LineaTokenAdapterScript
 * @dev Deployment script for the LineaTokenAdapter contract
 */
contract LineaTokenAdapterScript is Script {
    LineaTokenAdapter public adapter;

    function run() public {
        // Get the admin address from env var or use the msg.sender as fallback
        address admin = msg.sender;
        try vm.envAddress("ADMIN_ADDRESS") returns (address addr) {
            admin = addr;
        } catch {
            // Using msg.sender as admin (the account specified with --account flag)
        }

        console.log("Deploying LineaTokenAdapter with account:", admin);

        // Deploy LineaTokenAdapter
        vm.broadcast();
        adapter = new LineaTokenAdapter();

        // Add a mock USDC token for testing purposes (this would be configured in production)
        address mockUSDC = 0x1234567890123456789012345678901234567890; // Example address
        try vm.envAddress("LINEA_USDC_ADDRESS") returns (address addr) {
            mockUSDC = addr;
        } catch {
            // Using default mock address
        }

        vm.broadcast();
        adapter.addToken(mockUSDC, "USDC");

        // Also add support for native ETH (address(0))
        vm.broadcast();
        adapter.addToken(address(0), "ETH");

        console.log("LineaTokenAdapter deployed at:", address(adapter));
    }
}
