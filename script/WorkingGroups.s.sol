// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {WorkingGroups} from "../src/WorkingGroups.sol";

contract WorkingGroupsScript is Script {
    WorkingGroups public workingGroups;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        
        // Get staking token address from environment or use default PSF token address
        address stakingToken = vm.envOr("STAKING_TOKEN_ADDRESS", address(0));
        require(stakingToken != address(0), "Staking token address must be provided");
        
        // Deploy WorkingGroups
        workingGroups = new WorkingGroups(stakingToken);
        
        // Set up additional roles
        address reputationManager = vm.envOr("REPUTATION_MANAGER_ADDRESS", address(0));
        if (reputationManager != address(0)) {
            workingGroups.grantRole(workingGroups.REPUTATION_MANAGER_ROLE(), reputationManager);
        }
        
        // Set staking configuration if needed
        bool configureStaking = vm.envOr("CONFIGURE_STAKING", false);
        if (configureStaking) {
            uint256 minStakeAmount = vm.envOr("MIN_STAKE_AMOUNT", 1000 * 10**18); // Default 1000 tokens
            uint256 stakeLockPeriod = vm.envOr("STAKE_LOCK_PERIOD", 7 days);
            uint256 slashingPenaltyPercent = vm.envOr("SLASHING_PENALTY_PERCENT", 10); // 10%
            
            workingGroups.configureStaking(
                minStakeAmount,
                stakeLockPeriod,
                slashingPenaltyPercent,
                true // staking active
            );
        }
        
        console.log("WorkingGroups deployed at:", address(workingGroups));

        vm.stopBroadcast();
    }
}
