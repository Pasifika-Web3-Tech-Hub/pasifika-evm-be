// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {PasifikaTreasury} from "../src/PasifikaTreasury.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title PasifikaTreasuryScript
 * @dev Deployment script for the PasifikaTreasury contract
 */
contract PasifikaTreasuryScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address pasifikaTokenAddress = vm.envAddress("PSF_TOKEN_ADDRESS");
        address treasuryWalletAddress = vm.envAddress("TREASURY_WALLET_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        PasifikaTreasury treasury = new PasifikaTreasury(
            IERC20(pasifikaTokenAddress),
            treasuryWalletAddress
        );
        
        vm.stopBroadcast();
        
        console.log("PasifikaTreasury deployed at: ", address(treasury));
    }
}
