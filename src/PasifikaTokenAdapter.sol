// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title PasifikaTokenAdapter
 * @dev Interface for token operations across different networks
 * This interface standardizes token operations for the Pasifika ecosystem
 * across different blockchains (Linea, Arbitrum, RootStock)
 */
interface PasifikaTokenAdapter {
    /**
     * @dev Transfers tokens from the sender to the recipient
     * @param token Address of the token to transfer
     * @param recipient Address of the recipient
     * @param amount Amount of tokens to transfer
     * @return success Whether the transfer was successful
     */
    function transferToken(address token, address recipient, uint256 amount) 
        external 
        returns (bool success);
    
    /**
     * @dev Checks if a token is supported
     * @param token Address of the token to check
     * @return Whether the token is supported
     */
    function isTokenSupported(address token) external view returns (bool);
    
    /**
     * @dev Gets the symbol of a token
     * @param token Address of the token
     * @return The symbol of the token
     */
    function getTokenSymbol(address token) external view returns (string memory);
}
