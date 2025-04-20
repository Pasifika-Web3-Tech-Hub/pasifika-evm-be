// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {MockToken} from "../src/MockToken.sol";

contract MockTokenScript is Script {
    MockToken public mockToken;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        mockToken = new MockToken("Pasifika Test Token", "TPSF");
        
        // Mint initial tokens if needed
        mockToken.mint(msg.sender, 1000000e18);

        vm.stopBroadcast();
    }
}
