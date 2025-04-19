// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {PasifikaMarketplace} from "../src/PasifikaMarketplace.sol";

contract PasifikaMarketplaceScript is Script {
    PasifikaMarketplace public pasifikaMarketplace;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Using placeholder addresses for psfToken and feeManager
        // These should be replaced with actual contract addresses when deploying to a network
        address psfToken = address(0x1111111111111111111111111111111111111111);
        address feeManager = address(0x2222222222222222222222222222222222222222);
        
        pasifikaMarketplace = new PasifikaMarketplace(psfToken, feeManager);

        vm.stopBroadcast();
    }
}
