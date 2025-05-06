// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PasifikaTreasury
 * @dev Treasury contract for managing marketplace and platform fees
 * Simplified version without governance dependencies
 */
contract PasifikaTreasury is AccessControl, ReentrancyGuard, Pausable {
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE");
    bytes32 public constant SPENDER_ROLE = keccak256("SPENDER_ROLE");
    bytes32 public constant FEE_COLLECTOR_ROLE = keccak256("FEE_COLLECTOR_ROLE");

    // Fund allocation structure
    struct FundAllocation {
        string name;
        uint256 allocation; // In percentage basis points (1/100 of a percent) - 10000 = 100%
        uint256 balance;
        bool active;
    }

    // Expense structure
    struct Expense {
        string description;
        address recipient;
        uint256 amount;
        uint256 timestamp;
        bytes32 fundName;
        address approver;
    }

    // Deposit record structure
    struct Deposit {
        address sender;
        uint256 amount;
        uint256 timestamp;
        string description;
    }

    // Fund allocations
    mapping(bytes32 => FundAllocation) public funds;
    bytes32[] public fundNames;

    // Expenses and deposits
    Expense[] public expenses;
    Deposit[] public deposits;

    // Default allocation to unallocated fund
    bytes32 public constant UNALLOCATED_FUND = keccak256("UNALLOCATED");

    // Events
    event FundCreated(bytes32 indexed fundName, string name, uint256 allocation);
    event FundUpdated(bytes32 indexed fundName, uint256 newAllocation);
    event FundDeactivated(bytes32 indexed fundName);
    event AllocationAdjusted(bytes32[] fundNames, uint256[] allocations);
    event FundsDeposited(address indexed sender, uint256 amount, string description);
    event FundsWithdrawn(address indexed recipient, uint256 amount, string description, bytes32 indexed fundName);
    event EmergencyWithdrawal(address indexed admin, uint256 amount, address recipient);
    event ProfitSharingWithdrawal(address indexed recipient, uint256 amount);

    /**
     * @dev Constructor
     * @param admin Address to grant admin role
     */
    constructor(address admin) {
        require(admin != address(0), "PasifikaTreasury: zero address");

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(TREASURER_ROLE, admin);
        _grantRole(SPENDER_ROLE, admin);

        // Create default unallocated fund with 100% allocation
        _createFund(UNALLOCATED_FUND, "Unallocated", 10000);
    }

    /**
     * @dev Receive function to accept CORE tokens
     */
    receive() external payable {
        // Allocate to unallocated fund
        funds[UNALLOCATED_FUND].balance += msg.value;

        // Record deposit
        deposits.push(
            Deposit({ sender: msg.sender, amount: msg.value, timestamp: block.timestamp, description: "Direct deposit" })
        );

        emit FundsDeposited(msg.sender, msg.value, "Direct deposit");
    }

    /**
     * @dev Deposit funds with allocation to specific funds
     * Automatically allocates to funds based on their allocation percentage
     */
    function depositFunds(string memory description) external payable nonReentrant whenNotPaused {
        require(msg.value > 0, "PasifikaTreasury: zero amount");

        // Record deposit
        deposits.push(
            Deposit({ sender: msg.sender, amount: msg.value, timestamp: block.timestamp, description: description })
        );

        // Allocate funds based on allocations
        _allocateFunds(msg.value);

        emit FundsDeposited(msg.sender, msg.value, description);
    }

    /**
     * @dev Deposit fees (only fee collectors can call)
     * @param description Description of the fee
     */
    function depositFees(string memory description) external payable nonReentrant whenNotPaused {
        require(msg.value > 0, "PasifikaTreasury: zero amount");
        require(hasRole(FEE_COLLECTOR_ROLE, msg.sender), "PasifikaTreasury: not a fee collector");

        // Record deposit
        deposits.push(
            Deposit({ sender: msg.sender, amount: msg.value, timestamp: block.timestamp, description: description })
        );

        // Allocate funds based on allocations
        _allocateFunds(msg.value);

        emit FundsDeposited(msg.sender, msg.value, description);
    }

    /**
     * @dev Withdraw funds from a specific fund
     * @param fundName Name of the fund to withdraw from
     * @param recipient Address to send funds to
     * @param amount Amount to withdraw
     * @param description Description of the withdrawal
     */
    function withdraw(bytes32 fundName, address recipient, uint256 amount, string memory description)
        external
        nonReentrant
        whenNotPaused
        onlyRole(SPENDER_ROLE)
    {
        require(recipient != address(0), "PasifikaTreasury: zero address");
        require(amount > 0, "PasifikaTreasury: zero amount");
        require(funds[fundName].active, "PasifikaTreasury: fund not active");
        require(funds[fundName].balance >= amount, "PasifikaTreasury: insufficient funds");

        // Update fund balance
        funds[fundName].balance -= amount;

        // Record expense
        expenses.push(
            Expense({
                description: description,
                recipient: recipient,
                amount: amount,
                timestamp: block.timestamp,
                fundName: fundName,
                approver: msg.sender
            })
        );

        // Transfer funds
        (bool success,) = payable(recipient).call{ value: amount }("");
        require(success, "PasifikaTreasury: transfer failed");

        emit FundsWithdrawn(recipient, amount, description, fundName);
    }

    /**
     * @dev Withdraw funds for profit sharing (only contracts with SPENDER_ROLE)
     * @param recipient Address to send funds to
     * @param amount Amount to withdraw
     * @return success Whether the withdrawal was successful
     */
    function withdrawFunds(address recipient, uint256 amount)
        external
        nonReentrant
        whenNotPaused
        onlyRole(SPENDER_ROLE)
        returns (bool)
    {
        require(recipient != address(0), "PasifikaTreasury: zero address");
        require(amount > 0, "PasifikaTreasury: zero amount");
        require(address(this).balance >= amount, "PasifikaTreasury: insufficient balance");

        // First try to withdraw from the unallocated fund
        if (funds[UNALLOCATED_FUND].balance >= amount) {
            funds[UNALLOCATED_FUND].balance -= amount;
        } else {
            // Otherwise, take proportionally from all active funds
            uint256 remainingAmount = amount;
            for (uint256 i = 0; i < fundNames.length && remainingAmount > 0; i++) {
                bytes32 fundName = fundNames[i];
                if (funds[fundName].active) {
                    uint256 fundAmount = (funds[fundName].balance * remainingAmount) / address(this).balance;
                    if (fundAmount > funds[fundName].balance) {
                        fundAmount = funds[fundName].balance;
                    }
                    if (fundAmount > 0) {
                        funds[fundName].balance -= fundAmount;
                        remainingAmount -= fundAmount;
                    }
                }
            }

            // If there's still a remaining amount, take from unallocated
            if (remainingAmount > 0) {
                require(
                    funds[UNALLOCATED_FUND].balance >= remainingAmount,
                    "PasifikaTreasury: insufficient funds after allocation"
                );
                funds[UNALLOCATED_FUND].balance -= remainingAmount;
            }
        }

        // Record expense for profit sharing
        expenses.push(
            Expense({
                description: "Profit sharing distribution",
                recipient: recipient,
                amount: amount,
                timestamp: block.timestamp,
                fundName: UNALLOCATED_FUND,
                approver: msg.sender
            })
        );

        // Transfer funds
        (bool success,) = payable(recipient).call{ value: amount }("");
        require(success, "PasifikaTreasury: transfer failed");

        emit ProfitSharingWithdrawal(recipient, amount);

        return true;
    }

    /**
     * @dev Create a new fund
     * @param name Human-readable name of the fund
     * @param allocation Percentage allocation in basis points (10000 = 100%)
     */
    function createFund(string memory name, uint256 allocation) external onlyRole(TREASURER_ROLE) {
        bytes32 fundName = keccak256(abi.encodePacked(name));
        _createFund(fundName, name, allocation);
    }

    /**
     * @dev Internal function to create a fund
     * @param fundName Bytes32 identifier of the fund
     * @param name Human-readable name of the fund
     * @param allocation Percentage allocation in basis points
     */
    function _createFund(bytes32 fundName, string memory name, uint256 allocation) internal {
        require(funds[fundName].balance == 0, "PasifikaTreasury: fund already exists");

        // Add to fundNames array
        fundNames.push(fundName);

        // Create fund allocation
        funds[fundName] = FundAllocation({ name: name, allocation: allocation, balance: 0, active: true });

        // Adjust other allocations if needed
        if (fundName != UNALLOCATED_FUND) {
            _adjustAllocations();
        }

        emit FundCreated(fundName, name, allocation);
    }

    /**
     * @dev Update a fund's allocation
     * @param fundName Fund identifier
     * @param newAllocation New allocation percentage in basis points
     */
    function updateFund(bytes32 fundName, uint256 newAllocation) external onlyRole(TREASURER_ROLE) {
        require(funds[fundName].active, "PasifikaTreasury: fund not active");

        // Update allocation
        funds[fundName].allocation = newAllocation;

        // Adjust other allocations
        _adjustAllocations();

        emit FundUpdated(fundName, newAllocation);
    }

    /**
     * @dev Deactivate a fund
     * @param fundName Fund identifier
     */
    function deactivateFund(bytes32 fundName) external onlyRole(TREASURER_ROLE) {
        require(fundName != UNALLOCATED_FUND, "PasifikaTreasury: cannot deactivate unallocated fund");
        require(funds[fundName].active, "PasifikaTreasury: fund already inactive");

        // Move remaining balance to unallocated
        uint256 remainingBalance = funds[fundName].balance;
        if (remainingBalance > 0) {
            funds[fundName].balance = 0;
            funds[UNALLOCATED_FUND].balance += remainingBalance;
        }

        // Deactivate fund
        funds[fundName].active = false;
        funds[fundName].allocation = 0;

        // Adjust other allocations
        _adjustAllocations();

        emit FundDeactivated(fundName);
    }

    /**
     * @dev Update all fund allocations at once
     * @param updatedFundNames Array of fund names to update
     * @param updatedAllocations Array of new allocations
     */
    function updateAllFundAllocations(bytes32[] memory updatedFundNames, uint256[] memory updatedAllocations)
        external
        onlyRole(TREASURER_ROLE)
    {
        require(updatedFundNames.length == updatedAllocations.length, "PasifikaTreasury: length mismatch");

        // Update allocations
        for (uint256 i = 0; i < updatedFundNames.length; i++) {
            require(funds[updatedFundNames[i]].active, "PasifikaTreasury: fund not active");
            funds[updatedFundNames[i]].allocation = updatedAllocations[i];
        }

        // Manually verify total allocation is 10000 (100%)
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < fundNames.length; i++) {
            if (funds[fundNames[i]].active) {
                totalAllocation += funds[fundNames[i]].allocation;
            }
        }
        require(totalAllocation == 10000, "PasifikaTreasury: total allocation must be 100%");

        emit AllocationAdjusted(updatedFundNames, updatedAllocations);
    }

    /**
     * @dev Internal function to allocate funds based on fund allocations
     * @param amount Amount to allocate
     */
    function _allocateFunds(uint256 amount) internal {
        // Get total allocation percentage
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < fundNames.length; i++) {
            if (funds[fundNames[i]].active) {
                totalAllocation += funds[fundNames[i]].allocation;
            }
        }

        // If no allocations, put everything in unallocated
        if (totalAllocation == 0) {
            funds[UNALLOCATED_FUND].balance += amount;
            return;
        }

        // Allocate based on percentages
        uint256 remainingAmount = amount;
        for (uint256 i = 0; i < fundNames.length && remainingAmount > 0; i++) {
            if (funds[fundNames[i]].active && funds[fundNames[i]].allocation > 0) {
                uint256 fundAmount = (amount * funds[fundNames[i]].allocation) / totalAllocation;
                if (fundAmount > remainingAmount) {
                    fundAmount = remainingAmount;
                }
                if (fundAmount > 0) {
                    funds[fundNames[i]].balance += fundAmount;
                    remainingAmount -= fundAmount;
                }
            }
        }

        // If there's any remainder due to rounding, add to unallocated fund
        if (remainingAmount > 0) {
            funds[UNALLOCATED_FUND].balance += remainingAmount;
        }
    }

    /**
     * @dev Internal function to adjust allocations after changes
     * Ensures allocations always sum to 10000 (100%)
     */
    function _adjustAllocations() internal {
        // Calculate active funds and total current allocation
        uint256 activeFunds = 0;
        uint256 totalAllocation = 0;
        for (uint256 i = 0; i < fundNames.length; i++) {
            if (funds[fundNames[i]].active) {
                activeFunds++;
                totalAllocation += funds[fundNames[i]].allocation;
            }
        }

        // If total is already 10000, we're done
        if (totalAllocation == 10000) {
            return;
        }

        // Adjust unallocated fund to make total 10000
        funds[UNALLOCATED_FUND].allocation = 10000 - (totalAllocation - funds[UNALLOCATED_FUND].allocation);
    }

    /**
     * @dev Add a fee collector (admin only)
     * @param collector Address to grant fee collector role
     */
    function addFeeCollector(address collector) external onlyRole(ADMIN_ROLE) {
        require(collector != address(0), "PasifikaTreasury: zero address");
        grantRole(FEE_COLLECTOR_ROLE, collector);
    }

    /**
     * @dev Remove a fee collector (admin only)
     * @param collector Address to revoke fee collector role from
     */
    function removeFeeCollector(address collector) external onlyRole(ADMIN_ROLE) {
        revokeRole(FEE_COLLECTOR_ROLE, collector);
    }

    /**
     * @dev Get total treasury balance
     * @return Total balance of the treasury
     */
    function getTotalBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Get details for a specific fund
     * @param fundName Name of the fund to query
     * @return name Human-readable name
     * @return allocation Allocation percentage in basis points
     * @return balance Current balance
     * @return active Whether the fund is active
     */
    function getFundDetails(bytes32 fundName)
        external
        view
        returns (string memory name, uint256 allocation, uint256 balance, bool active)
    {
        FundAllocation storage fund = funds[fundName];
        return (fund.name, fund.allocation, fund.balance, fund.active);
    }

    /**
     * @dev Get all active fund names
     * @return Array of active fund names
     */
    function getActiveFunds() external view returns (bytes32[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < fundNames.length; i++) {
            if (funds[fundNames[i]].active) {
                activeCount++;
            }
        }

        bytes32[] memory activeFundNames = new bytes32[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < fundNames.length; i++) {
            if (funds[fundNames[i]].active) {
                activeFundNames[index++] = fundNames[i];
            }
        }

        return activeFundNames;
    }

    /**
     * @dev Emergency withdraw all funds (admin only)
     * @param recipient Address to withdraw to
     */
    function emergencyWithdraw(address recipient) external onlyRole(ADMIN_ROLE) {
        require(recipient != address(0), "PasifikaTreasury: zero address");

        uint256 balance = address(this).balance;
        require(balance > 0, "PasifikaTreasury: no balance");

        // Reset all fund balances
        for (uint256 i = 0; i < fundNames.length; i++) {
            funds[fundNames[i]].balance = 0;
        }

        // Transfer all balance
        (bool success,) = payable(recipient).call{ value: balance }("");
        require(success, "PasifikaTreasury: transfer failed");

        emit EmergencyWithdrawal(msg.sender, balance, recipient);
    }

    /**
     * @dev Pause the contract (admin only)
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause the contract (admin only)
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}
