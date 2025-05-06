// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PasifikaMoneyTransfer} from "../src/PasifikaMoneyTransfer.sol";
import {ArbitrumTokenAdapter} from "../src/ArbitrumTokenAdapter.sol";
import {PasifikaArbitrumNode} from "../src/PasifikaArbitrumNode.sol";
import {PasifikaTreasury} from "../src/PasifikaTreasury.sol";
import {PasifikaMembership} from "../src/PasifikaMembership.sol";

/**
 * @title PasifikaMoneyTransferAliasScript
 * @dev Deployment script for the PasifikaMoneyTransfer contract for Arbitrum using wallet alias
 */
contract PasifikaMoneyTransferAliasScript is Script {
    PasifikaMoneyTransfer public moneyTransfer;
    ArbitrumTokenAdapter public arbitrumTokenAdapter;
    PasifikaArbitrumNode public arbitrumNode;
    PasifikaTreasury public treasury;
    PasifikaMembership public membership;

    function run() public {
        // Using wallet alias from the keystore instead of private key
        address payable deployer = payable(msg.sender);
        address payable treasuryWallet;
        
        console.log("Deployer address:", deployer);
        
        try vm.envAddress("TREASURY_WALLET") returns (address addr) {
            treasuryWallet = payable(addr);
            console.log("Treasury wallet:", treasuryWallet);
        } catch {
            // Use deployer as treasury wallet if not set
            treasuryWallet = deployer;
            console.log("Treasury wallet not set, using deployer address:", treasuryWallet);
        }
        
        console.log("Starting PasifikaMoneyTransfer deployment on Arbitrum...");

        // Get ArbitrumTokenAdapter address if deployed
        address payable arbitrumTokenAdapterAddress;
        try vm.envAddress("ARBITRUM_TOKEN_ADAPTER_ADDRESS") returns (address addr) {
            arbitrumTokenAdapterAddress = payable(addr);
            console.log("Using existing ArbitrumTokenAdapter at:", arbitrumTokenAdapterAddress);
        } catch {
            // Error out if token adapter not found
            console.log("Error: ArbitrumTokenAdapter address not found. Please deploy it first.");
            return;
        }

        // Get PasifikaArbitrumNode address if deployed
        address payable arbitrumNodeAddress;
        try vm.envAddress("ARBITRUM_NODE_ADDRESS") returns (address addr) {
            arbitrumNodeAddress = payable(addr);
            console.log("Using existing PasifikaArbitrumNode at:", arbitrumNodeAddress);
        } catch {
            // Error out if node not found
            console.log("Error: PasifikaArbitrumNode address not found. Please deploy it first.");
            return;
        }

        // Get PasifikaTreasury address if deployed
        address payable treasuryAddress;
        try vm.envAddress("ARBITRUM_TREASURY_ADDRESS") returns (address addr) {
            treasuryAddress = payable(addr);
            console.log("Using existing PasifikaTreasury at:", treasuryAddress);
        } catch {
            try vm.envAddress("PASIFIKA_TREASURY_ADDRESS") returns (address addr) {
                treasuryAddress = payable(addr);
                console.log("Using existing PasifikaTreasury at:", treasuryAddress);
            } catch {
                // Error out if treasury not found
                console.log("Error: PasifikaTreasury address not found. Please deploy it first.");
                return;
            }
        }

        // Deploy PasifikaMoneyTransfer
        vm.startBroadcast();

        moneyTransfer = new PasifikaMoneyTransfer(arbitrumTokenAdapterAddress, treasuryWallet, treasuryAddress);
        console.log("PasifikaMoneyTransfer deployed at:", address(moneyTransfer));

        // Skip adding money transfer as fee collector to treasury (will be done by admin manually)
        // This avoids access control issues during deployment
        console.log("NOTE: To complete setup, the admin should manually:");
        console.log("1. Add money transfer as fee collector to treasury using the treasury's addFeeCollector function");
        console.log("2. Initialize the treasury connection using moneyTransfer.initializeTreasury()");
        console.log("3. Set fees using setBaseFeePercent, setMemberFeePercent, and setValidatorFeePercent");
        console.log("4. Set membership and node contracts using setMembershipContract and setNodeContract");

        // Skip remaining integration steps as they could cause access control issues
        
        console.log("PasifikaMoneyTransfer deployment completed successfully");
        console.log("Further setup required by admin with proper permissions");

        vm.stopBroadcast();
    }
}
