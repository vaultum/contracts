// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @dev User operation struct for ERC-4337 account abstraction
 */
struct UserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    uint256 callGasLimit;
    uint256 verificationGasLimit;
    uint256 preVerificationGas;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
    bytes paymasterAndData;
    bytes signature;
}

/**
 * @dev Interface for the ERC-4337 EntryPoint contract
 */
interface IEntryPoint {
    /**
     * @dev Execute a batch of UserOperations
     */
    function handleOps(UserOperation[] calldata ops, address payable beneficiary) external;
    
    /**
     * @dev Simulate a UserOperation validation
     */
    function simulateValidation(UserOperation calldata userOp) external;
    
    /**
     * @dev Get the nonce for a sender account
     */
    function getNonce(address sender, uint192 key) external view returns (uint256 nonce);
}
