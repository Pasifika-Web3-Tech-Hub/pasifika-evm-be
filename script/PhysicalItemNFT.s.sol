// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {PhysicalItemNFT} from "../src/PhysicalItemNFT.sol";

contract PhysicalItemNFTScript is Script {
    PhysicalItemNFT public physicalItemNFT;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy PhysicalItemNFT
        physicalItemNFT = new PhysicalItemNFT();
        
        // Set up roles if needed
        address validator = vm.envOr("VALIDATOR_ADDRESS", address(0));
        if (validator != address(0)) {
            physicalItemNFT.grantRole(physicalItemNFT.VALIDATOR_ROLE(), validator);
        }
        
        address culturalAuthority = vm.envOr("CULTURAL_AUTHORITY_ADDRESS", address(0));
        if (culturalAuthority != address(0)) {
            physicalItemNFT.grantRole(physicalItemNFT.CULTURAL_AUTHORITY_ROLE(), culturalAuthority);
        }
        
        address supplyChain = vm.envOr("SUPPLY_CHAIN_ADDRESS", address(0));
        if (supplyChain != address(0)) {
            physicalItemNFT.grantRole(physicalItemNFT.SUPPLY_CHAIN_ROLE(), supplyChain);
        }
        
        address qualityVerifier = vm.envOr("QUALITY_VERIFIER_ADDRESS", address(0));
        if (qualityVerifier != address(0)) {
            physicalItemNFT.grantRole(physicalItemNFT.QUALITY_VERIFIER_ROLE(), qualityVerifier);
        }
        
        console.log("PhysicalItemNFT deployed at:", address(physicalItemNFT));

        vm.stopBroadcast();
    }
}
