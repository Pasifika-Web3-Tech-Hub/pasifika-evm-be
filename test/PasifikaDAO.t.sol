// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import "../src/PasifikaDAO.sol";
import "../src/MockToken.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

contract PasifikaDAOTest is Test {
    PasifikaDAO public dao;
    MockToken public token;
    TimelockController public timelock;

    address public admin = address(1);
    address public proposer = address(2);
    address public executor = address(3);
    address public voter1 = address(4);
    address public voter2 = address(5);

    // Initial DAO configuration
    uint48 public constant VOTING_DELAY = 1; // 1 block
    uint32 public constant VOTING_PERIOD = 50400; // ~1 week (assuming 12 sec blocks)
    uint256 public constant PROPOSAL_THRESHOLD = 100e18; // 100 tokens
    uint256 public constant QUORUM_PERCENTAGE = 4; // 4%
    uint256 public constant MIN_DELAY = 2 days; // Timelock delay

    function setUp() public {
        // Setup users
        vm.startPrank(admin);
        
        // Deploy token
        token = new MockToken("Pasifika Token", "PSF");
        token.mint(admin, 1000000e18);
        token.mint(proposer, 200000e18);
        token.mint(voter1, 100000e18);
        token.mint(voter2, 50000e18);
        
        // Delegate votes
        token.delegate(admin);
        vm.stopPrank();
        
        vm.prank(proposer);
        token.delegate(proposer);
        
        vm.prank(voter1);
        token.delegate(voter1);
        
        vm.prank(voter2);
        token.delegate(voter2);
        
        // Move forward one block for voting power checkpointing
        vm.roll(block.number + 1);
        
        // Deploy timelock controller
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = proposer;
        executors[0] = executor;
        
        vm.startPrank(admin);
        timelock = new TimelockController(MIN_DELAY, proposers, executors, admin);
        
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
        
        // Setup roles on the timelock
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.TIMELOCK_ADMIN_ROLE();
        
        timelock.grantRole(proposerRole, address(dao));
        timelock.revokeRole(proposerRole, proposer);
        timelock.revokeRole(adminRole, admin);
        vm.stopPrank();
    }

    function testInitialSetup() public {
        assertEq(dao.name(), "Pasifika DAO");
        assertEq(dao.votingDelay(), VOTING_DELAY);
        assertEq(dao.votingPeriod(), VOTING_PERIOD);
        assertEq(dao.proposalThreshold(), PROPOSAL_THRESHOLD);
        assertEq(address(dao.token()), address(token));
        assertTrue(dao.hasRole(dao.ADMIN_ROLE(), admin));
        assertTrue(dao.hasRole(dao.MODERATOR_ROLE(), admin));
    }
    
    function testProposalCreation() public {
        // Create a proposal
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Proposal #1: Test proposal";
        
        targets[0] = address(token);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(token.mint.selector, voter2, 10000e18);
        
        // Verify that the admin has enough voting power
        uint256 votingPower = token.getVotes(admin);
        assertGe(votingPower, dao.proposalThreshold());
        
        // Submit the proposal
        vm.prank(admin);
        uint256 proposalId = dao.propose(targets, values, calldatas, description);
        
        // Verify proposal state is Pending
        assertEq(uint(dao.state(proposalId)), uint(IGovernor.ProposalState.Pending));
        
        // Move forward by the voting delay to make the proposal Active
        vm.roll(block.number + VOTING_DELAY + 1);
        
        // Verify proposal state is now Active
        assertEq(uint(dao.state(proposalId)), uint(IGovernor.ProposalState.Active));
        
        // Cast votes
        vm.prank(admin);
        dao.castVote(proposalId, 1); // Vote in favor
        
        vm.prank(proposer);
        dao.castVote(proposalId, 1); // Vote in favor
        
        vm.prank(voter1);
        dao.castVote(proposalId, 0); // Vote against
        
        // Fast forward to end of voting period
        vm.roll(block.number + VOTING_PERIOD);
        
        // Verify proposal state is Succeeded
        assertEq(uint(dao.state(proposalId)), uint(IGovernor.ProposalState.Succeeded));
    }
    
    function testAdminFunctions() public {
        // Test updating voting delay
        uint48 newVotingDelay = 10;
        vm.prank(admin);
        dao.setVotingDelay(newVotingDelay);
        assertEq(dao.votingDelay(), newVotingDelay);
        
        // Test updating voting period
        uint32 newVotingPeriod = 100000;
        vm.prank(admin);
        dao.setVotingPeriod(newVotingPeriod);
        assertEq(dao.votingPeriod(), newVotingPeriod);
        
        // Test updating proposal threshold
        uint256 newProposalThreshold = 200e18;
        vm.prank(admin);
        dao.setProposalThreshold(newProposalThreshold);
        assertEq(dao.proposalThreshold(), newProposalThreshold);
        
        // Test updating quorum percentage
        uint256 newQuorumPercentage = 10;
        vm.prank(admin);
        dao.updateQuorumNumerator(newQuorumPercentage);
        
        // Check new quorum with total supply of 1,350,000 tokens
        // Expected: 10% of 1,350,000 = 135,000 tokens
        uint256 expectedQuorum = (1350000e18 * newQuorumPercentage) / 100;
        assertEq(dao.quorum(block.number - 1), expectedQuorum);
    }
    
    function testRoleBasedAccess() public {
        // Non-admin trying to change settings should fail
        vm.prank(voter1);
        vm.expectRevert();
        dao.setVotingDelay(20);
        
        // Admin can add a new moderator
        vm.prank(admin);
        dao.grantRole(dao.MODERATOR_ROLE(), voter1);
        assertTrue(dao.hasRole(dao.MODERATOR_ROLE(), voter1));
        
        // Add new admin
        vm.prank(admin);
        dao.grantRole(dao.ADMIN_ROLE(), proposer);
        assertTrue(dao.hasRole(dao.ADMIN_ROLE(), proposer));
        
        // New admin should be able to update settings
        vm.prank(proposer);
        dao.setVotingDelay(30);
        assertEq(dao.votingDelay(), 30);
    }
    
    function testQuorum() public {
        // With QUORUM_PERCENTAGE = 4 and total votes = 1,350,000 tokens
        // Expected quorum = 4% of 1,350,000 = 54,000 tokens
        uint256 totalVotes = 1350000e18;
        uint256 expectedQuorum = (totalVotes * QUORUM_PERCENTAGE) / 100;
        assertEq(dao.quorum(block.number - 1), expectedQuorum);
    }
    
    function testExecutionFlow() public {
        // Create a complete proposal and execute it
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Mint tokens to voter2";
        
        targets[0] = address(token);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSelector(token.mint.selector, voter2, 10000e18);
        
        // Submit the proposal
        vm.prank(admin);
        uint256 proposalId = dao.propose(targets, values, calldatas, description);
        
        // Move to active state
        vm.roll(block.number + VOTING_DELAY + 1);
        
        // Vote on proposal
        vm.prank(admin);
        dao.castVote(proposalId, 1); // Vote in favor
        
        // Move to end of voting period
        vm.roll(block.number + VOTING_PERIOD);
        
        // Queue the proposal
        bytes32 descHash = keccak256(bytes(description));
        vm.prank(admin);
        dao.queue(targets, values, calldatas, descHash);
        
        // Check state is Queued
        assertEq(uint(dao.state(proposalId)), uint(IGovernor.ProposalState.Queued));
        
        // Move forward in time past the timelock delay
        vm.warp(block.timestamp + MIN_DELAY + 1);
        
        // Execute proposal
        vm.prank(admin);
        dao.execute(targets, values, calldatas, descHash);
        
        // Check state is Executed
        assertEq(uint(dao.state(proposalId)), uint(IGovernor.ProposalState.Executed));
        
        // Verify that the proposal action was executed (voter2 got the tokens)
        assertEq(token.balanceOf(voter2), 60000e18); // Original 50000e18 + 10000e18
    }
}
