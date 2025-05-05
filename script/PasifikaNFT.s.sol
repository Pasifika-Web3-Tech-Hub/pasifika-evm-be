// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PasifikaNFT} from "../src/PasifikaNFT.sol";
import {PasifikaMembership} from "../src/PasifikaMembership.sol";
import {PasifikaTreasury} from "../src/PasifikaTreasury.sol";

/**
 * @title PasifikaNFTScript
 * @dev Deployment script for the consolidated PasifikaNFT contract
 */
contract PasifikaNFTScript is Script {
    PasifikaNFT public pasifikaNFT;
    PasifikaMembership public membership;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Parameters
        string memory name = "Pasifika NFT";
        string memory symbol = "PASIFIKA";
        string memory baseURI = "https://pasifika.io/metadata/";

        // Get PasifikaTreasury address if deployed
        address payable treasuryAddress;
        try vm.envAddress("PASIFIKA_TREASURY_ADDRESS") returns (address addr) {
            treasuryAddress = payable(addr);
            console.log("Using existing PasifikaTreasury at:", treasuryAddress);
        } catch {
            // No treasury deployed yet, we'll let other scripts handle this
            console.log("No treasury found, continuing without membership integration");
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

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the NFT contract
        pasifikaNFT = new PasifikaNFT(name, symbol, baseURI);

        // Set default royalty to 1%
        pasifikaNFT.setDefaultRoyalty(100);

        // Set member royalty to 0.5%
        pasifikaNFT.setMemberRoyalty(50);

        // Check if Membership is already deployed
        address payable membershipAddress;
        try vm.envAddress("PASIFIKA_MEMBERSHIP_ADDRESS") returns (address addr) {
            membershipAddress = payable(addr);
            console.log("Using existing PasifikaMembership at:", membershipAddress);

            // Link NFT to membership
            pasifikaNFT.setMembershipContract(membershipAddress);
        } catch {
            // If treasury exists, deploy membership
            if (treasuryAddress != address(0)) {
                vm.startBroadcast();
                membership = new PasifikaMembership(treasuryAddress);
                membershipAddress = payable(address(membership));
                console.log("Deployed new PasifikaMembership at:", membershipAddress);

                // Link NFT to membership
                pasifikaNFT.setMembershipContract(membershipAddress);
            }
        }

        console.log("PasifikaNFT deployed at:", address(pasifikaNFT));

        vm.stopBroadcast();
    }
}
