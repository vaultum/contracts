// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @dev Interface for pluggable signature validators in ERC-4337 accounts.
 * @notice Validators can implement custom signature verification logic.
 */
interface ISignatureValidator {
    /**
     * @dev Validates a user operation signature.
     * @param userOpSignature The signature bytes from the user operation.
     * @param userOpHash The hash of the user operation to validate.
     * @return bool True if the signature is valid, false otherwise.
     */
    function isValidUserOp(bytes calldata userOpSignature, bytes32 userOpHash) external view returns (bool);
}
