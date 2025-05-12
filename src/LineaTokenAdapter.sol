// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {PasifikaTokenAdapter} from "./PasifikaTokenAdapter.sol";

/**
 * @title LineaTokenAdapter
 * @dev Adapter for handling token operations on Linea network
 * Implements the PasifikaTokenAdapter interface for integration with other Pasifika contracts
 */
contract LineaTokenAdapter is PasifikaTokenAdapter {
    address public immutable owner;
    
    // Token-related state variables
    mapping(address => bool) public supportedTokens;
    mapping(address => string) public tokenSymbols;
    
    event TokenAdded(address indexed token, string symbol);
    event TokenRemoved(address indexed token);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "LineaTokenAdapter: caller is not the owner");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Adds a token to the list of supported tokens
     * @param token Address of the token to add (address(0) represents native ETH)
     * @param symbol Symbol of the token
     */
    function addToken(address token, string memory symbol) external onlyOwner {
        require(bytes(symbol).length > 0, "LineaTokenAdapter: symbol cannot be empty");
        
        supportedTokens[token] = true;
        tokenSymbols[token] = symbol;
        
        emit TokenAdded(token, symbol);
    }
    
    /**
     * @dev Removes a token from the list of supported tokens
     * @param token Address of the token to remove
     */
    function removeToken(address token) external onlyOwner {
        require(supportedTokens[token], "LineaTokenAdapter: token not supported");
        
        supportedTokens[token] = false;
        delete tokenSymbols[token];
        
        emit TokenRemoved(token);
    }
    
    /**
     * @dev Transfers tokens from the sender to the recipient
     * @param token Address of the token to transfer
     * @param recipient Address of the recipient
     * @param amount Amount of tokens to transfer
     * @return success Whether the transfer was successful
     */
    function transferToken(address token, address recipient, uint256 amount) 
        external 
        override 
        returns (bool success) 
    {
        require(supportedTokens[token], "LineaTokenAdapter: token not supported");
        
        // For native ETH transfers on Linea
        if (token == address(0)) {
            (success, ) = recipient.call{value: amount}("");
            require(success, "LineaTokenAdapter: ETH transfer failed");
            return success;
        }
        
        // For ERC20 tokens
        (bool callSuccess, bytes memory data) = token.call(
            abi.encodeWithSelector(
                bytes4(keccak256("transferFrom(address,address,uint256)")),
                msg.sender,
                recipient,
                amount
            )
        );
        
        require(callSuccess && (data.length == 0 || abi.decode(data, (bool))), 
            "LineaTokenAdapter: ERC20 transferFrom failed");
        
        return true;
    }
    
    /**
     * @dev Checks if a token is supported
     * @param token Address of the token to check
     * @return Whether the token is supported
     */
    function isTokenSupported(address token) external view override returns (bool) {
        return supportedTokens[token];
    }
    
    /**
     * @dev Gets the symbol of a token
     * @param token Address of the token
     * @return The symbol of the token
     */
    function getTokenSymbol(address token) external view override returns (string memory) {
        require(supportedTokens[token], "LineaTokenAdapter: token not supported");
        return tokenSymbols[token];
    }
    
    /**
     * @dev Allows the contract to receive ETH
     */
    receive() external payable {}
}
