// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {PSFStaking} from "../src/PSFStaking.sol";
import {PSFToken} from "../src/PSFToken.sol";

contract PSFStakingScript is Script {
    PSFStaking public psfStaking;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // For deployment script, replace these with actual addresses when deploying
        address psfTokenAddress = address(0); // Replace with actual PSF token address
        address adminAddress = msg.sender;
        address rewardsDistributorAddress = msg.sender; // Can be changed later

        // Check if PSFToken is already deployed
        if (psfTokenAddress == address(0)) {
            // Deploy a new PSFToken 
            PSFToken psfToken = new PSFToken();
            psfTokenAddress = address(psfToken);
            
            // Mint some tokens to admin for testing
            psfToken.mint(adminAddress, 1_000_000_000 * 10**18); // 1 billion tokens
            
            console.log("Deployed PSFToken at:", psfTokenAddress);
        }

        // Deploy PSFStaking with the required parameters
        psfStaking = new PSFStaking(
            psfTokenAddress,
            adminAddress,
            rewardsDistributorAddress
        );
        console.log("Deployed PSFStaking at:", address(psfStaking));

        vm.stopBroadcast();
    }
}
