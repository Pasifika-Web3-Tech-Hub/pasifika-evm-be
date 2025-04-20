// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

/**
 * @title WorkingGroups
 * @dev Contract to manage working groups and validators in the Pasifika ecosystem
 * Handles validator registration, staking, certification, and reputation management
 */
contract WorkingGroups is AccessControlEnumerable, Pausable, ReentrancyGuard {
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant REPUTATION_MANAGER_ROLE = keccak256("REPUTATION_MANAGER_ROLE");
    bytes32 public constant GROUP_COORDINATOR_ROLE = keccak256("GROUP_COORDINATOR_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    
    // Working group category types
    enum GroupCategory {
        ArtisticVerification,     // For cultural and artistic works
        TechnicalVerification,    // For technical quality and standards
        CommunityRepresentation,  // For community engagement
        SupplyChainValidation,    // For physical item tracking
        ContentModeration,        // For content standards
        DisputeResolution,        // For marketplace disputes
        GovernanceProposal,       // For DAO proposals
        CodeAudit                 // For smart contract audits
    }
    
    // Validator status
    enum ValidatorStatus {
        Inactive,
        Pending,
        Active,
        Suspended,
        Revoked
    }
    
    // Working group structure
    struct WorkingGroup {
        string name;
        string description;
        GroupCategory category;
        uint256 memberCount;
        uint256 minimumReputationRequired;
        uint256 requiredStake;
        bool active;
        address[] members;
        address coordinator;
        uint256 creationTime;
        uint256 completedTasks;
    }
    
    // Validator data structure
    struct Validator {
        address account;
        GroupCategory[] categories;
        uint256 stakedAmount;
        uint256 reputation;
        uint256 completedVerifications;
        uint256 registrationTime;
        ValidatorStatus status;
        string profileURI;
        uint256 slashCount;
    }
    
    // Verification record structure
    struct Verification {
        uint256 verificationId;
        uint256 tokenId;
        address validator;
        uint256 timestamp;
        string attestationURI;
        bool revoked;
        string details;
    }
    
    // Staking configuration
    struct StakingConfig {
        uint256 minStakeAmount;
        uint256 stakeLockPeriod;
        uint256 slashingPenaltyPercent;
        bool stakingActive;
    }
    
    // Token for staking
    IERC20 public stakingToken;
    
    // IDs and counters
    uint256 private _nextGroupId = 1;
    uint256 private _nextVerificationId = 1;
    
    // Mappings
    mapping(uint256 => WorkingGroup) public workingGroups;
    mapping(address => Validator) public validators;
    mapping(uint256 => Verification) public verifications;
    mapping(uint256 => address[]) public groupMemberships; // Group ID => member addresses
    mapping(address => uint256[]) public memberGroups; // Member address => group IDs
    mapping(address => uint256) public stakedBalances;
    mapping(address => uint256) public unstakeTime; // When a validator can unstake their tokens
    mapping(GroupCategory => uint256) public categoryStakeRequirements;
    mapping(uint256 => mapping(address => bool)) public tokenVerificationStatus; // Token ID => validator => verified
    
    // Staking configuration
    StakingConfig public stakingConfig;
    
    // Events
    event WorkingGroupCreated(uint256 indexed groupId, string name, GroupCategory category);
    event WorkingGroupUpdated(uint256 indexed groupId, string name, bool active);
    event MemberAdded(uint256 indexed groupId, address indexed member);
    event MemberRemoved(uint256 indexed groupId, address indexed member);
    event ValidatorRegistered(address indexed validator, GroupCategory indexed category);
    event StakeDeposited(address indexed validator, uint256 amount);
    event StakeWithdrawn(address indexed validator, uint256 amount);
    event VerificationIssued(address indexed validator, uint256 indexed tokenId, uint256 verificationId);
    event ValidatorReputationUpdated(address indexed validator, int8 change, uint256 newReputation);
    event ValidatorSlashed(address indexed validator, uint256 amount, string reason);
    event ValidatorStatusChanged(address indexed validator, ValidatorStatus status);
    
    /**
     * @dev Constructor
     * @param _stakingToken ERC20 token used for staking
     */
    constructor(address _stakingToken) {
        stakingToken = IERC20(_stakingToken);
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(REPUTATION_MANAGER_ROLE, msg.sender);
        _grantRole(GROUP_COORDINATOR_ROLE, msg.sender);
        
        // Initialize staking configuration
        stakingConfig = StakingConfig({
            minStakeAmount: 1000 * 10**18, // 1000 tokens
            stakeLockPeriod: 30 days,
            slashingPenaltyPercent: 10, // 10% of stake
            stakingActive: true
        });
        
        // Set default stake requirements for each category
        categoryStakeRequirements[GroupCategory.ArtisticVerification] = 1000 * 10**18;
        categoryStakeRequirements[GroupCategory.TechnicalVerification] = 1500 * 10**18;
        categoryStakeRequirements[GroupCategory.CommunityRepresentation] = 1000 * 10**18;
        categoryStakeRequirements[GroupCategory.SupplyChainValidation] = 2000 * 10**18;
        categoryStakeRequirements[GroupCategory.ContentModeration] = 1000 * 10**18;
        categoryStakeRequirements[GroupCategory.DisputeResolution] = 2500 * 10**18;
        categoryStakeRequirements[GroupCategory.GovernanceProposal] = 3000 * 10**18;
        categoryStakeRequirements[GroupCategory.CodeAudit] = 5000 * 10**18;
    }
    
    /**
     * @dev Pause the contract
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
    
    /**
     * @dev Create a new working group
     * @param name Group name
     * @param description Group description
     * @param category Group category
     * @param minimumReputationRequired Minimum reputation needed to join
     * @param requiredStake Staking requirement for this group
     * @param coordinator Initial coordinator address
     * @return groupId The ID of the new working group
     */
    function createWorkingGroup(
        string calldata name,
        string calldata description,
        GroupCategory category,
        uint256 minimumReputationRequired,
        uint256 requiredStake,
        address coordinator
    ) 
        external
        whenNotPaused
        onlyRole(ADMIN_ROLE)
        returns (uint256)
    {
        uint256 groupId = _nextGroupId++;
        
        workingGroups[groupId] = WorkingGroup({
            name: name,
            description: description,
            category: category,
            memberCount: 0,
            minimumReputationRequired: minimumReputationRequired,
            requiredStake: requiredStake,
            active: true,
            members: new address[](0),
            coordinator: coordinator,
            creationTime: block.timestamp,
            completedTasks: 0
        });
        
        // Grant coordinator role to the coordinator
        _grantRole(GROUP_COORDINATOR_ROLE, coordinator);
        
        // Add the coordinator as first member
        _addMemberToGroup(groupId, coordinator);
        
        emit WorkingGroupCreated(groupId, name, category);
        
        return groupId;
    }
    
    /**
     * @dev Update a working group's configuration
     * @param groupId The ID of the group to update
     * @param name New group name
     * @param description New group description
     * @param minimumReputationRequired New minimum reputation
     * @param active Whether the group is active
     */
    function updateWorkingGroup(
        uint256 groupId,
        string calldata name,
        string calldata description,
        uint256 minimumReputationRequired,
        bool active
    )
        external
        whenNotPaused
    {
        WorkingGroup storage group = workingGroups[groupId];
        require(group.creationTime > 0, "Group does not exist");
        require(
            hasRole(ADMIN_ROLE, msg.sender) || 
            group.coordinator == msg.sender,
            "Not authorized"
        );
        
        group.name = name;
        group.description = description;
        group.minimumReputationRequired = minimumReputationRequired;
        group.active = active;
        
        emit WorkingGroupUpdated(groupId, name, active);
    }
    
    /**
     * @dev Change the coordinator of a working group
     * @param groupId The ID of the group
     * @param newCoordinator Address of the new coordinator
     */
    function changeGroupCoordinator(uint256 groupId, address newCoordinator) 
        external
        whenNotPaused
    {
        WorkingGroup storage group = workingGroups[groupId];
        require(group.creationTime > 0, "Group does not exist");
        require(
            hasRole(ADMIN_ROLE, msg.sender) || 
            group.coordinator == msg.sender,
            "Not authorized"
        );
        
        require(newCoordinator != address(0), "Invalid coordinator address");
        
        // Add new coordinator to group if not already a member
        bool isMember = false;
        for (uint i = 0; i < group.members.length; i++) {
            if (group.members[i] == newCoordinator) {
                isMember = true;
                break;
            }
        }
        
        if (!isMember) {
            _addMemberToGroup(groupId, newCoordinator);
        }
        
        // Grant coordinator role
        _grantRole(GROUP_COORDINATOR_ROLE, newCoordinator);
        
        // Update coordinator
        group.coordinator = newCoordinator;
    }
    
    /**
     * @dev Internal function to add a member to a group
     * @param groupId The ID of the group
     * @param member The address to add
     */
    function _addMemberToGroup(uint256 groupId, address member) internal {
        WorkingGroup storage group = workingGroups[groupId];
        
        // Add to group members array
        group.members.push(member);
        group.memberCount++;
        
        // Update mappings
        groupMemberships[groupId].push(member);
        memberGroups[member].push(groupId);
        
        emit MemberAdded(groupId, member);
    }
    
    /**
     * @dev Add a member to a working group
     * @param groupId The ID of the group
     * @param member The address to add
     */
    function addGroupMember(uint256 groupId, address member) 
        external
        whenNotPaused
    {
        WorkingGroup storage group = workingGroups[groupId];
        require(group.creationTime > 0, "Group does not exist");
        require(group.active, "Group is not active");
        require(
            hasRole(ADMIN_ROLE, msg.sender) || 
            group.coordinator == msg.sender,
            "Not authorized"
        );
        
        // Check if member meets reputation requirements
        if (group.minimumReputationRequired > 0) {
            require(
                validators[member].reputation >= group.minimumReputationRequired,
                "Insufficient reputation"
            );
        }
        
        // Check if already a member
        for (uint i = 0; i < group.members.length; i++) {
            require(group.members[i] != member, "Already a member");
        }
        
        _addMemberToGroup(groupId, member);
    }
    
    /**
     * @dev Remove a member from a working group
     * @param groupId The ID of the group
     * @param member The address to remove
     */
    function removeGroupMember(uint256 groupId, address member) 
        external
        whenNotPaused
    {
        WorkingGroup storage group = workingGroups[groupId];
        require(group.creationTime > 0, "Group does not exist");
        require(
            hasRole(ADMIN_ROLE, msg.sender) || 
            group.coordinator == msg.sender,
            "Not authorized"
        );
        
        // Can't remove the coordinator
        require(member != group.coordinator, "Cannot remove coordinator");
        
        // Find and remove member from group.members
        bool found = false;
        uint memberIndex;
        
        for (uint i = 0; i < group.members.length; i++) {
            if (group.members[i] == member) {
                memberIndex = i;
                found = true;
                break;
            }
        }
        
        require(found, "Member not found in group");
        
        // Remove from group.members by swapping with the last element and then removing the last element
        if (memberIndex < group.members.length - 1) {
            group.members[memberIndex] = group.members[group.members.length - 1];
        }
        group.members.pop();
        group.memberCount--;
        
        // Remove from groupMemberships
        address[] storage groupMembers = groupMemberships[groupId];
        found = false;
        
        for (uint i = 0; i < groupMembers.length; i++) {
            if (groupMembers[i] == member) {
                memberIndex = i;
                found = true;
                break;
            }
        }
        
        if (found) {
            if (memberIndex < groupMembers.length - 1) {
                groupMembers[memberIndex] = groupMembers[groupMembers.length - 1];
            }
            groupMembers.pop();
        }
        
        // Remove from memberGroups
        uint256[] storage memberGroupIds = memberGroups[member];
        found = false;
        
        for (uint i = 0; i < memberGroupIds.length; i++) {
            if (memberGroupIds[i] == groupId) {
                memberIndex = i;
                found = true;
                break;
            }
        }
        
        if (found) {
            if (memberIndex < memberGroupIds.length - 1) {
                memberGroupIds[memberIndex] = memberGroupIds[memberGroupIds.length - 1];
            }
            memberGroupIds.pop();
        }
        
        emit MemberRemoved(groupId, member);
    }
    
    /**
     * @dev Get all members of a working group
     * @param groupId The ID of the group
     * @return An array of member addresses
     */
    function getGroupMembers(uint256 groupId) external view returns (address[] memory) {
        return workingGroups[groupId].members;
    }
    
    /**
     * @dev Get all groups a member belongs to
     * @param member The member address
     * @return An array of group IDs
     */
    function getMemberGroups(address member) external view returns (uint256[] memory) {
        return memberGroups[member];
    }
    
    /**
     * @dev Register as a validator
     * @param category The category to register for
     * @param profileURI URI to validator profile information
     */
    function registerValidator(GroupCategory category, string calldata profileURI) 
        external
        whenNotPaused
    {
        // Check if staking is active
        require(stakingConfig.stakingActive, "Staking is not active");
        
        // Check if already registered for this category
        Validator storage validator = validators[msg.sender];
        
        if (validator.account == address(0)) {
            // First time registration
            validator.account = msg.sender;
            validator.registrationTime = block.timestamp;
            validator.status = ValidatorStatus.Pending;
            validator.profileURI = profileURI;
        }
        
        // Check if already registered for this category
        for (uint i = 0; i < validator.categories.length; i++) {
            require(validator.categories[i] != category, "Already registered for this category");
        }
        
        // Add category to validator's categories
        validator.categories.push(category);
        
        emit ValidatorRegistered(msg.sender, category);
    }
    
    /**
     * @dev Stake tokens for validation
     * @param amount The amount to stake
     */
    function stakeForValidation(uint256 amount) 
        external
        whenNotPaused
        nonReentrant
    {
        require(stakingConfig.stakingActive, "Staking is not active");
        require(amount >= stakingConfig.minStakeAmount, "Stake too small");
        
        Validator storage validator = validators[msg.sender];
        require(validator.account != address(0), "Not registered as validator");
        
        // Transfer tokens from user to contract
        require(stakingToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        // Update staked amount
        validator.stakedAmount += amount;
        stakedBalances[msg.sender] += amount;
        
        // If this is their first stake, set status to Active
        if (validator.status == ValidatorStatus.Pending) {
            validator.status = ValidatorStatus.Active;
            _grantRole(VALIDATOR_ROLE, msg.sender);
            emit ValidatorStatusChanged(msg.sender, ValidatorStatus.Active);
        }
        
        emit StakeDeposited(msg.sender, amount);
    }
    
    /**
     * @dev Request to unstake tokens (begins lock period)
     * @param amount The amount to unstake
     */
    function requestUnstake(uint256 amount) 
        external
        whenNotPaused
        nonReentrant
    {
        Validator storage validator = validators[msg.sender];
        require(validator.account != address(0), "Not registered as validator");
        require(validator.stakedAmount >= amount, "Insufficient staked amount");
        
        // Set unstake time
        unstakeTime[msg.sender] = block.timestamp + stakingConfig.stakeLockPeriod;
    }
    
    /**
     * @dev Withdraw staked tokens after lock period
     * @param amount The amount to withdraw
     */
    function withdrawStake(uint256 amount) 
        external
        whenNotPaused
        nonReentrant
    {
        Validator storage validator = validators[msg.sender];
        require(validator.account != address(0), "Not registered as validator");
        require(validator.stakedAmount >= amount, "Insufficient staked amount");
        require(unstakeTime[msg.sender] > 0, "Unstake not requested");
        require(block.timestamp >= unstakeTime[msg.sender], "Lock period not over");
        
        // Update staked amounts
        validator.stakedAmount -= amount;
        stakedBalances[msg.sender] -= amount;
        
        // Transfer tokens back to validator
        require(stakingToken.transfer(msg.sender, amount), "Transfer failed");
        
        // Clear unstake time if all tokens withdrawn
        if (validator.stakedAmount == 0) {
            delete unstakeTime[msg.sender];
        }
        
        emit StakeWithdrawn(msg.sender, amount);
    }
    
    /**
     * @dev Issue verification for a token
     * @param tokenId The NFT token ID to verify
     * @param attestationURI URI to attestation data
     * @param details Additional verification details
     * @return verificationId The ID of the verification
     */
    function issueVerification(
        uint256 tokenId,
        string calldata attestationURI,
        string calldata details
    ) 
        external
        whenNotPaused
        onlyRole(VALIDATOR_ROLE)
        returns (uint256)
    {
        Validator storage validator = validators[msg.sender];
        require(validator.status == ValidatorStatus.Active, "Validator not active");
        
        // Check if token already verified by this validator
        require(!tokenVerificationStatus[tokenId][msg.sender], "Already verified by you");
        
        // Create verification record
        uint256 verificationId = _nextVerificationId++;
        
        verifications[verificationId] = Verification({
            verificationId: verificationId,
            tokenId: tokenId,
            validator: msg.sender,
            timestamp: block.timestamp,
            attestationURI: attestationURI,
            revoked: false,
            details: details
        });
        
        // Mark token as verified by this validator
        tokenVerificationStatus[tokenId][msg.sender] = true;
        
        // Update validator stats
        validator.completedVerifications++;
        
        // Find groups with this validator and update completed tasks
        for (uint i = 0; i < memberGroups[msg.sender].length; i++) {
            uint256 groupId = memberGroups[msg.sender][i];
            workingGroups[groupId].completedTasks++;
        }
        
        emit VerificationIssued(msg.sender, tokenId, verificationId);
        
        return verificationId;
    }
    
    /**
     * @dev Revoke a verification
     * @param verificationId The ID of the verification to revoke
     */
    function revokeVerification(uint256 verificationId) 
        external
        whenNotPaused
    {
        Verification storage verification = verifications[verificationId];
        require(verification.verificationId == verificationId, "Verification does not exist");
        
        // Only the issuing validator or an admin can revoke
        require(
            verification.validator == msg.sender || 
            hasRole(ADMIN_ROLE, msg.sender),
            "Not authorized"
        );
        
        require(!verification.revoked, "Already revoked");
        
        verification.revoked = true;
        
        // Clear token verification status
        tokenVerificationStatus[verification.tokenId][verification.validator] = false;
    }
    
    /**
     * @dev Update the reputation of a validator
     * @param validator Address of the validator
     * @param changeAmount Amount to change reputation by (positive or negative)
     */
    function updateReputation(address validator, int8 changeAmount) 
        external 
        onlyRole(REPUTATION_MANAGER_ROLE)
    {
        require(validators[validator].account != address(0), "Validator does not exist");
        
        if (changeAmount > 0) {
            validators[validator].reputation += uint256(uint8(changeAmount));
        } else if (changeAmount < 0) {
            uint256 absChange = uint256(uint8(-changeAmount));
            if (validators[validator].reputation < absChange) {
                validators[validator].reputation = 0;
            } else {
                validators[validator].reputation -= absChange;
            }
        }
        
        emit ValidatorReputationUpdated(validator, changeAmount, validators[validator].reputation);
    }
    
    /**
     * @dev Slash a validator for bad behavior
     * @param validator The validator address
     * @param amount The amount to slash
     * @param reason The reason for slashing
     */
    function slashValidator(
        address validator,
        uint256 amount,
        string calldata reason
    ) 
        external
        whenNotPaused
        onlyRole(ADMIN_ROLE)
        nonReentrant
    {
        Validator storage validatorData = validators[validator];
        require(validatorData.account != address(0), "Not a validator");
        require(validatorData.stakedAmount >= amount, "Slash amount exceeds stake");
        
        // Update staked amounts
        validatorData.stakedAmount -= amount;
        stakedBalances[validator] -= amount;
        validatorData.slashCount++;
        
        // If validator has no more stake, change status to Suspended
        if (validatorData.stakedAmount == 0) {
            validatorData.status = ValidatorStatus.Suspended;
            emit ValidatorStatusChanged(validator, ValidatorStatus.Suspended);
        }
        
        emit ValidatorSlashed(validator, amount, reason);
    }
    
    /**
     * @dev Change validator status
     * @param validator The validator address
     * @param status The new status
     */
    function changeValidatorStatus(address validator, ValidatorStatus status) 
        external
        whenNotPaused
        onlyRole(ADMIN_ROLE)
    {
        require(validators[validator].account != address(0), "Not a validator");
        require(validators[validator].status != status, "Already in this status");
        
        validators[validator].status = status;
        
        // If activating, grant validator role
        if (status == ValidatorStatus.Active) {
            _grantRole(VALIDATOR_ROLE, validator);
        }
        
        // If deactivating, revoke validator role
        if (status == ValidatorStatus.Inactive || status == ValidatorStatus.Suspended || status == ValidatorStatus.Revoked) {
            _revokeRole(VALIDATOR_ROLE, validator);
        }
        
        emit ValidatorStatusChanged(validator, status);
    }
    
    /**
     * @dev Update staking configuration
     * @param minStakeAmount New minimum stake
     * @param stakeLockPeriod New lock period
     * @param slashingPenaltyPercent New slashing penalty
     * @param stakingActive Whether staking is active
     */
    function updateStakingConfig(
        uint256 minStakeAmount,
        uint256 stakeLockPeriod,
        uint256 slashingPenaltyPercent,
        bool stakingActive
    ) 
        external
        whenNotPaused
        onlyRole(ADMIN_ROLE)
    {
        require(slashingPenaltyPercent <= 100, "Penalty too high");
        
        stakingConfig.minStakeAmount = minStakeAmount;
        stakingConfig.stakeLockPeriod = stakeLockPeriod;
        stakingConfig.slashingPenaltyPercent = slashingPenaltyPercent;
        stakingConfig.stakingActive = stakingActive;
    }
    
    /**
     * @dev Update stake requirement for a category
     * @param category The category to update
     * @param stakeAmount The new stake requirement
     */
    function updateCategoryStakeRequirement(GroupCategory category, uint256 stakeAmount) 
        external
        whenNotPaused
        onlyRole(ADMIN_ROLE)
    {
        categoryStakeRequirements[category] = stakeAmount;
    }
    
    /**
     * @dev Check if account is a valid validator for a specific category
     * @param validator The validator address
     * @param category The category to check
     * @return isValid Whether the validator is valid for the category
     */
    function isValidValidatorForCategory(address validator, GroupCategory category) 
        external 
        view 
        returns (bool) 
    {
        if (validators[validator].status != ValidatorStatus.Active) {
            return false;
        }
        
        // Check if validator has sufficient stake for this category
        if (validators[validator].stakedAmount < categoryStakeRequirements[category]) {
            return false;
        }
        
        // Check if validator is registered for this category
        bool categoryMatch = false;
        for (uint i = 0; i < validators[validator].categories.length; i++) {
            if (validators[validator].categories[i] == category) {
                categoryMatch = true;
                break;
            }
        }
        
        return categoryMatch;
    }
    
    /**
     * @dev Get all validators in a specific category
     * @param category The category to query
     * @return validatorAddresses Array of validator addresses
     */
    function getValidatorsByCategory(GroupCategory category) 
        external 
        view 
        returns (address[] memory) 
    {
        // First, count valid validators in this category
        uint256 count = 0;
        address[] memory allValidators = new address[](1000); // Max count limit
        
        for (uint i = 0; i < allValidators.length; i++) {
            address validatorAddr = allValidators[i];
            
            if (validatorAddr == address(0)) break;
            
            Validator storage validator = validators[validatorAddr];
            
            if (validator.status != ValidatorStatus.Active) continue;
            
            // Check if validator is registered for this category
            for (uint j = 0; j < validator.categories.length; j++) {
                if (validator.categories[j] == category) {
                    count++;
                    break;
                }
            }
        }
        
        // Create result array
        address[] memory result = new address[](count);
        uint256 resultIndex = 0;
        
        for (uint i = 0; i < allValidators.length; i++) {
            address validatorAddr = allValidators[i];
            
            if (validatorAddr == address(0)) break;
            
            Validator storage validator = validators[validatorAddr];
            
            if (validator.status != ValidatorStatus.Active) continue;
            
            // Check if validator is registered for this category
            for (uint j = 0; j < validator.categories.length; j++) {
                if (validator.categories[j] == category) {
                    result[resultIndex] = validatorAddr;
                    resultIndex++;
                    break;
                }
            }
        }
        
        return result;
    }
    
    /**
     * @dev Get all verifications for a token
     * @param tokenId The token ID
     * @return verificationIds Array of verification IDs
     */
    function getTokenVerifications(uint256 tokenId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        // First count verifications for this token
        uint256 count = 0;
        for (uint i = 0; i < _nextVerificationId; i++) {
            if (verifications[i].tokenId == tokenId && !verifications[i].revoked) {
                count++;
            }
        }
        
        // Create result array
        uint256[] memory result = new uint256[](count);
        uint256 resultIndex = 0;
        
        for (uint i = 0; i < _nextVerificationId; i++) {
            if (verifications[i].tokenId == tokenId && !verifications[i].revoked) {
                result[resultIndex] = i;
                resultIndex++;
            }
        }
        
        return result;
    }
    
    /**
     * @dev Get a validator's details
     * @param validator Address of the validator
     * @return The validator's details struct
     */
    function getValidator(address validator) external view returns (Validator memory) {
        return validators[validator];
    }
    
    /**
     * @dev Get a working group's details
     * @param groupId ID of the working group
     * @return The working group's details struct
     */
    function getWorkingGroup(uint256 groupId) external view returns (WorkingGroup memory) {
        return workingGroups[groupId];
    }
    
    /**
     * @dev Get a verification's details
     * @param verificationId ID of the verification
     * @return The verification's details struct
     */
    function getVerification(uint256 verificationId) external view returns (Verification memory) {
        return verifications[verificationId];
    }
}
