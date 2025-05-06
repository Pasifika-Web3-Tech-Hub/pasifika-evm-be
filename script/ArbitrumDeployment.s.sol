// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { PasifikaTreasury } from "../src/PasifikaTreasury.sol";
import { PasifikaMembership } from "../src/PasifikaMembership.sol";
import { PasifikaMoneyTransfer } from "../src/PasifikaMoneyTransfer.sol";
import { PasifikaNFT } from "../src/PasifikaNFT.sol";
import { PasifikaMarketplace } from "../src/PasifikaMarketplace.sol";
import { ArbitrumTokenAdapter } from "../src/ArbitrumTokenAdapter.sol";
import { PasifikaArbitrumNode } from "../src/PasifikaArbitrumNode.sol";

/**
 * @title ArbitrumDeploymentScript
 * @dev Comprehensive deployment script for the Pasifika contracts on Arbitrum
 */
contract ArbitrumDeploymentScript is Script {
    // Contract instances
    ArbitrumTokenAdapter public tokenAdapter;
    PasifikaArbitrumNode public arbitrumNode;
    PasifikaTreasury public treasury;
    PasifikaMembership public membership;
    PasifikaMoneyTransfer public moneyTransfer;
    PasifikaNFT public nft;
    PasifikaMarketplace public marketplace;

    // Contract addresses
    address public tokenAdapterAddress;
    address public nodeAddress;
    address public treasuryAddress;
    address public membershipAddress;
    address public nftAddress;
    address public marketplaceAddress;
    address public moneyTransferAddress;

    function run() public {
        address treasuryWallet = vm.envAddress("TREASURY_WALLET");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");

        console.log("Beginning Pasifika deployment on Arbitrum");
        console.log("Treasury Wallet:", treasuryWallet);
        console.log("Fee Recipient:", feeRecipient);

        vm.startBroadcast();

        // 1. Deploy ArbitrumTokenAdapter
        console.log("1. Deploying ArbitrumTokenAdapter...");
        tokenAdapter = new ArbitrumTokenAdapter(msg.sender);
        tokenAdapterAddress = address(tokenAdapter);
        console.log("ArbitrumTokenAdapter deployed at:", tokenAdapterAddress);
        vm.setEnv("TOKEN_ADAPTER_ADDRESS", vm.toString(tokenAdapterAddress));

        // 2. Deploy PasifikaArbitrumNode
        console.log("2. Deploying PasifikaArbitrumNode...");
        arbitrumNode = new PasifikaArbitrumNode(msg.sender);
        nodeAddress = address(arbitrumNode);
        console.log("PasifikaArbitrumNode deployed at:", nodeAddress);
        vm.setEnv("NODE_ADDRESS", vm.toString(nodeAddress));

        // 3. Deploy PasifikaTreasury
        console.log("3. Deploying PasifikaTreasury...");
        treasury = new PasifikaTreasury(msg.sender);
        treasuryAddress = address(treasury);
        console.log("PasifikaTreasury deployed at:", treasuryAddress);
        vm.setEnv("TREASURY_ADDRESS", vm.toString(treasuryAddress));

        // Create standard funds
        treasury.createFund("Development", 2000); // 20%
        treasury.createFund("Community", 2000); // 20%
        treasury.createFund("Marketing", 1500); // 15%
        treasury.createFund("Operations", 2500); // 25%
        treasury.createFund("Reserve", 2000); // 20%
        console.log("Treasury setup completed with default funds");

        // 4. Deploy PasifikaMembership
        console.log("4. Deploying PasifikaMembership...");
        membership = new PasifikaMembership(payable(treasuryAddress));
        membershipAddress = address(membership);
        console.log("PasifikaMembership deployed at:", membershipAddress);
        vm.setEnv("MEMBERSHIP_ADDRESS", vm.toString(membershipAddress));

        // 5. Deploy PasifikaNFT
        console.log("5. Deploying PasifikaNFT...");
        nft = new PasifikaNFT("Pasifika NFT", "PNFT", "https://api.pasifika.io/metadata/");
        nftAddress = address(nft);
        console.log("PasifikaNFT deployed at:", nftAddress);
        vm.setEnv("NFT_ADDRESS", vm.toString(nftAddress));

        // Connect NFT to node contract
        nft.setNodeContract(payable(nodeAddress));
        console.log("Connected NFT to Arbitrum Node");

        // 6. Deploy PasifikaMoneyTransfer
        console.log("6. Deploying PasifikaMoneyTransfer...");
        moneyTransfer =
            new PasifikaMoneyTransfer(payable(tokenAdapterAddress), payable(treasuryWallet), payable(treasuryAddress));
        moneyTransferAddress = address(moneyTransfer);
        console.log("PasifikaMoneyTransfer deployed at:", moneyTransferAddress);
        vm.setEnv("MONEY_TRANSFER_ADDRESS", vm.toString(moneyTransferAddress));

        // Connect MoneyTransfer to other contracts
        moneyTransfer.setNodeContract(payable(nodeAddress));
        moneyTransfer.setMembershipContract(payable(membershipAddress));

        // Register money transfer as fee collector in treasury
        treasury.addFeeCollector(payable(moneyTransferAddress));
        console.log("Registered MoneyTransfer as fee collector in Treasury");

        // 7. Deploy PasifikaMarketplace
        console.log("7. Deploying PasifikaMarketplace...");
        marketplace = new PasifikaMarketplace(
            payable(feeRecipient), payable(treasuryWallet), payable(tokenAdapterAddress), payable(treasuryAddress)
        );
        marketplaceAddress = address(marketplace);
        console.log("PasifikaMarketplace deployed at:", marketplaceAddress);
        vm.setEnv("MARKETPLACE_ADDRESS", vm.toString(marketplaceAddress));

        // Connect Marketplace to other contracts
        marketplace.setNodeContract(payable(nodeAddress));
        marketplace.setMembershipContract(payable(membershipAddress));

        // Register marketplace as fee collector in treasury
        treasury.addFeeCollector(payable(marketplaceAddress));
        console.log("Registered Marketplace as fee collector in Treasury");

        // Initialize connections between contracts
        moneyTransfer.initializeTreasury();
        marketplace.initializeTreasury();

        console.log("All contracts deployed and integrated successfully on Arbitrum");
        vm.stopBroadcast();
    }
}
