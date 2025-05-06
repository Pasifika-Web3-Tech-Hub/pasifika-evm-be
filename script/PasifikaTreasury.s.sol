// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { PasifikaTreasury } from "../src/PasifikaTreasury.sol";
import { PasifikaMarketplace } from "../src/PasifikaMarketplace.sol";
import { PasifikaMoneyTransfer } from "../src/PasifikaMoneyTransfer.sol";
import { PasifikaMembership } from "../src/PasifikaMembership.sol";

/**
 * @title PasifikaTreasuryScript
 * @dev Deployment script for the PasifikaTreasury contract
 */
contract PasifikaTreasuryScript is Script {
    PasifikaTreasury public treasury;

    function run() public {
        // Using the Foundry wallet directly instead of private key from env
        vm.startBroadcast();

        // Explicitly use the pasifika-account address as the admin
        address pasifikaAccount = 0x58a60a9cBEDC8E7d3f9ec9a96312BEDe8fc147b8;
        console.log("Deploying with pasifika-account address:", pasifikaAccount);

        // Deploy the treasury contract with the pasifika-account as admin
        treasury = new PasifikaTreasury(pasifikaAccount);
        console.log("Treasury deployed with admin:", pasifikaAccount);

        // Check if Marketplace is already deployed
        address payable marketplaceAddress;
        try vm.envAddress("PASIFIKA_MARKETPLACE_ADDRESS") returns (address addr) {
            marketplaceAddress = payable(addr);
            if (marketplaceAddress != address(treasury)) {
                console.log("Registering existing marketplace at:", marketplaceAddress);
                // Register marketplace as fee collector
                treasury.addFeeCollector(marketplaceAddress);
                try PasifikaMarketplace(marketplaceAddress).initializeTreasury() {
                    console.log("Marketplace initialized with treasury");
                } catch {
                    console.log("Failed to initialize marketplace with treasury");
                }
            } else {
                console.log("Skipping marketplace registration (same as treasury address)");
            }
        } catch {
            console.log("No marketplace found to register as fee collector");
        }

        // Check if MoneyTransfer is already deployed
        address payable moneyTransferAddress;
        try vm.envAddress("PASIFIKA_MONEY_TRANSFER_ADDRESS") returns (address addr) {
            moneyTransferAddress = payable(addr);
            if (moneyTransferAddress != address(treasury)) {
                console.log("Registering existing money transfer at:", moneyTransferAddress);
                // Register money transfer as fee collector
                treasury.addFeeCollector(moneyTransferAddress);
                try PasifikaMoneyTransfer(moneyTransferAddress).initializeTreasury() {
                    console.log("Money transfer initialized with treasury");
                } catch {
                    console.log("Failed to initialize money transfer with treasury");
                }
            } else {
                console.log("Skipping money transfer registration (same as treasury address)");
            }
        } catch {
            console.log("No money transfer found to register as fee collector");
        }

        // Check if Membership is already deployed, if not - deploy it
        address payable membershipAddress;
        try vm.envAddress("PASIFIKA_MEMBERSHIP_ADDRESS") returns (address addr) {
            membershipAddress = payable(addr);
            console.log("Using existing PasifikaMembership at:", membershipAddress);
        } catch {
            // Get RIF token address if available
            address rifTokenAddress;
            try vm.envAddress("RIF_TOKEN_ADDRESS") returns (address addr) {
                rifTokenAddress = addr;
                console.log("Using RIF token at:", rifTokenAddress);
            } catch {
                console.log("RIF_TOKEN_ADDRESS not set, will use a mock address if needed");
                rifTokenAddress = address(0x9876); // Placeholder, only used for new deployments
            }
            // Deploy new Membership connected to this treasury
            PasifikaMembership membership = new PasifikaMembership(payable(address(treasury)));
            membershipAddress = payable(address(membership));
            console.log("Deployed new PasifikaMembership at:", membershipAddress);
            vm.setEnv("PASIFIKA_MEMBERSHIP_ADDRESS", vm.toString(membershipAddress));
        }

        // Create standard funds
        treasury.createFund("Development", 2000); // 20%
        treasury.createFund("Community", 2000); // 20%
        treasury.createFund("Marketing", 1500); // 15%
        treasury.createFund("Operations", 2500); // 25%
        treasury.createFund("Reserve", 2000); // 20%

        console.log("Treasury setup completed with default funds");
        console.log("PasifikaTreasury deployed at:", address(treasury));
        vm.stopBroadcast();
    }
}
