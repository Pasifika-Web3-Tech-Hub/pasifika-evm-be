// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { PasifikaMoneyTransfer } from "../src/PasifikaMoneyTransfer.sol";
import { ArbitrumTokenAdapter } from "../src/ArbitrumTokenAdapter.sol";
import { PasifikaArbitrumNode } from "../src/PasifikaArbitrumNode.sol";
import { PasifikaTreasury } from "../src/PasifikaTreasury.sol";
import { PasifikaMembership } from "../src/PasifikaMembership.sol";

/**
 * @title PasifikaMoneyTransferScript
 * @dev Deployment script for the PasifikaMoneyTransfer contract for Arbitrum
 */
contract PasifikaMoneyTransferScript is Script {
    PasifikaMoneyTransfer public moneyTransfer;
    ArbitrumTokenAdapter public arbitrumTokenAdapter;
    PasifikaArbitrumNode public arbitrumNode;
    PasifikaTreasury public treasury;
    PasifikaMembership public membership;

    function run() public {
        // Using wallet alias from the keystore instead of private key
        address payable deployer = payable(msg.sender);
        address payable treasuryWallet = payable(vm.envAddress("TREASURY_WALLET"));

        console.log("Deployer address:", deployer);
        console.log("Treasury wallet:", treasuryWallet);
        console.log("Starting PasifikaMoneyTransfer deployment on Arbitrum...");

        // Get ArbitrumTokenAdapter address if deployed
        address payable arbitrumTokenAdapterAddress;
        try vm.envAddress("ARBITRUM_TOKEN_ADAPTER_ADDRESS") returns (address addr) {
            arbitrumTokenAdapterAddress = payable(addr);
            console.log("Using existing ArbitrumTokenAdapter at:", arbitrumTokenAdapterAddress);
        } catch {
            // Deploy new ArbitrumTokenAdapter
            vm.startBroadcast();
            arbitrumTokenAdapter = new ArbitrumTokenAdapter(deployer);
            arbitrumTokenAdapterAddress = payable(address(arbitrumTokenAdapter));
            vm.stopBroadcast();
            console.log("Deployed new ArbitrumTokenAdapter at:", arbitrumTokenAdapterAddress);
        }

        // Get PasifikaArbitrumNode address if deployed
        address payable arbitrumNodeAddress;
        try vm.envAddress("ARBITRUM_NODE_ADDRESS") returns (address addr) {
            arbitrumNodeAddress = payable(addr);
            console.log("Using existing PasifikaArbitrumNode at:", arbitrumNodeAddress);
        } catch {
            // Deploy new PasifikaArbitrumNode
            vm.startBroadcast();
            arbitrumNode = new PasifikaArbitrumNode(deployer);
            arbitrumNodeAddress = payable(address(arbitrumNode));
            vm.stopBroadcast();
            console.log("Deployed new PasifikaArbitrumNode at:", arbitrumNodeAddress);
        }

        // Get PasifikaTreasury address if deployed
        address payable treasuryAddress;
        try vm.envAddress("ARBITRUM_TREASURY_ADDRESS") returns (address addr) {
            treasuryAddress = payable(addr);
            console.log("Using existing PasifikaTreasury at:", treasuryAddress);
        } catch {
            // Deploy new PasifikaTreasury
            vm.startBroadcast();
            treasury = new PasifikaTreasury(deployer);
            treasuryAddress = payable(address(treasury));
            vm.stopBroadcast();
            console.log("Deployed new PasifikaTreasury at:", treasuryAddress);
        }

        // Deploy PasifikaMoneyTransfer
        vm.startBroadcast();

        moneyTransfer = new PasifikaMoneyTransfer(arbitrumTokenAdapterAddress, treasuryWallet, treasuryAddress);
        console.log("PasifikaMoneyTransfer deployed at:", address(moneyTransfer));

        // Add money transfer as fee collector to treasury
        PasifikaTreasury(treasuryAddress).addFeeCollector(address(moneyTransfer));
        moneyTransfer.initializeTreasury();
        console.log("Added MoneyTransfer as fee collector to Treasury");

        // Set standard fee to 1%
        moneyTransfer.setBaseFeePercent(100); // 1%
        console.log("Set base fee to 1%");

        // Set member fee to 0.5%
        moneyTransfer.setMemberFeePercent(50); // 0.5%
        console.log("Set member fee to 0.5%");

        // Set validator fee to 0.25%
        moneyTransfer.setValidatorFeePercent(25); // 0.25%
        console.log("Set validator fee to 0.25%");

        // Check if Membership is already deployed
        address payable membershipAddress;
        try vm.envAddress("ARBITRUM_MEMBERSHIP_ADDRESS") returns (address addr) {
            membershipAddress = payable(addr);
            membership = PasifikaMembership(membershipAddress);
            console.log("Using existing PasifikaMembership at:", membershipAddress);
        } catch {
            // Deploy new Membership contract if needed
            vm.startBroadcast();
            membership = new PasifikaMembership(payable(treasuryAddress));
            membershipAddress = payable(address(membership));
            console.log("Deployed new PasifikaMembership at:", membershipAddress);
        }

        // Set membership contract
        moneyTransfer.setMembershipContract(membershipAddress);
        console.log("Set membership contract for MoneyTransfer");

        // Set node contract for validators
        moneyTransfer.setNodeContract(arbitrumNodeAddress);
        console.log("Set node contract for MoneyTransfer");

        console.log("PasifikaMoneyTransfer deployment and integration completed successfully");

        vm.stopBroadcast();
    }
}
