// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {PSFToken} from "../src/PSFToken.sol";

contract PSFTokenScript is Script {
    PSFToken public psfToken;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        psfToken = new PSFToken();

        vm.stopBroadcast();
    }
}
