// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IERC1271 - Standard Signature Validation Method for Contracts
 * @dev Interface for contracts to validate signatures
 * This enables smart contracts to act as signers for DApps
 */
interface IERC1271 {
    /**
     * @dev Should return whether the signature provided is valid for the provided data
     * @param hash Hash of the data to be signed
     * @param signature Signature byte array associated with hash
     * 
     * MUST return the bytes4 magic value 0x1626ba7e when function passes.
     * MUST NOT modify state (using view modifier)
     * MUST allow external calls
     * 
     * @return magicValue Either 0x1626ba7e (valid) or 0xffffffff (invalid)
     */
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4 magicValue);
}
