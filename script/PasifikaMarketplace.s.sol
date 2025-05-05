// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PasifikaMarketplace} from "../src/PasifikaMarketplace.sol";
import {ArbitrumTokenAdapter} from "../src/ArbitrumTokenAdapter.sol";
import {PasifikaNFT} from "../src/PasifikaNFT.sol";
import {PasifikaTreasury} from "../src/PasifikaTreasury.sol";
import {PasifikaMembership} from "../src/PasifikaMembership.sol";

/**
 * @title PasifikaMarketplaceScript
 * @dev Deployment script for the PasifikaMarketplace that works with RSK native token (RBTC)
 */
contract PasifikaMarketplaceScript is Script {
    PasifikaMarketplace public marketplace;
    ArbitrumTokenAdapter public arbitrumTokenAdapter;
    PasifikaNFT public pasifikaNFT;
    PasifikaTreasury public treasury;
    PasifikaMembership public membership;

    function run() public {
        // Using wallet alias from the keystore instead of private key
        address payable deployer = payable(msg.sender);
        address payable feeRecipient = payable(vm.envAddress("FEE_RECIPIENT"));
        address payable treasuryWallet = payable(vm.envAddress("TREASURY_WALLET"));

        console.log("Deployer address:", deployer);

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

        // Get RIF token address for membership if needed
        address rifTokenAddress;
        try vm.envAddress("RIF_TOKEN_ADDRESS") returns (address addr) {
            rifTokenAddress = addr;
            console.log("Using RIF token at:", rifTokenAddress);
        } catch {
            console.log("RIF_TOKEN_ADDRESS not set, will use a mock address for any new contracts");
            rifTokenAddress = address(0x9876); // Placeholder, only used for new deployments
        }

        // Deploy marketplace
        vm.startBroadcast();

        marketplace =
            new PasifikaMarketplace(feeRecipient, treasuryWallet, arbitrumTokenAdapterAddress, treasuryAddress);

        // Add marketplace as fee collector to treasury
        PasifikaTreasury(treasuryAddress).addFeeCollector(address(marketplace));
        marketplace.initializeTreasury();

        // Check if NFT is already deployed
        address nftAddress;
        try vm.envAddress("ARBITRUM_NFT_ADDRESS") returns (address addr) {
            nftAddress = addr;
            console.log("Using existing PasifikaNFT at:", nftAddress);

            // Grant marketplace minter role
            PasifikaNFT(nftAddress).grantRole(keccak256("MINTER_ROLE"), address(marketplace));
        } catch {
            // Deploy new NFT contract if needed
            string memory name = "Pasifika NFT";
            string memory symbol = "PASIFIKA";
            string memory baseURI = "https://pasifika.io/metadata/";

            pasifikaNFT = new PasifikaNFT(name, symbol, baseURI);
            pasifikaNFT.setDefaultRoyalty(100); // 1% default royalty
            nftAddress = address(pasifikaNFT);
            console.log("Deployed new PasifikaNFT at:", nftAddress);

            // Grant marketplace minter role
            pasifikaNFT.grantRole(keccak256("MINTER_ROLE"), address(marketplace));
        }

        // Check if Membership is already deployed
        address payable membershipAddress;
        try vm.envAddress("ARBITRUM_MEMBERSHIP_ADDRESS") returns (address addr) {
            membershipAddress = payable(addr);
            console.log("Using existing PasifikaMembership at:", membershipAddress);
        } catch {
            // Deploy new Membership contract if needed
            vm.startBroadcast();
            membership = new PasifikaMembership(treasuryAddress);
            membershipAddress = payable(address(membership));
            console.log("Deployed new PasifikaMembership at:", membershipAddress);
        }

        // Set membership contract in marketplace
        marketplace.setMembershipContract(membershipAddress);

        console.log("PasifikaMarketplace deployed at:", address(marketplace));
        console.log("Integration completed");

        vm.stopBroadcast();
    }
}
