// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PasifikaMembership} from "../src/PasifikaMembership.sol";
import {PasifikaTreasury} from "../src/PasifikaTreasury.sol";

/**
 * @title PasifikaMembershipScript
 * @dev Deployment script for the PasifikaMembership contract
 */
contract PasifikaMembershipScript is Script {
    PasifikaMembership public membership;
    PasifikaTreasury public treasury;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Get PasifikaTreasury address if deployed
        address payable treasuryAddress;
        try vm.envAddress("PASIFIKA_TREASURY_ADDRESS") returns (address addr) {
            treasuryAddress = payable(addr);
            treasury = PasifikaTreasury(treasuryAddress);
            console.log("Using existing PasifikaTreasury at:", treasuryAddress);
        } catch {
            // Deploy new PasifikaTreasury
            vm.startBroadcast(deployerPrivateKey);
            treasury = new PasifikaTreasury(msg.sender);
            treasuryAddress = payable(address(treasury));
            vm.stopBroadcast();
            console.log("Deployed new PasifikaTreasury at:", treasuryAddress);
        }

        // Deploy PasifikaMembership
        vm.startBroadcast(deployerPrivateKey);

        membership = new PasifikaMembership(treasuryAddress);

        // Add membership as fee collector to treasury
        treasury.addFeeCollector(address(membership));

        console.log("PasifikaMembership deployed at:", address(membership));

        vm.stopBroadcast();
    }
}
