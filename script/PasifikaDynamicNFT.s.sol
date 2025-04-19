// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {PasifikaDynamicNFT} from "../src/PasifikaDynamicNFT.sol";

contract PasifikaDynamicNFTScript is Script {
    PasifikaDynamicNFT public pasifikaDynamicNFT;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        pasifikaDynamicNFT = new PasifikaDynamicNFT();

        vm.stopBroadcast();
    }
}
