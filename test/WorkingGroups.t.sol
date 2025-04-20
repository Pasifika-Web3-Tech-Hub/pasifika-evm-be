// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/WorkingGroups.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

// Mock token for testing (replacing ERC20PresetMinterPauser which is not in OZ v5.3.0)
contract MockToken is ERC20Burnable, ERC20Pausable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // The following functions are overrides required by Solidity
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
    }
}

contract WorkingGroupsTest is Test {
    WorkingGroups public workingGroups;
    MockToken public token;
    
    address public admin = address(1);
    address public coordinator = address(2);
    address public validator1 = address(3);
    address public validator2 = address(4);
    address public reputationManager = address(5);
    
    uint256 public groupId;
    
    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy token for staking
        token = new MockToken("Stake Token", "STK");
        
        // Deploy WorkingGroups contract
        workingGroups = new WorkingGroups(address(token));
        
        // Setup roles
        workingGroups.grantRole(workingGroups.REPUTATION_MANAGER_ROLE(), reputationManager);
        
        // Mint tokens to validators for staking
        token.mint(validator1, 10000 * 10**18);
        token.mint(validator2, 10000 * 10**18);
        
        // Create a working group
        groupId = workingGroups.createWorkingGroup(
            "Technical Verification Group",
            "Group responsible for technical verification of digital assets",
            WorkingGroups.GroupCategory.TechnicalVerification,
            10, // Min reputation
            1500 * 10**18, // Required stake
            coordinator
        );
        
        vm.stopPrank();
    }
    
    function testDeployment() public {
        assertEq(address(workingGroups.stakingToken()), address(token));
        assertTrue(workingGroups.hasRole(workingGroups.ADMIN_ROLE(), admin));
        assertTrue(workingGroups.hasRole(workingGroups.GROUP_COORDINATOR_ROLE(), coordinator));
        
        // Check working group was created properly
        (
            string memory name,
            string memory description,
            WorkingGroups.GroupCategory category,
            uint256 memberCount,
            ,,,
            address[] memory members,
            address groupCoordinator,
            ,
        ) = workingGroups.workingGroups(groupId);
        
        assertEq(name, "Technical Verification Group");
        assertEq(description, "Group responsible for technical verification of digital assets");
        assertEq(uint(category), uint(WorkingGroups.GroupCategory.TechnicalVerification));
        assertEq(memberCount, 1);
        assertEq(members.length, 0); // Members are stored in a separate mapping
        assertEq(groupCoordinator, coordinator);
        
        // Check coordinator is in the group
        address[] memory groupMembers = workingGroups.getGroupMembers(groupId);
        assertEq(groupMembers.length, 1);
        assertEq(groupMembers[0], coordinator);
    }
    
    function testRegisterValidator() public {
        vm.startPrank(validator1);
        
        // Register as validator
        workingGroups.registerValidator(
            WorkingGroups.GroupCategory.TechnicalVerification,
            "ipfs://validator1-profile"
        );
        
        // Check validator record
        (
            address account,
            ,
            uint256 stakedAmount,
            uint256 reputation,
            uint256 completedVerifications,
            uint256 registrationTime,
            WorkingGroups.ValidatorStatus status,
            string memory profileURI,
            uint256 slashCount
        ) = workingGroups.validators(validator1);
        
        assertEq(account, validator1);
        assertEq(stakedAmount, 0);
        assertEq(reputation, 0);
        assertEq(completedVerifications, 0);
        assertGt(registrationTime, 0);
        assertEq(uint(status), uint(WorkingGroups.ValidatorStatus.Pending));
        assertEq(profileURI, "ipfs://validator1-profile");
        assertEq(slashCount, 0);
        
        vm.stopPrank();
    }
    
    function testStaking() public {
        vm.startPrank(validator1);
        
        // Register as validator
        workingGroups.registerValidator(
            WorkingGroups.GroupCategory.TechnicalVerification,
            "ipfs://validator1-profile"
        );
        
        // Approve tokens for staking
        token.approve(address(workingGroups), 2000 * 10**18);
        
        // Stake tokens
        workingGroups.stakeForValidation(2000 * 10**18);
        
        // Check stake was recorded
        (
            ,
            ,
            uint256 stakedAmount,
            ,
            ,
            ,
            WorkingGroups.ValidatorStatus status,
            ,
        ) = workingGroups.validators(validator1);
        
        assertEq(stakedAmount, 2000 * 10**18);
        assertEq(uint(status), uint(WorkingGroups.ValidatorStatus.Active));
        assertEq(workingGroups.stakedBalances(validator1), 2000 * 10**18);
        assertTrue(workingGroups.hasRole(workingGroups.VALIDATOR_ROLE(), validator1));
        
        vm.stopPrank();
    }
    
    function testUnstaking() public {
        // Setup validator with stake
        vm.startPrank(validator1);
        workingGroups.registerValidator(
            WorkingGroups.GroupCategory.TechnicalVerification,
            "ipfs://validator1-profile"
        );
        token.approve(address(workingGroups), 2000 * 10**18);
        workingGroups.stakeForValidation(2000 * 10**18);
        vm.stopPrank();
        
        // Request unstake
        vm.prank(validator1);
        workingGroups.requestUnstake(1000 * 10**18);
        
        // Verify lock period
        assertGt(workingGroups.unstakeTime(validator1), 0);
        
        // Try to withdraw before lock period ends - should fail
        vm.prank(validator1);
        vm.expectRevert();
        workingGroups.withdrawStake(1000 * 10**18);
        
        // Move time forward past lock period
        vm.warp(block.timestamp + 31 days);
        
        // Now withdrawal should succeed
        vm.prank(validator1);
        workingGroups.withdrawStake(1000 * 10**18);
        
        // Check updated stake
        (
            ,
            ,
            uint256 stakedAmount,
            ,
            ,
            ,
            ,
            ,
        ) = workingGroups.validators(validator1);
        
        assertEq(stakedAmount, 1000 * 10**18);
        assertEq(workingGroups.stakedBalances(validator1), 1000 * 10**18);
    }
    
    function testUpdateReputation() public {
        // Setup validator
        vm.prank(validator1);
        workingGroups.registerValidator(
            WorkingGroups.GroupCategory.TechnicalVerification,
            "ipfs://validator1-profile"
        );
        
        // Increase reputation
        vm.prank(reputationManager);
        workingGroups.updateReputation(validator1, 20);
        
        (
            ,
            ,
            ,
            uint256 reputation,
            ,
            ,
            ,
            ,
        ) = workingGroups.validators(validator1);
        
        assertEq(reputation, 20);
        
        // Decrease reputation
        vm.prank(reputationManager);
        workingGroups.updateReputation(validator1, -5);
        
        (
            ,
            ,
            ,
            uint256 newReputation,
            ,
            ,
            ,
            ,
        ) = workingGroups.validators(validator1);
        
        assertEq(newReputation, 15);
    }
    
    function testAddRemoveGroupMembers() public {
        // Setup validator with reputation
        vm.prank(validator1);
        workingGroups.registerValidator(
            WorkingGroups.GroupCategory.TechnicalVerification,
            "ipfs://validator1-profile"
        );
        
        vm.prank(reputationManager);
        workingGroups.updateReputation(validator1, 20);
        
        // Add validator to group
        vm.prank(coordinator);
        workingGroups.addGroupMember(groupId, validator1);
        
        // Check member was added
        address[] memory groupMembers = workingGroups.getGroupMembers(groupId);
        assertEq(groupMembers.length, 2); // Coordinator + validator1
        
        bool found = false;
        for (uint i = 0; i < groupMembers.length; i++) {
            if (groupMembers[i] == validator1) {
                found = true;
                break;
            }
        }
        assertTrue(found);
        
        // Check validator's groups
        uint256[] memory memberGroups = workingGroups.getMemberGroups(validator1);
        assertEq(memberGroups.length, 1);
        assertEq(memberGroups[0], groupId);
        
        // Remove member
        vm.prank(coordinator);
        workingGroups.removeGroupMember(groupId, validator1);
        
        // Check member was removed
        groupMembers = workingGroups.getGroupMembers(groupId);
        assertEq(groupMembers.length, 1); // Only coordinator remains
        
        memberGroups = workingGroups.getMemberGroups(validator1);
        assertEq(memberGroups.length, 0);
    }
    
    function testIssueVerification() public {
        // Setup validator with stake
        vm.startPrank(validator1);
        workingGroups.registerValidator(
            WorkingGroups.GroupCategory.TechnicalVerification,
            "ipfs://validator1-profile"
        );
        token.approve(address(workingGroups), 2000 * 10**18);
        workingGroups.stakeForValidation(2000 * 10**18);
        vm.stopPrank();
        
        // Add validator to group
        vm.prank(coordinator);
        workingGroups.addGroupMember(groupId, validator1);
        
        // Issue verification
        vm.prank(validator1);
        uint256 verificationId = workingGroups.issueVerification(
            42, // tokenId
            "ipfs://verification-data",
            "Technical verification completed"
        );
        
        // Check verification record
        (
            uint256 storedVerificationId,
            uint256 tokenId,
            address validator,
            uint256 timestamp,
            string memory attestationURI,
            bool revoked,
            string memory details
        ) = workingGroups.verifications(verificationId);
        
        assertEq(storedVerificationId, verificationId);
        assertEq(tokenId, 42);
        assertEq(validator, validator1);
        assertGt(timestamp, 0);
        assertEq(attestationURI, "ipfs://verification-data");
        assertFalse(revoked);
        assertEq(details, "Technical verification completed");
        
        // Check validator stats updated
        (
            ,
            ,
            ,
            ,
            uint256 completedVerifications,
            ,
            ,
            ,
        ) = workingGroups.validators(validator1);
        
        assertEq(completedVerifications, 1);
        
        // Check token verification status
        assertTrue(workingGroups.tokenVerificationStatus(42, validator1));
        
        // Check group tasks updated
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint256 completedTasks
        ) = workingGroups.workingGroups(groupId);
        
        assertEq(completedTasks, 1);
    }
    
    function testRevokeVerification() public {
        // Setup validator with stake and issue verification
        vm.startPrank(validator1);
        workingGroups.registerValidator(
            WorkingGroups.GroupCategory.TechnicalVerification,
            "ipfs://validator1-profile"
        );
        token.approve(address(workingGroups), 2000 * 10**18);
        workingGroups.stakeForValidation(2000 * 10**18);
        uint256 verificationId = workingGroups.issueVerification(
            42, 
            "ipfs://verification-data",
            "Technical verification completed"
        );
        vm.stopPrank();
        
        // Revoke verification
        vm.prank(validator1);
        workingGroups.revokeVerification(verificationId);
        
        // Check verification record
        (
            ,
            ,
            ,
            ,
            ,
            bool revoked,
            
        ) = workingGroups.verifications(verificationId);
        
        assertTrue(revoked);
        
        // Check token verification status
        assertFalse(workingGroups.tokenVerificationStatus(42, validator1));
    }
    
    function testSlashValidator() public {
        // Setup validator with stake
        vm.startPrank(validator1);
        workingGroups.registerValidator(
            WorkingGroups.GroupCategory.TechnicalVerification,
            "ipfs://validator1-profile"
        );
        token.approve(address(workingGroups), 2000 * 10**18);
        workingGroups.stakeForValidation(2000 * 10**18);
        vm.stopPrank();
        
        // Slash validator
        vm.prank(admin);
        workingGroups.slashValidator(
            validator1,
            500 * 10**18,
            "Incorrect verification"
        );
        
        // Check updated stake and status
        (
            ,
            ,
            uint256 stakedAmount,
            ,
            ,
            ,
            ,
            ,
            uint256 slashCount
        ) = workingGroups.validators(validator1);
        
        assertEq(stakedAmount, 1500 * 10**18);
        assertEq(slashCount, 1);
        assertEq(workingGroups.stakedBalances(validator1), 1500 * 10**18);
        
        // Slash the rest of the stake
        vm.prank(admin);
        workingGroups.slashValidator(
            validator1,
            1500 * 10**18,
            "Major violation"
        );
        
        // Check validator is suspended
        (
            ,
            ,
            ,
            ,
            ,
            ,
            WorkingGroups.ValidatorStatus status,
            ,
            
        ) = workingGroups.validators(validator1);
        
        assertEq(uint(status), uint(WorkingGroups.ValidatorStatus.Suspended));
        assertFalse(workingGroups.hasRole(workingGroups.VALIDATOR_ROLE(), validator1));
    }
    
    function testChangeValidatorStatus() public {
        // Setup validator
        vm.prank(validator1);
        workingGroups.registerValidator(
            WorkingGroups.GroupCategory.TechnicalVerification,
            "ipfs://validator1-profile"
        );
        
        // Change status
        vm.prank(admin);
        workingGroups.changeValidatorStatus(validator1, WorkingGroups.ValidatorStatus.Revoked);
        
        // Check status
        (
            ,
            ,
            ,
            ,
            ,
            ,
            WorkingGroups.ValidatorStatus status,
            ,
            
        ) = workingGroups.validators(validator1);
        
        assertEq(uint(status), uint(WorkingGroups.ValidatorStatus.Revoked));
        
        // Restore status
        vm.prank(admin);
        workingGroups.changeValidatorStatus(validator1, WorkingGroups.ValidatorStatus.Active);
        
        (
            ,
            ,
            ,
            ,
            ,
            ,
            WorkingGroups.ValidatorStatus newStatus,
            ,
            
        ) = workingGroups.validators(validator1);
        
        assertEq(uint(newStatus), uint(WorkingGroups.ValidatorStatus.Active));
        assertTrue(workingGroups.hasRole(workingGroups.VALIDATOR_ROLE(), validator1));
    }
    
    function testUpdateStakingConfig() public {
        vm.prank(admin);
        workingGroups.updateStakingConfig(
            2000 * 10**18, // New min stake
            60 days, // New lock period
            20, // New slashing penalty
            true // Staking active
        );
        
        (
            uint256 minStakeAmount,
            uint256 stakeLockPeriod,
            uint256 slashingPenaltyPercent,
            bool stakingActive
        ) = workingGroups.stakingConfig();
        
        assertEq(minStakeAmount, 2000 * 10**18);
        assertEq(stakeLockPeriod, 60 days);
        assertEq(slashingPenaltyPercent, 20);
        assertTrue(stakingActive);
    }
    
    function testUpdateCategoryStakeRequirement() public {
        vm.prank(admin);
        workingGroups.updateCategoryStakeRequirement(
            WorkingGroups.GroupCategory.TechnicalVerification,
            3000 * 10**18
        );
        
        assertEq(
            workingGroups.categoryStakeRequirements(WorkingGroups.GroupCategory.TechnicalVerification),
            3000 * 10**18
        );
    }
    
    function testPause() public {
        // Pause contract
        vm.prank(admin);
        workingGroups.pause();
        
        // Try to register - should fail
        vm.prank(validator2);
        vm.expectRevert("Pausable: paused");
        workingGroups.registerValidator(
            WorkingGroups.GroupCategory.ContentModeration,
            "ipfs://validator2-profile"
        );
        
        // Unpause
        vm.prank(admin);
        workingGroups.unpause();
        
        // Now should work
        vm.prank(validator2);
        workingGroups.registerValidator(
            WorkingGroups.GroupCategory.ContentModeration,
            "ipfs://validator2-profile"
        );
        
        // Check registration succeeded
        (
            address account,
            ,,,,,,,
        ) = workingGroups.validators(validator2);
        
        assertEq(account, validator2);
    }
}
