// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { PasifikaMembership } from "../src/PasifikaMembership.sol";
import { PasifikaTreasury } from "../src/PasifikaTreasury.sol";

/**
 * @title PasifikaMembershipScript
 * @dev Deployment script for the PasifikaMembership contract using wallet alias
 */
contract PasifikaMembershipAliasScript is Script {
    PasifikaMembership public membership;
    PasifikaTreasury public treasury;

    function run() public {
        // Using wallet alias from the keystore instead of private key
        console.log("Deploying PasifikaMembership with account:", msg.sender);

        // Get PasifikaTreasury address if deployed
        address payable treasuryAddress;
        try vm.envAddress("ARBITRUM_TREASURY_ADDRESS") returns (address addr) {
            treasuryAddress = payable(addr);
            treasury = PasifikaTreasury(treasuryAddress);
            console.log("Using existing PasifikaTreasury at:", treasuryAddress);
        } catch {
            try vm.envAddress("PASIFIKA_TREASURY_ADDRESS") returns (address addr) {
                treasuryAddress = payable(addr);
                treasury = PasifikaTreasury(treasuryAddress);
                console.log("Using existing PasifikaTreasury at:", treasuryAddress);
            } catch {
                console.log("Error: No treasury address found. Please deploy PasifikaTreasury first.");
                return;
            }
        }

        // Deploy PasifikaMembership
        vm.startBroadcast();

        membership = new PasifikaMembership(treasuryAddress);

        // Skip adding membership as fee collector to treasury (will be done by admin manually)
        // This avoids access control issues during deployment
        console.log("PasifikaMembership deployed at:", address(membership));
        console.log("NOTE: To complete setup, the admin should manually add the membership contract");
        console.log("as a fee collector in the treasury using the treasury's addFeeCollector function.");

        vm.stopBroadcast();
    }
}
