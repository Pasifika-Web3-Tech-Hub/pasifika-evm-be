// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {FeeManager} from "../src/FeeManager.sol";

contract FeeManagerScript is Script {
    FeeManager public feeManager;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        
        // Get addresses from environment or use defaults
        address treasury = vm.envOr("TREASURY_ADDRESS", address(0x1));
        address communityFund = vm.envOr("COMMUNITY_FUND_ADDRESS", address(0x2));
        
        // Deploy FeeManager
        feeManager = new FeeManager(treasury, communityFund);
        
        // Grant marketplace role if marketplace address is provided
        address marketplace = vm.envOr("MARKETPLACE_ADDRESS", address(0));
        if (marketplace != address(0)) {
            feeManager.grantRole(feeManager.MARKETPLACE_ROLE(), marketplace);
        }
        
        // Set accepted token if provided
        address acceptedToken = vm.envOr("ACCEPTED_TOKEN_ADDRESS", address(0));
        if (acceptedToken != address(0)) {
            feeManager.updateAcceptedToken(acceptedToken);
        }
        
        console.log("FeeManager deployed at:", address(feeManager));

        vm.stopBroadcast();
    }
}
