// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {DigitalContentNFT} from "../src/DigitalContentNFT.sol";

contract DigitalContentNFTScript is Script {
    DigitalContentNFT public digitalContentNFT;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy DigitalContentNFT
        digitalContentNFT = new DigitalContentNFT();
        
        // Set up roles if needed
        address contentManager = vm.envOr("CONTENT_MANAGER_ADDRESS", address(0));
        if (contentManager != address(0)) {
            digitalContentNFT.grantRole(digitalContentNFT.CONTENT_MANAGER_ROLE(), contentManager);
        }
        
        address culturalAuthority = vm.envOr("CULTURAL_AUTHORITY_ADDRESS", address(0));
        if (culturalAuthority != address(0)) {
            digitalContentNFT.grantRole(digitalContentNFT.CULTURAL_AUTHORITY_ROLE(), culturalAuthority);
        }
        
        console.log("DigitalContentNFT deployed at:", address(digitalContentNFT));

        vm.stopBroadcast();
    }
}
