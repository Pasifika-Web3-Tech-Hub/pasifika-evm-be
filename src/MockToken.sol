// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";

/**
 * @title MockToken
 * @dev A mock token implementation with voting capabilities for testing the PasifikaDAO
 * Compatible with OpenZeppelin v5.3.0
 */
contract MockToken is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    // Create a role for minting
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(string memory name, string memory symbol) 
        ERC20(name, symbol)
        ERC20Permit(name)
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    /**
     * @dev Mints tokens to the specified address
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens including mint and burn
     * @param from The address tokens are transferred from
     * @param to The address tokens are transferred to
     * @param amount The amount of tokens being transferred
     */
    function _update(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._update(from, to, amount);
    }

    /**
     * @dev Returns the address's nonce, used for permit signatures
     * @param owner The address to get the nonce for
     */
    function nonces(address owner) public view override(Nonces, ERC20Permit) returns (uint256) {
        return super.nonces(owner);
    }

    /**
     * @dev Override of supportsInterface to support AccessControl
     * @param interfaceId The interface to check support for
     */
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
