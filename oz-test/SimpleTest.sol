// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

// This is a standalone test showing OpenZeppelin error patterns
contract SimpleTest is Test {
    // Error definitions from OpenZeppelin
    error AccessControlUnauthorizedAccount(address account, bytes32 role);
    error EnforcedPause();
    
    function testErrorHandling() public {
        bytes32 role = keccak256("ADMIN_ROLE");
        address unauthorized = address(999);
        
        // Test the AccessControlUnauthorizedAccount error
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                unauthorized,
                role
            )
        );
        revert AccessControlUnauthorizedAccount(unauthorized, role);
        
        // Test the EnforcedPause error
        vm.expectRevert(EnforcedPause.selector);
        revert EnforcedPause();
    }
}
