// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {PasifikaDAO} from "../src/PasifikaDAO.sol";
import {PSFToken} from "../src/PSFToken.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract PasifikaDAOScript is Script {
    PasifikaDAO public dao;
    TimelockController public timelock;
    
    // Timelock parameters
    uint256 public constant MIN_DELAY = 2 days;
    
    // DAO parameters
    uint48 public constant VOTING_DELAY = 1; // 1 block
    uint32 public constant VOTING_PERIOD = 50400; // ~1 week (assuming 12 sec blocks)
    uint256 public constant PROPOSAL_THRESHOLD = 100e18; // 100 tokens
    uint256 public constant QUORUM_PERCENTAGE = 4; // 4%

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        
        // Get the PSF token address - this should be deployed first
        address psfTokenAddress = vm.envAddress("PSF_TOKEN_ADDRESS");
        PSFToken token = PSFToken(psfTokenAddress);
        
        // Set up timelock controller
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        
        // Initially set deployer as proposer and executor, will be updated after DAO deployment
        proposers[0] = msg.sender;
        executors[0] = address(0); // Use the zero address to allow any address to execute
        
        timelock = new TimelockController(
            MIN_DELAY,
            proposers,
            executors,
            msg.sender // Admin
        );
        
        // Deploy DAO
        dao = new PasifikaDAO(
            "Pasifika DAO",
            token,
            timelock,
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD,
            QUORUM_PERCENTAGE
        );
        
        // Update timelock roles to give control to the DAO
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.TIMELOCK_ADMIN_ROLE();
        
        timelock.grantRole(proposerRole, address(dao));
        timelock.revokeRole(proposerRole, msg.sender);
        timelock.revokeRole(adminRole, msg.sender);
        
        console.log("PasifikaDAO deployed at:", address(dao));
        console.log("TimelockController deployed at:", address(timelock));

        vm.stopBroadcast();
    }
}
