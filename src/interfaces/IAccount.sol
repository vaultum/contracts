// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {UserOperation} from "./IEntryPoint.sol";

/**
 * @dev Interface for ERC-4337 account contracts
 * @notice Accounts must implement this interface to be compatible with the EntryPoint
 */
interface IAccount {
    /**
     * @dev Validate a user operation
     * @param userOp The user operation to validate
     * @param userOpHash Hash of the user operation
     * @param missingFunds Missing funds that must be deposited to the EntryPoint
     * @return validationData Validation data (0 for success, 1 for signature failure, or packed validation data)
     * @notice This function must be called only by the EntryPoint
     * TODO: security review - ensure no state changes for gas estimation
     */
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingFunds
    ) external returns (uint256 validationData);
}
