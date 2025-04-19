// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PSFStaking
 * @dev Contract managing staking operations and rewards for the PASIFIKA ecosystem
 * Handles multiple staking tiers, rewards, and governance weight calculation
 */
contract PSFStaking is AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant REWARDS_DISTRIBUTOR_ROLE = keccak256("REWARDS_DISTRIBUTOR_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 public constant NODE_OPERATOR_ROLE = keccak256("NODE_OPERATOR_ROLE");

    // Staking tiers
    enum StakingTier {
        Basic,      // Basic staking tier
        Silver,     // Silver tier, 10% APY
        Gold,       // Gold tier, 15% APY
        Platinum,   // Platinum tier, 20% APY
        Validator,  // Validator tier, 25% APY
        NodeOperator // Node operator tier, 30% APY
    }

    // Staking structure
    struct StakeInfo {
        uint256 id;               // Unique identifier for the stake
        address owner;            // Address of the stake owner
        uint256 amount;           // Amount of tokens staked
        uint256 startTime;        // When the stake started
        uint256 endTime;          // When the stake can be withdrawn
        uint256 lastClaimTime;    // Last time rewards were claimed
        StakingTier tier;         // Staking tier
        bool active;              // Whether the stake is active
    }

    // Tier requirements
    struct TierRequirement {
        uint256 minAmount;        // Minimum amount required for this tier
        uint256 minDuration;      // Minimum duration (in seconds) required
        uint256 rewardMultiplier; // Reward multiplier (in basis points - 10000 = 100%)
        uint256 governanceWeight; // Governance voting weight multiplier (10000 = 1x)
        bool enabled;             // Whether this tier is enabled
    }

    // Duration bonus structure
    struct DurationBonus {
        uint256 minDuration;      // Minimum duration in seconds
        uint256 bonusMultiplier;  // Bonus multiplier in basis points
    }

    // State variables
    IERC20 public psfToken;                // Reference to the PSF token
    uint256 public totalStaked;            // Total tokens staked
    uint256 private nextStakeId = 1;       // Counter for stake IDs
    uint256 public rewardRate;             // Base reward rate in tokens per second (scaled by 1e18)
    uint256 public rewardsPool;            // Available rewards for distribution
    
    // Minimums and maximums
    uint256 public constant MIN_STAKE_AMOUNT = 100 * 10**18;   // 100 PSF tokens
    uint256 public constant MIN_STAKE_DURATION = 7 days;       // 1 week
    uint256 public constant MAX_STAKE_DURATION = 1825 days;    // 5 years
    uint256 public constant BASIS_POINTS = 10000;              // For percentage calculations
    
    // Mappings
    mapping(address => mapping(uint256 => StakeInfo)) public stakes;           // user => stakeId => StakeInfo
    mapping(address => uint256[]) public userStakeIds;                         // user => array of stake IDs
    mapping(StakingTier => TierRequirement) public tierRequirements;           // Tier requirements
    mapping(uint256 => DurationBonus) public durationBonuses;                  // Duration index => bonus info
    uint256 public durationBonusCount;                                         // Number of duration bonuses
    
    // For validators and node operators
    mapping(address => bool) public isActiveValidator;            // Whether an address is an active validator
    mapping(address => bool) public isActiveNodeOperator;         // Whether an address is an active node operator
    uint256 public validatorCount;                                // Number of active validators
    uint256 public nodeOperatorCount;                             // Number of active node operators
    
    // Validator and node operator stakes
    mapping(address => uint256) public validatorStakeId;          // Address => stake ID for validator stake
    mapping(address => uint256) public nodeOperatorStakeId;       // Address => stake ID for node operator stake

    // Events
    event Staked(address indexed user, uint256 amount, uint256 duration, StakingTier tier, uint256 stakeId);
    event StakeIncreased(address indexed user, uint256 stakeId, uint256 additionalAmount);
    event StakeExtended(address indexed user, uint256 stakeId, uint256 newEndTime);
    event Unstaked(address indexed user, uint256 stakeId, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 stakeId, uint256 amount);
    event TierRequirementUpdated(StakingTier tier, uint256 minAmount, uint256 minDuration, uint256 rewardMultiplier, uint256 governanceWeight);
    event DurationBonusUpdated(uint256 index, uint256 minDuration, uint256 bonusMultiplier);
    event RewardsAdded(uint256 amount);
    event ValidatorActivated(address indexed validator, uint256 stakeId);
    event ValidatorDeactivated(address indexed validator);
    event NodeOperatorActivated(address indexed operator, uint256 stakeId);
    event NodeOperatorDeactivated(address indexed operator);

    /**
     * @dev Constructor - sets up initial contract parameters
     * @param _psfToken Address of the PSF token contract
     * @param _admin Initial admin address
     * @param _rewardsDistributor Address authorized to distribute rewards
     */
    constructor(
        address _psfToken,
        address _admin,
        address _rewardsDistributor
    ) {
        require(_psfToken != address(0), "PSFStaking: PSF token address cannot be zero");
        require(_admin != address(0), "PSFStaking: Admin address cannot be zero");
        require(_rewardsDistributor != address(0), "PSFStaking: Rewards distributor address cannot be zero");
        
        psfToken = IERC20(_psfToken);
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(REWARDS_DISTRIBUTOR_ROLE, _rewardsDistributor);
        
        // Set up tier requirements (these can be adjusted by admin later)
        _setTierRequirement(StakingTier.Basic, 100 * 10**18, 7 days, 500, 10000); // 5% APY, 1x governance
        _setTierRequirement(StakingTier.Silver, 1000 * 10**18, 30 days, 1000, 12000); // 10% APY, 1.2x governance
        _setTierRequirement(StakingTier.Gold, 10000 * 10**18, 90 days, 1500, 15000); // 15% APY, 1.5x governance
        _setTierRequirement(StakingTier.Platinum, 50000 * 10**18, 180 days, 2000, 20000); // 20% APY, 2x governance
        _setTierRequirement(StakingTier.Validator, 100000 * 10**18, 365 days, 2500, 25000); // 25% APY, 2.5x governance
        _setTierRequirement(StakingTier.NodeOperator, 250000 * 10**18, 365 days, 3000, 30000); // 30% APY, 3x governance
        
        // Set up duration bonuses
        _addDurationBonus(90 days, 500);   // 5% bonus for 3+ months
        _addDurationBonus(180 days, 1000); // 10% bonus for 6+ months
        _addDurationBonus(365 days, 2000); // 20% bonus for 1+ year
        _addDurationBonus(730 days, 3000); // 30% bonus for 2+ years
        
        // Set initial reward rate at 10% APY
        // This means for every 1 PSF token staked, 0.1 PSF is earned per year
        // Scaled by 1e18 and calculated per second: (0.1 * 1e18) / (365 days * 24 hours * 60 minutes * 60 seconds)
        rewardRate = (10 * 10**16) / uint256(365 * 24 * 60 * 60);
    }

    /**
     * @dev Create a new stake
     * @param amount Amount of tokens to stake
     * @param duration Duration of the stake in seconds
     * @return Id of the created stake
     */
    function createStake(uint256 amount, uint256 duration) external nonReentrant whenNotPaused returns (uint256) {
        require(amount >= MIN_STAKE_AMOUNT, "PSFStaking: Amount below minimum");
        require(duration >= MIN_STAKE_DURATION, "PSFStaking: Duration below minimum");
        require(duration <= MAX_STAKE_DURATION, "PSFStaking: Duration above maximum");
        
        // Determine the stake tier based on amount and duration
        StakingTier tier = _determineTier(amount, duration);
        
        // Transfer tokens from user to this contract
        psfToken.safeTransferFrom(msg.sender, address(this), amount);
        
        // Create the stake
        uint256 stakeId = nextStakeId++;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + duration;
        
        StakeInfo memory newStake = StakeInfo({
            id: stakeId,
            owner: msg.sender,
            amount: amount,
            startTime: startTime,
            endTime: endTime,
            lastClaimTime: startTime,
            tier: tier,
            active: true
        });
        
        // Store the stake information
        stakes[msg.sender][stakeId] = newStake;
        userStakeIds[msg.sender].push(stakeId);
        
        // Update total staked amount
        totalStaked += amount;
        
        // Special handling for validators and node operators
        if (tier == StakingTier.Validator && hasRole(VALIDATOR_ROLE, msg.sender)) {
            _activateValidator(msg.sender, stakeId);
        } else if (tier == StakingTier.NodeOperator && hasRole(NODE_OPERATOR_ROLE, msg.sender)) {
            _activateNodeOperator(msg.sender, stakeId);
        }
        
        emit Staked(msg.sender, amount, duration, tier, stakeId);
        return stakeId;
    }

    /**
     * @dev Increase the amount of an existing stake
     * @param stakeId ID of the stake to increase
     * @param additionalAmount Additional amount to stake
     */
    function increaseStake(uint256 stakeId, uint256 additionalAmount) external nonReentrant whenNotPaused {
        require(additionalAmount > 0, "PSFStaking: Amount must be greater than 0");
        
        StakeInfo storage stake = stakes[msg.sender][stakeId];
        require(stake.active, "PSFStaking: Stake not active");
        require(stake.owner == msg.sender, "PSFStaking: Not stake owner");
        
        // Claim any pending rewards first
        _claimRewards(stakeId);
        
        // Transfer additional tokens from user
        psfToken.safeTransferFrom(msg.sender, address(this), additionalAmount);
        
        // Update stake amount
        stake.amount += additionalAmount;
        totalStaked += additionalAmount;
        
        // Check if the increased amount changes the tier
        StakingTier newTier = _determineTier(stake.amount, stake.endTime - block.timestamp);
        if (newTier != stake.tier) {
            stake.tier = newTier;
        }
        
        emit StakeIncreased(msg.sender, stakeId, additionalAmount);
    }

    /**
     * @dev Extend the duration of an existing stake
     * @param stakeId ID of the stake to extend
     * @param additionalDuration Additional time in seconds to extend the stake
     */
    function extendStake(uint256 stakeId, uint256 additionalDuration) external nonReentrant whenNotPaused {
        require(additionalDuration > 0, "PSFStaking: Duration must be greater than 0");
        
        StakeInfo storage stake = stakes[msg.sender][stakeId];
        require(stake.active, "PSFStaking: Stake not active");
        require(stake.owner == msg.sender, "PSFStaking: Not stake owner");
        
        // Claim any pending rewards first
        _claimRewards(stakeId);
        
        // Ensure the new total duration doesn't exceed maximum
        uint256 originalDuration = stake.endTime - stake.startTime;
        uint256 newTotalDuration = originalDuration + additionalDuration;
        require(newTotalDuration <= MAX_STAKE_DURATION, "PSFStaking: Duration exceeds maximum");
        
        // Update stake end time
        stake.endTime += additionalDuration;
        
        // Check if the new duration changes the tier
        StakingTier newTier = _determineTier(stake.amount, newTotalDuration);
        if (newTier != stake.tier) {
            stake.tier = newTier;
        }
        
        emit StakeExtended(msg.sender, stakeId, stake.endTime);
    }

    /**
     * @dev Unstake tokens after the lock period has ended
     * @param stakeId ID of the stake to unstake
     */
    function unstake(uint256 stakeId) external nonReentrant {
        StakeInfo storage stake = stakes[msg.sender][stakeId];
        require(stake.active, "PSFStaking: Stake not active");
        require(stake.owner == msg.sender, "PSFStaking: Not stake owner");
        require(block.timestamp >= stake.endTime, "PSFStaking: Stake locked");
        
        // Claim any pending rewards first
        _claimRewards(stakeId);
        
        // Mark stake as inactive
        stake.active = false;
        
        // Update total staked amount
        totalStaked -= stake.amount;
        
        // Handle validator or node operator deactivation
        if (stake.tier == StakingTier.Validator && validatorStakeId[msg.sender] == stakeId) {
            _deactivateValidator(msg.sender);
        } else if (stake.tier == StakingTier.NodeOperator && nodeOperatorStakeId[msg.sender] == stakeId) {
            _deactivateNodeOperator(msg.sender);
        }
        
        // Transfer tokens back to owner
        psfToken.safeTransfer(msg.sender, stake.amount);
        
        emit Unstaked(msg.sender, stakeId, stake.amount);
    }

    /**
     * @dev Claim rewards for a stake
     * @param stakeId ID of the stake to claim rewards for
     * @return Reward amount claimed
     */
    function claimRewards(uint256 stakeId) external nonReentrant returns (uint256) {
        StakeInfo storage stake = stakes[msg.sender][stakeId];
        require(stake.active, "PSFStaking: Stake not active");
        require(stake.owner == msg.sender, "PSFStaking: Not stake owner");
        
        return _claimRewards(stakeId);
    }

    /**
     * @dev Internal function to claim rewards
     * @param stakeId ID of the stake to claim rewards for
     * @return Reward amount claimed
     */
    function _claimRewards(uint256 stakeId) internal returns (uint256) {
        StakeInfo storage stake = stakes[msg.sender][stakeId];
        
        // Calculate rewards
        uint256 rewards = calculateRewards(msg.sender, stakeId);
        if (rewards == 0) {
            return 0;
        }
        
        // Update last claim time
        stake.lastClaimTime = block.timestamp;
        
        // Ensure we have enough rewards to distribute
        require(rewards <= rewardsPool, "PSFStaking: Insufficient rewards in pool");
        rewardsPool -= rewards;
        
        // Transfer rewards to user
        psfToken.safeTransfer(msg.sender, rewards);
        
        emit RewardsClaimed(msg.sender, stakeId, rewards);
        return rewards;
    }

    /**
     * @dev Calculate pending rewards for a stake
     * @param user Address of the stake owner
     * @param stakeId ID of the stake
     * @return Reward amount
     */
    function calculateRewards(address user, uint256 stakeId) public view returns (uint256) {
        StakeInfo storage stake = stakes[user][stakeId];
        if (!stake.active || stake.lastClaimTime >= block.timestamp) {
            return 0;
        }
        
        // Calculate time elapsed since last claim
        uint256 timeElapsed = block.timestamp - stake.lastClaimTime;
        
        // Get base reward rate for this tier
        uint256 tierRate = rewardRate * tierRequirements[stake.tier].rewardMultiplier / BASIS_POINTS;
        
        // Calculate duration bonus
        uint256 durationBonus = _getDurationBonus(stake.endTime - stake.startTime);
        
        // Calculate effective rate including duration bonus
        uint256 effectiveRate = tierRate * (BASIS_POINTS + durationBonus) / BASIS_POINTS;
        
        // Calculate rewards: amount * rate * time
        uint256 rewards = stake.amount * effectiveRate * timeElapsed / 1e18;
        
        return rewards;
    }

    /**
     * @dev Calculate governance voting weight based on stakes
     * @param account Address to calculate weight for
     * @return Governance weight (scaled by 1e18)
     */
    function getGovernanceWeight(address account) external view returns (uint256) {
        uint256[] memory userStakes = userStakeIds[account];
        uint256 weight = 0;
        
        for (uint256 i = 0; i < userStakes.length; i++) {
            StakeInfo storage stake = stakes[account][userStakes[i]];
            
            if (stake.active) {
                // Calculate remaining time percentage if not expired
                uint256 timeMultiplier = BASIS_POINTS; // Default 100%
                if (block.timestamp < stake.endTime) {
                    uint256 totalDuration = stake.endTime - stake.startTime;
                    uint256 remainingDuration = stake.endTime - block.timestamp;
                    timeMultiplier = remainingDuration * BASIS_POINTS / totalDuration;
                }
                
                // Calculate weight using tier governance multiplier
                uint256 tierWeight = tierRequirements[stake.tier].governanceWeight;
                uint256 stakeWeight = stake.amount * tierWeight * timeMultiplier / (BASIS_POINTS * BASIS_POINTS);
                
                weight += stakeWeight;
            }
        }
        
        return weight;
    }

    /**
     * @dev Get all stakes for a user
     * @param user Address to get stakes for
     * @return Array of stake IDs belonging to the user
     */
    function getUserStakes(address user) external view returns (uint256[] memory) {
        return userStakeIds[user];
    }

    /**
     * @dev Get details for a specific stake
     * @param user Owner of the stake
     * @param stakeId ID of the stake
     * @return Full stake information
     */
    function getStakeInfo(address user, uint256 stakeId) external view returns (StakeInfo memory) {
        return stakes[user][stakeId];
    }

    /**
     * @dev Determine the staking tier based on amount and duration
     * @param amount Staking amount
     * @param duration Staking duration
     * @return Appropriate staking tier
     */
    function _determineTier(uint256 amount, uint256 duration) internal view returns (StakingTier) {
        // Check qualification for each tier, from highest to lowest
        if (amount >= tierRequirements[StakingTier.NodeOperator].minAmount && 
            duration >= tierRequirements[StakingTier.NodeOperator].minDuration &&
            tierRequirements[StakingTier.NodeOperator].enabled) {
            return StakingTier.NodeOperator;
        }
        
        if (amount >= tierRequirements[StakingTier.Validator].minAmount && 
            duration >= tierRequirements[StakingTier.Validator].minDuration &&
            tierRequirements[StakingTier.Validator].enabled) {
            return StakingTier.Validator;
        }
        
        if (amount >= tierRequirements[StakingTier.Platinum].minAmount && 
            duration >= tierRequirements[StakingTier.Platinum].minDuration &&
            tierRequirements[StakingTier.Platinum].enabled) {
            return StakingTier.Platinum;
        }
        
        if (amount >= tierRequirements[StakingTier.Gold].minAmount && 
            duration >= tierRequirements[StakingTier.Gold].minDuration &&
            tierRequirements[StakingTier.Gold].enabled) {
            return StakingTier.Gold;
        }
        
        if (amount >= tierRequirements[StakingTier.Silver].minAmount && 
            duration >= tierRequirements[StakingTier.Silver].minDuration &&
            tierRequirements[StakingTier.Silver].enabled) {
            return StakingTier.Silver;
        }
        
        return StakingTier.Basic;
    }

    /**
     * @dev Get duration bonus multiplier based on staking duration
     * @param duration Staking duration in seconds
     * @return Bonus multiplier in basis points
     */
    function _getDurationBonus(uint256 duration) internal view returns (uint256) {
        uint256 highestBonus = 0;
        
        // Check all duration bonuses and find the highest applicable one
        for (uint256 i = 0; i < durationBonusCount; i++) {
            if (duration >= durationBonuses[i].minDuration && 
                durationBonuses[i].bonusMultiplier > highestBonus) {
                highestBonus = durationBonuses[i].bonusMultiplier;
            }
        }
        
        return highestBonus;
    }

    /**
     * @dev Activate a validator based on their stake
     * @param validator Address of the validator
     * @param stakeId ID of the validator's stake
     */
    function _activateValidator(address validator, uint256 stakeId) internal {
        require(hasRole(VALIDATOR_ROLE, validator), "PSFStaking: Not a validator");
        require(!isActiveValidator[validator], "PSFStaking: Already active validator");
        
        isActiveValidator[validator] = true;
        validatorStakeId[validator] = stakeId;
        validatorCount++;
        
        emit ValidatorActivated(validator, stakeId);
    }

    /**
     * @dev Deactivate a validator
     * @param validator Address of the validator
     */
    function _deactivateValidator(address validator) internal {
        require(isActiveValidator[validator], "PSFStaking: Not an active validator");
        
        isActiveValidator[validator] = false;
        validatorStakeId[validator] = 0;
        validatorCount--;
        
        emit ValidatorDeactivated(validator);
    }

    /**
     * @dev Activate a node operator based on their stake
     * @param operator Address of the node operator
     * @param stakeId ID of the operator's stake
     */
    function _activateNodeOperator(address operator, uint256 stakeId) internal {
        require(hasRole(NODE_OPERATOR_ROLE, operator), "PSFStaking: Not a node operator");
        require(!isActiveNodeOperator[operator], "PSFStaking: Already active operator");
        
        isActiveNodeOperator[operator] = true;
        nodeOperatorStakeId[operator] = stakeId;
        nodeOperatorCount++;
        
        emit NodeOperatorActivated(operator, stakeId);
    }

    /**
     * @dev Deactivate a node operator
     * @param operator Address of the node operator
     */
    function _deactivateNodeOperator(address operator) internal {
        require(isActiveNodeOperator[operator], "PSFStaking: Not an active operator");
        
        isActiveNodeOperator[operator] = false;
        nodeOperatorStakeId[operator] = 0;
        nodeOperatorCount--;
        
        emit NodeOperatorDeactivated(operator);
    }

    // ==================== ADMIN FUNCTIONS ====================

    /**
     * @dev Add rewards to the pool
     * @param amount Amount of rewards to add
     */
    function addRewards(uint256 amount) external nonReentrant onlyRole(REWARDS_DISTRIBUTOR_ROLE) {
        require(amount > 0, "PSFStaking: Amount must be greater than 0");
        
        // Transfer tokens from the rewards distributor to this contract
        psfToken.safeTransferFrom(msg.sender, address(this), amount);
        
        // Update rewards pool
        rewardsPool += amount;
        
        emit RewardsAdded(amount);
    }

    /**
     * @dev Set tier requirements
     * @param tier Staking tier to configure
     * @param minAmount Minimum amount required for this tier
     * @param minDuration Minimum duration required for this tier
     * @param rewardMultiplier Reward multiplier in basis points
     * @param governanceWeight Governance weight multiplier in basis points
     */
    function setTierRequirement(
        StakingTier tier,
        uint256 minAmount,
        uint256 minDuration,
        uint256 rewardMultiplier,
        uint256 governanceWeight
    ) external onlyRole(ADMIN_ROLE) {
        _setTierRequirement(tier, minAmount, minDuration, rewardMultiplier, governanceWeight);
    }

    /**
     * @dev Internal function to set tier requirements
     */
    function _setTierRequirement(
        StakingTier tier,
        uint256 minAmount,
        uint256 minDuration,
        uint256 rewardMultiplier,
        uint256 governanceWeight
    ) internal {
        require(minAmount >= MIN_STAKE_AMOUNT, "PSFStaking: Min amount too low");
        require(minDuration >= MIN_STAKE_DURATION, "PSFStaking: Min duration too low");
        require(minDuration <= MAX_STAKE_DURATION, "PSFStaking: Min duration too high");
        
        TierRequirement storage req = tierRequirements[tier];
        req.minAmount = minAmount;
        req.minDuration = minDuration;
        req.rewardMultiplier = rewardMultiplier;
        req.governanceWeight = governanceWeight;
        req.enabled = true;
        
        emit TierRequirementUpdated(tier, minAmount, minDuration, rewardMultiplier, governanceWeight);
    }

    /**
     * @dev Enable or disable a staking tier
     * @param tier Staking tier to update
     * @param enabled Whether the tier should be enabled
     */
    function setTierEnabled(StakingTier tier, bool enabled) external onlyRole(ADMIN_ROLE) {
        tierRequirements[tier].enabled = enabled;
    }

    /**
     * @dev Add a new duration bonus
     * @param minDuration Minimum duration required for this bonus
     * @param bonusMultiplier Bonus multiplier in basis points
     */
    function addDurationBonus(uint256 minDuration, uint256 bonusMultiplier) external onlyRole(ADMIN_ROLE) {
        _addDurationBonus(minDuration, bonusMultiplier);
    }

    /**
     * @dev Internal function to add a duration bonus
     */
    function _addDurationBonus(uint256 minDuration, uint256 bonusMultiplier) internal {
        require(minDuration >= MIN_STAKE_DURATION, "PSFStaking: Min duration too low");
        require(minDuration <= MAX_STAKE_DURATION, "PSFStaking: Min duration too high");
        
        uint256 index = durationBonusCount;
        durationBonuses[index] = DurationBonus({
            minDuration: minDuration,
            bonusMultiplier: bonusMultiplier
        });
        durationBonusCount++;
        
        emit DurationBonusUpdated(index, minDuration, bonusMultiplier);
    }

    /**
     * @dev Update a duration bonus
     * @param index Index of the bonus to update
     * @param minDuration New minimum duration
     * @param bonusMultiplier New bonus multiplier
     */
    function updateDurationBonus(
        uint256 index,
        uint256 minDuration,
        uint256 bonusMultiplier
    ) external onlyRole(ADMIN_ROLE) {
        require(index < durationBonusCount, "PSFStaking: Invalid index");
        require(minDuration >= MIN_STAKE_DURATION, "PSFStaking: Min duration too low");
        require(minDuration <= MAX_STAKE_DURATION, "PSFStaking: Min duration too high");
        
        DurationBonus storage bonus = durationBonuses[index];
        bonus.minDuration = minDuration;
        bonus.bonusMultiplier = bonusMultiplier;
        
        emit DurationBonusUpdated(index, minDuration, bonusMultiplier);
    }

    /**
     * @dev Update the base reward rate
     * @param newRate New reward rate in tokens per second (scaled by 1e18)
     */
    function setRewardRate(uint256 newRate) external onlyRole(ADMIN_ROLE) {
        rewardRate = newRate;
    }

    /**
     * @dev Grant validator role to an address
     * @param validator Address to grant role to
     */
    function grantValidatorRole(address validator) external onlyRole(ADMIN_ROLE) {
        grantRole(VALIDATOR_ROLE, validator);
    }

    /**
     * @dev Revoke validator role from an address
     * @param validator Address to revoke role from
     */
    function revokeValidatorRole(address validator) external onlyRole(ADMIN_ROLE) {
        revokeRole(VALIDATOR_ROLE, validator);
        
        // If they were an active validator, deactivate them
        if (isActiveValidator[validator]) {
            _deactivateValidator(validator);
        }
    }

    /**
     * @dev Grant node operator role to an address
     * @param operator Address to grant role to
     */
    function grantNodeOperatorRole(address operator) external onlyRole(ADMIN_ROLE) {
        grantRole(NODE_OPERATOR_ROLE, operator);
    }

    /**
     * @dev Revoke node operator role from an address
     * @param operator Address to revoke role from
     */
    function revokeNodeOperatorRole(address operator) external onlyRole(ADMIN_ROLE) {
        revokeRole(NODE_OPERATOR_ROLE, operator);
        
        // If they were an active node operator, deactivate them
        if (isActiveNodeOperator[operator]) {
            _deactivateNodeOperator(operator);
        }
    }

    /**
     * @dev Pause contract
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause contract
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Emergency withdraw tokens in case of critical issues
     * @param token Address of the token to withdraw
     * @param amount Amount to withdraw
     * @param recipient Address to receive the tokens
     */
    function emergencyWithdraw(
        address token,
        uint256 amount,
        address recipient
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(recipient != address(0), "PSFStaking: Invalid recipient");
        
        if (token == address(psfToken)) {
            // If withdrawing staking token, ensure we don't take staked tokens
            uint256 available = psfToken.balanceOf(address(this)) - totalStaked;
            require(amount <= available, "PSFStaking: Cannot withdraw staked tokens");
        }
        
        IERC20(token).safeTransfer(recipient, amount);
    }
}
