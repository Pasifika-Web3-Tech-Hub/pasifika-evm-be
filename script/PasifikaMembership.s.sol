// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { PasifikaMembership } from "../src/PasifikaMembership.sol";
import { PasifikaTreasury } from "../src/PasifikaTreasury.sol";

/**
 * @title PasifikaMembershipScript
 * @dev Deployment script for the PasifikaMembership contract
 */
contract PasifikaMembershipScript is Script {
    PasifikaMembership public membership;
    PasifikaTreasury public treasury;

    function run() public {
        // Get the admin address from env var or use the msg.sender as fallback
        address admin = msg.sender;
        try vm.envAddress("ADMIN_ADDRESS") returns (address addr) {
            admin = addr;
        } catch {
            // Using msg.sender as admin (the account specified with --account flag)
        }

        // Get PasifikaTreasury address if deployed
        address payable treasuryAddress;
        try vm.envAddress("PASIFIKA_TREASURY_ADDRESS") returns (address addr) {
            treasuryAddress = payable(addr);
            treasury = PasifikaTreasury(treasuryAddress);
            console.log("Using existing PasifikaTreasury at:", treasuryAddress);
        } catch {
            // Deploy new PasifikaTreasury
            vm.broadcast();
            treasury = new PasifikaTreasury(admin);
            treasuryAddress = payable(address(treasury));
            console.log("Deployed new PasifikaTreasury at:", treasuryAddress);
        }

        // Deploy PasifikaMembership
        vm.broadcast();
        membership = new PasifikaMembership(treasuryAddress);

        // Add membership as fee collector to treasury
        vm.broadcast();
        treasury.addFeeCollector(address(membership));

        console.log("PasifikaMembership deployed at:", address(membership));
    }
}
