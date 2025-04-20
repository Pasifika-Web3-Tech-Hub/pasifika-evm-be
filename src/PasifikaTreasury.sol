// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PasifikaTreasury
 * @dev Contract managing DAO treasury funds with multi-signature control,
 * budget allocation, spending proposals, and automated distributions.
 * Compatible with OpenZeppelin v5.3.0
 */
contract PasifikaTreasury is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TREASURY_MANAGER_ROLE = keccak256("TREASURY_MANAGER_ROLE");
    bytes32 public constant APPROVER_ROLE = keccak256("APPROVER_ROLE");

    // State variables
    uint256 public minApprovals; // Minimum approvals required for spending execution

    // Struct for budget categories
    struct BudgetCategory {
        string name;
        uint256 allocated;
        uint256 spent;
        bool active;
    }

    // Struct for spending proposals
    struct SpendingProposal {
        uint256 categoryId;
        uint256 amount;
        address payable recipient;
        uint256 approvalCount;
        bool executed;
        bool cancelled;
        mapping(address => bool) approvals;
    }

    // State variables
    uint256 private _categoryIdCounter;  // Native counter instead of using Counters library
    uint256 private _spendingIdCounter;  // Native counter instead of using Counters library
    
    mapping(uint256 => BudgetCategory) public budgetCategories;
    mapping(uint256 => SpendingProposal) public spendingProposals;
    
    IERC20 public pasifikaToken; // PSF token address
    address public treasuryWallet; // Cold wallet for treasury reserve funds

    // Events
    event BudgetAllocated(uint256 indexed categoryId, uint256 amount);
    event SpendingProposed(uint256 indexed spendingId, uint256 indexed categoryId, uint256 amount);
    event SpendingApproved(uint256 indexed spendingId, address indexed approver);
    event SpendingExecuted(uint256 indexed spendingId, address indexed recipient, uint256 amount);
    event CategoryCreated(uint256 indexed categoryId, string name);
    event CategoryUpdated(uint256 indexed categoryId, string name, bool active);
    event FundsDeposited(address indexed from, uint256 amount);
    event SpendingCancelled(uint256 indexed spendingId);
    
    /**
     * @dev Constructor sets up initial roles and token address
     * @param _pasifikaToken The address of the PSF token
     * @param _treasuryWallet The wallet address for treasury reserve
     */
    constructor(IERC20 _pasifikaToken, address _treasuryWallet) {
        require(address(_pasifikaToken) != address(0), "Invalid token address");
        require(_treasuryWallet != address(0), "Invalid treasury wallet address");
        
        pasifikaToken = _pasifikaToken;
        treasuryWallet = _treasuryWallet;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(TREASURY_MANAGER_ROLE, msg.sender);
        _grantRole(APPROVER_ROLE, msg.sender);
        
        // Initialize minApprovals to 2
        minApprovals = 2;
        
        // Create default category for operational expenses
        _createCategory("Operational Expenses");
    }

    /**
     * @dev Creates a new budget category
     * @param name The name of the budget category
     * @return The ID of the newly created category
     */
    function createCategory(string calldata name) external onlyRole(TREASURY_MANAGER_ROLE) returns (uint256) {
        return _createCategory(name);
    }

    /**
     * @dev Internal function to create a new budget category
     * @param name The name of the budget category
     * @return The ID of the newly created category
     */
    function _createCategory(string memory name) internal returns (uint256) {
        _categoryIdCounter += 1;
        uint256 categoryId = _categoryIdCounter;
        
        budgetCategories[categoryId] = BudgetCategory({
            name: name,
            allocated: 0,
            spent: 0,
            active: true
        });
        
        emit CategoryCreated(categoryId, name);
        return categoryId;
    }

    /**
     * @dev Updates an existing budget category
     * @param categoryId The ID of the category to update
     * @param name The new name for the category
     * @param active The new active status for the category
     */
    function updateCategory(
        uint256 categoryId, 
        string calldata name, 
        bool active
    ) external onlyRole(TREASURY_MANAGER_ROLE) {
        require(categoryId > 0 && categoryId <= _categoryIdCounter, "Invalid category ID");
        
        BudgetCategory storage category = budgetCategories[categoryId];
        category.name = name;
        category.active = active;
        
        emit CategoryUpdated(categoryId, name, active);
    }

    /**
     * @dev Allocates budget for a specific category
     * @param categoryId The ID of the category to allocate budget for
     * @param amount The amount to allocate
     */
    function allocateBudget(uint256 categoryId, uint256 amount) external onlyRole(TREASURY_MANAGER_ROLE) {
        require(categoryId > 0 && categoryId <= _categoryIdCounter, "Invalid category ID");
        require(amount > 0, "Amount must be greater than 0");
        require(budgetCategories[categoryId].active, "Category is not active");
        require(getTreasuryBalance() >= amount, "Insufficient treasury balance");
        
        budgetCategories[categoryId].allocated += amount;
        
        emit BudgetAllocated(categoryId, amount);
    }

    /**
     * @dev Proposes a new spending from a specific budget category
     * @param categoryId The ID of the category to spend from
     * @param amount The amount to spend
     * @param recipient The recipient of the funds
     * @return The ID of the newly created spending proposal
     */
    function proposeSpending(
        uint256 categoryId, 
        uint256 amount, 
        address payable recipient
    ) external onlyRole(TREASURY_MANAGER_ROLE) returns (uint256) {
        require(categoryId > 0 && categoryId <= _categoryIdCounter, "Invalid category ID");
        require(amount > 0, "Amount must be greater than 0");
        require(recipient != address(0), "Invalid recipient");
        require(budgetCategories[categoryId].active, "Category is not active");
        
        BudgetCategory storage category = budgetCategories[categoryId];
        require(category.allocated - category.spent >= amount, "Insufficient allocated budget");
        
        _spendingIdCounter += 1;
        uint256 spendingId = _spendingIdCounter;
        
        SpendingProposal storage proposal = spendingProposals[spendingId];
        proposal.categoryId = categoryId;
        proposal.amount = amount;
        proposal.recipient = recipient;
        proposal.approvalCount = 0;
        proposal.executed = false;
        proposal.cancelled = false;
        
        emit SpendingProposed(spendingId, categoryId, amount);
        return spendingId;
    }

    /**
     * @dev Approves a pending spending proposal
     * @param spendingId The ID of the spending proposal to approve
     */
    function approveSpending(uint256 spendingId) external onlyRole(APPROVER_ROLE) nonReentrant {
        require(spendingId > 0 && spendingId <= _spendingIdCounter, "Invalid spending ID");
        
        SpendingProposal storage proposal = spendingProposals[spendingId];
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.cancelled, "Proposal was cancelled");
        require(!proposal.approvals[msg.sender], "Already approved");
        
        proposal.approvals[msg.sender] = true;
        proposal.approvalCount += 1;
        
        emit SpendingApproved(spendingId, msg.sender);
    }

    /**
     * @dev Executes a spending proposal after sufficient approvals
     * @param spendingId The ID of the spending proposal to execute
     */
    function executeSpending(uint256 spendingId) external onlyRole(TREASURY_MANAGER_ROLE) nonReentrant {
        require(spendingId > 0 && spendingId <= _spendingIdCounter, "Invalid spending ID");
        
        SpendingProposal storage proposal = spendingProposals[spendingId];
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.cancelled, "Proposal was cancelled");
        require(proposal.approvalCount >= minApprovals, "Insufficient approvals");
        
        uint256 categoryId = proposal.categoryId;
        uint256 amount = proposal.amount;
        address payable recipient = proposal.recipient;
        
        BudgetCategory storage category = budgetCategories[categoryId];
        require(category.allocated - category.spent >= amount, "Insufficient allocated budget");
        
        // Mark as executed before transfer to prevent reentrancy
        proposal.executed = true;
        category.spent += amount;
        
        // Transfer tokens to recipient
        pasifikaToken.safeTransfer(recipient, amount);
        
        emit SpendingExecuted(spendingId, recipient, amount);
    }

    /**
     * @dev Cancels a pending spending proposal
     * @param spendingId The ID of the spending proposal to cancel
     */
    function cancelSpending(uint256 spendingId) external onlyRole(TREASURY_MANAGER_ROLE) {
        require(spendingId > 0 && spendingId <= _spendingIdCounter, "Invalid spending ID");
        
        SpendingProposal storage proposal = spendingProposals[spendingId];
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.cancelled, "Proposal already cancelled");
        
        proposal.cancelled = true;
        
        emit SpendingCancelled(spendingId);
    }

    /**
     * @dev Gets the current treasury balance of PSF tokens
     * @return The balance of PSF tokens held by this contract
     */
    function getTreasuryBalance() public view returns (uint256) {
        return pasifikaToken.balanceOf(address(this));
    }

    /**
     * @dev Gets detailed information about a budget category
     * @param categoryId The ID of the category to query
     * @return name The name of the category
     * @return allocated The amount allocated to the category
     * @return spent The amount spent from the category
     * @return available The amount available to spend from the category
     * @return active Whether the category is active
     */
    function getCategoryDetails(uint256 categoryId) external view returns (
        string memory name,
        uint256 allocated,
        uint256 spent,
        uint256 available,
        bool active
    ) {
        require(categoryId > 0 && categoryId <= _categoryIdCounter, "Invalid category ID");
        
        BudgetCategory storage category = budgetCategories[categoryId];
        name = category.name;
        allocated = category.allocated;
        spent = category.spent;
        available = allocated - spent;
        active = category.active;
    }

    /**
     * @dev Gets information about a spending proposal
     * @param spendingId The ID of the spending proposal to query
     * @return categoryId The ID of the category for this proposal
     * @return amount The proposed spending amount
     * @return recipient The recipient of the funds
     * @return approvalCount The number of approvals received
     * @return executed Whether the proposal has been executed
     * @return cancelled Whether the proposal has been cancelled
     */
    function getProposalDetails(uint256 spendingId) external view returns (
        uint256 categoryId,
        uint256 amount,
        address recipient,
        uint256 approvalCount,
        bool executed,
        bool cancelled
    ) {
        require(spendingId > 0 && spendingId <= _spendingIdCounter, "Invalid spending ID");
        
        SpendingProposal storage proposal = spendingProposals[spendingId];
        categoryId = proposal.categoryId;
        amount = proposal.amount;
        recipient = proposal.recipient;
        approvalCount = proposal.approvalCount;
        executed = proposal.executed;
        cancelled = proposal.cancelled;
    }

    /**
     * @dev Checks if an address has approved a spending proposal
     * @param spendingId The ID of the spending proposal
     * @param approver The address to check for approval
     * @return Whether the address has approved the proposal
     */
    function hasApproved(uint256 spendingId, address approver) external view returns (bool) {
        require(spendingId > 0 && spendingId <= _spendingIdCounter, "Invalid spending ID");
        return spendingProposals[spendingId].approvals[approver];
    }

    /**
     * @dev Deposits PSF tokens into the treasury
     * @param amount The amount of tokens to deposit
     */
    function depositFunds(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        
        pasifikaToken.safeTransferFrom(msg.sender, address(this), amount);
        
        emit FundsDeposited(msg.sender, amount);
    }
    
    /**
     * @dev Updates the treasury wallet address
     * @param newTreasuryWallet The new treasury wallet address
     */
    function setTreasuryWallet(address newTreasuryWallet) external onlyRole(ADMIN_ROLE) {
        require(newTreasuryWallet != address(0), "Invalid treasury wallet address");
        treasuryWallet = newTreasuryWallet;
    }

    /**
     * @dev Allows changing the minimum number of approvals required
     * @param newMinApprovals The new minimum number of approvals
     */
    function setMinApprovals(uint256 newMinApprovals) external onlyRole(ADMIN_ROLE) {
        require(newMinApprovals >= 1, "Min approvals must be at least 1");
        minApprovals = newMinApprovals;
    }

    /**
     * @dev Emergency function to recover ERC20 tokens sent to this contract by mistake
     * @param token The token to recover
     * @param amount The amount to recover
     * @param recipient The recipient of the recovered tokens
     */
    function recoverTokens(
        IERC20 token,
        uint256 amount,
        address recipient
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        require(address(token) != address(pasifikaToken), "Cannot recover treasury token");
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be greater than 0");
        
        token.safeTransfer(recipient, amount);
    }
}
