// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "forge-std/console.sol";

/**
 * @title PSFToken
 * @dev Implementation of the PASIFIKA Token (PSF)
 * This token implements governance extensions, vesting schedules, and staking
 */
contract PSFToken is ERC20, ERC20Permit, ERC20Votes, AccessControl, Pausable {
    // Constants
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18; // 1 billion tokens
    
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    
    // Vesting structures
    struct VestingSchedule {
        uint256 totalAmount;
        uint256 startTime;
        uint256 cliffDuration;
        uint256 duration;
        uint256 releasedAmount;
        bool revocable;
        bool revoked;
    }
    
    // Staking structures
    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        bool active;
    }
    
    // State variables
    mapping(address => VestingSchedule) public vestingSchedules;
    mapping(address => mapping(uint256 => Stake)) public stakes;
    mapping(address => uint256) public stakeCount;
    
    // Events
    event VestingScheduleCreated(address indexed beneficiary, uint256 amount, uint256 startTime, uint256 duration);
    event VestingTokensReleased(address indexed beneficiary, uint256 amount);
    event VestingScheduleRevoked(address indexed beneficiary, uint256 unreleasedAmount);
    event Staked(address indexed user, uint256 amount, uint256 duration, uint256 stakeId);
    event Unstaked(address indexed user, uint256 amount, uint256 stakeId);
    event Burned(address indexed burner, uint256 amount);
    event DebugAddress(address sender);
    
    /**
     * @dev Constructor - initializes the token and roles
     */
    constructor()
        ERC20("PASIFIKA Token", "PSF")
        ERC20Permit("PASIFIKA Token")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(BURNER_ROLE, msg.sender);
        _grantRole(TREASURY_ROLE, msg.sender);
    }
    
    /**
     * @dev Creates tokens and assigns them to account
     * Can only be called by the minter role
     * @param to Address to which tokens will be minted
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(totalSupply() + amount <= MAX_SUPPLY, "PSFToken: max supply exceeded");
        _mint(to, amount);
    }
    
    /**
     * @dev Burns tokens from the caller
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        emit Burned(msg.sender, amount);
    }
    
    /**
     * @dev Burns tokens from a specified account (requires approval)
     * Can only be called by the burner role
     * @param account Address from which tokens will be burned
     * @param amount Amount of tokens to burn
     */
    function burnFrom(address account, uint256 amount) external onlyRole(BURNER_ROLE) {
        uint256 currentAllowance = allowance(account, msg.sender);
        require(currentAllowance >= amount, "PSFToken: burn amount exceeds allowance");
        
        unchecked {
            _approve(account, msg.sender, currentAllowance - amount);
        }
        
        _burn(account, amount);
        emit Burned(account, amount);
    }
    
    /**
     * @dev Creates a vesting schedule for a beneficiary
     * Can only be called by an admin
     * @param beneficiary Address of the beneficiary
     * @param amount Total amount of tokens to be vested
     * @param cliffDuration Duration in seconds before which no tokens can be released
     * @param duration Total duration in seconds for the vesting period
     * @param revocable Whether the vesting is revocable or not
     */
    function createVestingSchedule(
        address beneficiary,
        uint256 amount,
        uint256 cliffDuration,
        uint256 duration,
        bool revocable
    ) external onlyRole(ADMIN_ROLE) {
        require(beneficiary != address(0), "PSFToken: beneficiary is zero address");
        require(vestingSchedules[beneficiary].totalAmount == 0, "PSFToken: vesting schedule already exists");
        require(amount > 0, "PSFToken: amount is 0");
        require(duration > 0, "PSFToken: duration is 0");
        require(duration >= cliffDuration, "PSFToken: cliff is longer than duration");

        uint256 startTime = block.timestamp;

        vestingSchedules[beneficiary] = VestingSchedule({
            totalAmount: amount,
            startTime: startTime,
            cliffDuration: cliffDuration,
            duration: duration,
            releasedAmount: 0,
            revocable: revocable,
            revoked: false
        });

        // Instead of transferFrom, require the contract is pre-funded
        require(balanceOf(address(this)) >= amount, "PSFToken: contract not funded");

        emit VestingScheduleCreated(beneficiary, amount, startTime, duration);
    }
    
    /**
     * @dev Release vested tokens to the beneficiary
     * @param beneficiary Address of the beneficiary
     */
    function releaseVestedTokens(address beneficiary) external {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        require(schedule.totalAmount > 0, "PSFToken: no vesting schedule exists");
        require(!schedule.revoked, "PSFToken: vesting schedule revoked");
        
        uint256 releasable = calculateReleasableAmount(beneficiary);
        require(releasable > 0, "PSFToken: no tokens are due for release");
        
        schedule.releasedAmount = schedule.releasedAmount + releasable;
        
        // Transfer tokens to beneficiary
        _transfer(address(this), beneficiary, releasable);
        
        emit VestingTokensReleased(beneficiary, releasable);
    }
    
    /**
     * @dev Revoke the vesting schedule
     * Can only be called by an admin
     * @param beneficiary Address of the beneficiary
     */
    function revokeVestingSchedule(address beneficiary) external onlyRole(ADMIN_ROLE) {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        require(schedule.totalAmount > 0, "PSFToken: no vesting schedule exists");
        require(schedule.revocable, "PSFToken: vesting schedule not revocable");
        require(!schedule.revoked, "PSFToken: vesting schedule already revoked");
        
        uint256 releasable = calculateReleasableAmount(beneficiary);
        
        // Release any due tokens first
        if (releasable > 0) {
            schedule.releasedAmount = schedule.releasedAmount + releasable;
            _transfer(address(this), beneficiary, releasable);
            emit VestingTokensReleased(beneficiary, releasable);
        }
        
        // Calculate unreleased amount
        uint256 unreleased = schedule.totalAmount - schedule.releasedAmount;
        
        // Mark as revoked
        schedule.revoked = true;
        
        // Return unreleased tokens to admin
        if (unreleased > 0) {
            _transfer(address(this), msg.sender, unreleased);
        }
        
        emit VestingScheduleRevoked(beneficiary, unreleased);
    }
    
    /**
     * @dev Calculate amount of tokens that can be released right now
     * @param beneficiary Address of the beneficiary
     * @return Amount of releasable tokens
     */
    function calculateReleasableAmount(address beneficiary) public view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[beneficiary];
        
        if (schedule.totalAmount == 0 || schedule.revoked) {
            return 0;
        }
        
        // Before cliff, nothing is releasable
        if (block.timestamp < schedule.startTime + schedule.cliffDuration) {
            return 0;
        }
        
        // After vesting has completed, all remaining tokens are releasable
        if (block.timestamp >= schedule.startTime + schedule.duration) {
            return schedule.totalAmount - schedule.releasedAmount;
        }
        
        // Calculate releasable amount based on linear vesting
        uint256 timeFromStart = block.timestamp - schedule.startTime;
        uint256 vestedAmount = schedule.totalAmount * timeFromStart / schedule.duration;
        
        return vestedAmount - schedule.releasedAmount;
    }
    
    /**
     * @dev Create a new stake
     * @param amount Amount of tokens to stake
     * @param duration Duration of the stake in seconds
     * @return Id of the created stake
     */
    function stake(uint256 amount, uint256 duration) external whenNotPaused returns (uint256) {
        require(amount > 0, "PSFToken: stake amount must be greater than 0");
        require(duration > 0, "PSFToken: stake duration must be greater than 0");
        require(balanceOf(msg.sender) >= amount, "PSFToken: insufficient balance");
        
        uint256 stakeId = stakeCount[msg.sender];
        uint256 endTime = block.timestamp + duration;
        
        // Create stake
        stakes[msg.sender][stakeId] = Stake({
            amount: amount,
            startTime: block.timestamp,
            endTime: endTime,
            active: true
        });
        
        // Increment stake count
        stakeCount[msg.sender] = stakeId + 1;
        
        // Transfer tokens to this contract
        _transfer(msg.sender, address(this), amount);
        
        emit Staked(msg.sender, amount, duration, stakeId);
        
        return stakeId;
    }
    
    /**
     * @dev Unstake tokens
     * @param stakeId Id of the stake to unstake
     */
    function unstake(uint256 stakeId) external {
        Stake storage userStake = stakes[msg.sender][stakeId];
        
        require(userStake.active, "PSFToken: stake not active");
        require(block.timestamp >= userStake.endTime, "PSFToken: stake still locked");
        
        // Mark stake as inactive
        userStake.active = false;
        
        // Transfer tokens back to user
        _transfer(address(this), msg.sender, userStake.amount);
        
        emit Unstaked(msg.sender, userStake.amount, stakeId);
    }
    
    /**
     * @dev Calculate voting weight based on stakes
     * @param account Address to check
     * @return The voting weight
     */
    function getStakingWeight(address account) external view returns (uint256) {
        uint256 weight = 0;
        
        for (uint256 i = 0; i < stakeCount[account]; i++) {
            Stake memory userStake = stakes[account][i];
            
            if (userStake.active) {
                // Calculate weight based on amount and remaining duration
                uint256 remainingTime = 0;
                if (userStake.endTime > block.timestamp) {
                    remainingTime = userStake.endTime - block.timestamp;
                }
                
                // Weight formula: amount * (1 + remainingTime / 30 days)
                uint256 durationBonus = remainingTime * 1e18 / 30 days;
                uint256 stakeWeight = userStake.amount * (1e18 + durationBonus) / 1e18;
                
                weight = weight + stakeWeight;
            }
        }
        
        return weight;
    }
    
    /**
     * @dev Returns the amount of tokens staked by an account
     * @param account Address to check
     * @return Total staked amount
     */
    function totalStakedAmount(address account) external view returns (uint256) {
        uint256 total = 0;
        
        for (uint256 i = 0; i < stakeCount[account]; i++) {
            Stake memory userStake = stakes[account][i];
            
            if (userStake.active) {
                total = total + userStake.amount;
            }
        }
        
        return total;
    }
    
    /**
     * @dev Pause token transfers and staking
     * Can only be called by an admin
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpause token transfers and staking
     * Can only be called by an admin
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
    
    /**
     * @dev OpenZeppelin 5.x+ override for transfer logic
     */
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        _requireNotPaused(); 
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return "PASIFIKA Token";
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return "PSF";
    }
    
    /**
     * @dev Returns the number of decimals used to get its user representation.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }
}