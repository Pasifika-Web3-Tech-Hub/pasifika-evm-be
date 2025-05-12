// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { PasifikaMoneyTransfer } from "../src/PasifikaMoneyTransfer.sol";
import { ArbitrumTokenAdapter } from "../src/ArbitrumTokenAdapter.sol";
import { PasifikaTreasury } from "../src/PasifikaTreasury.sol";
import { PasifikaMembership } from "../src/PasifikaMembership.sol";

/**
 * @title PasifikaMoneyTransferArbitrumScript
 * @dev Deployment script for the PasifikaMoneyTransfer contract for Arbitrum
 */
contract PasifikaMoneyTransferArbitrumScript is Script {
    PasifikaMoneyTransfer public moneyTransfer;
    ArbitrumTokenAdapter public arbitrumTokenAdapter;
    PasifikaTreasury public treasury;
    PasifikaMembership public membership;

    function run() public {
        // Get admin address or use deployer as fallback
        address admin = msg.sender;
        try vm.envAddress("ADMIN_ADDRESS") returns (address addr) {
            admin = addr;
        } catch {
            // Fallback to the pasifika-account (as per the memory)
            try vm.envAddress("WALLET_ADDRESS") returns (address walletAddress) {
                admin = walletAddress;
                console.log("Using wallet address from env:", admin);
            } catch {
                // Using msg.sender as admin
                console.log("No admin address found. Using deployer address:", admin);
            }
        }
        
        // Get treasury wallet from environment
        address payable treasuryWallet = payable(vm.envAddress("TREASURY_WALLET"));

        console.log("Deployer address:", admin);
        console.log("Treasury wallet:", treasuryWallet);
        console.log("Starting PasifikaMoneyTransfer deployment on Arbitrum...");

        // Get ArbitrumTokenAdapter address
        address payable arbitrumTokenAdapterAddress;
        try vm.envAddress("ARBITRUM_TOKEN_ADAPTER_ADDRESS") returns (address addr) {
            arbitrumTokenAdapterAddress = payable(addr);
            console.log("Using existing ArbitrumTokenAdapter at:", arbitrumTokenAdapterAddress);
        } catch {
            revert("ArbitrumTokenAdapter address not found. Please deploy it first.");
        }

        // Get PasifikaTreasury address
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
                revert("PasifikaTreasury address not found. Please deploy it first.");
            }
        }

        // Deploy PasifikaMoneyTransfer
        console.log("Deploying PasifikaMoneyTransfer...");
        vm.broadcast();
        moneyTransfer = new PasifikaMoneyTransfer(
            arbitrumTokenAdapterAddress,
            treasuryWallet,
            treasuryAddress
        );
        
        console.log("PasifikaMoneyTransfer deployed at:", address(moneyTransfer));

        // Add money transfer as fee collector to treasury
        console.log("Adding MoneyTransfer as fee collector to Treasury...");
        vm.broadcast();
        treasury.addFeeCollector(address(moneyTransfer));
        
        // Initialize treasury integration
        console.log("Initializing treasury integration...");
        vm.broadcast();
        moneyTransfer.initializeTreasury();

        // Set standard fee to 1%
        console.log("Setting base fee to 1%...");
        vm.broadcast();
        moneyTransfer.setBaseFeePercent(100); // 1%

        // Set member fee to 0.5%
        console.log("Setting member fee to 0.5%...");
        vm.broadcast();
        moneyTransfer.setMemberFeePercent(50); // 0.5%

        // Set validator fee to 0.25%
        console.log("Setting validator fee to 0.25%...");
        vm.broadcast();
        moneyTransfer.setValidatorFeePercent(25); // 0.25%

        // Check if Membership is already deployed
        address payable membershipAddress;
        try vm.envAddress("ARBITRUM_MEMBERSHIP_ADDRESS") returns (address addr) {
            membershipAddress = payable(addr);
            membership = PasifikaMembership(membershipAddress);
            console.log("Using existing PasifikaMembership at:", membershipAddress);
            
            // Set membership contract
            console.log("Setting membership contract...");
            vm.broadcast();
            moneyTransfer.setMembershipContract(membershipAddress);
        } catch {
            try vm.envAddress("PASIFIKA_MEMBERSHIP_ADDRESS") returns (address addr) {
                membershipAddress = payable(addr);
                membership = PasifikaMembership(membershipAddress);
                console.log("Using existing PasifikaMembership at:", membershipAddress);
                
                // Set membership contract
                console.log("Setting membership contract...");
                vm.broadcast();
                moneyTransfer.setMembershipContract(membershipAddress);
            } catch {
                console.log("No membership contract found, skipping integration");
            }
        }

        console.log("PasifikaMoneyTransfer deployment and integration completed successfully");
    }
}
