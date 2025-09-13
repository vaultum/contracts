// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ISignatureValidator {
    function isValidUserOp(bytes calldata userOpSignature, bytes32 userOpHash) external view returns (bool);
}