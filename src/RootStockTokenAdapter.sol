// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {PasifikaTokenAdapter} from "./PasifikaTokenAdapter.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title RootStockTokenAdapter
 * @dev Adapter for handling RIF tokens on RootStock network
 * Implements the PasifikaTokenAdapter interface for integration with other Pasifika contracts
 */
contract RootStockTokenAdapter is PasifikaTokenAdapter, AccessControl {
    using Address for address payable;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    // RIF token address
    address public immutable rifToken;
    
    // Token-related state variables
    mapping(address => bool) public supportedTokens;
    mapping(address => string) public tokenSymbols;
    
    event TokenAdded(address indexed token, string symbol);
    event TokenRemoved(address indexed token);
    
    constructor(address _rifToken, address admin) {
        require(_rifToken != address(0), "RootStockTokenAdapter: RIF token address cannot be zero");
        
        rifToken = _rifToken;
        
        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        
        // Add RIF token by default
        supportedTokens[_rifToken] = true;
        tokenSymbols[_rifToken] = "RIF";
        emit TokenAdded(_rifToken, "RIF");
        
        // Also support native RBTC
        supportedTokens[address(0)] = true;
        tokenSymbols[address(0)] = "RBTC";
        emit TokenAdded(address(0), "RBTC");
    }
    
    /**
     * @dev Adds a token to the list of supported tokens
     * @param token Address of the token to add
     * @param symbol Symbol of the token
     */
    function addToken(address token, string memory symbol) external onlyRole(ADMIN_ROLE) {
        require(bytes(symbol).length > 0, "RootStockTokenAdapter: symbol cannot be empty");
        
        supportedTokens[token] = true;
        tokenSymbols[token] = symbol;
        
        emit TokenAdded(token, symbol);
    }
    
    /**
     * @dev Removes a token from the list of supported tokens
     * @param token Address of the token to remove
     */
    function removeToken(address token) external onlyRole(ADMIN_ROLE) {
        require(supportedTokens[token], "RootStockTokenAdapter: token not supported");
        require(token != rifToken, "RootStockTokenAdapter: Cannot remove RIF token");
        
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
        require(supportedTokens[token], "RootStockTokenAdapter: token not supported");
        
        // For native RBTC transfers
        if (token == address(0)) {
            (success, ) = recipient.call{value: amount}("");
            require(success, "RootStockTokenAdapter: RBTC transfer failed");
            return success;
        }
        
        // For ERC20 tokens including RIF
        (bool callSuccess, bytes memory data) = token.call(
            abi.encodeWithSelector(
                bytes4(keccak256("transferFrom(address,address,uint256)")),
                msg.sender,
                recipient,
                amount
            )
        );
        
        require(callSuccess && (data.length == 0 || abi.decode(data, (bool))), 
            "RootStockTokenAdapter: ERC20 transferFrom failed");
        
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
        require(supportedTokens[token], "RootStockTokenAdapter: token not supported");
        return tokenSymbols[token];
    }
    
    /**
     * @dev Allows the contract to receive RBTC
     */
    receive() external payable {}
}
