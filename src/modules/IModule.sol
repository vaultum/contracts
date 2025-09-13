// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IModule {
    /// @notice Called before SmartAccount executes a target call
    /// @param caller original msg.sender to SmartAccount.execute
    /// @param target target contract to call
    /// @param value ETH value
    /// @param data calldata for target
    /// @return allow true to allow, false to block
    function preExecute(address caller, address target, uint256 value, bytes calldata data) external returns (bool);

    /// @notice Called after SmartAccount executes a target call
    /// @param caller original msg.sender to SmartAccount.execute
    /// @param target target contract called
    /// @param value ETH value
    /// @param data calldata sent to target
    /// @param result returndata from target call
    /// @return ok true if post hook succeeded
    function postExecute(
        address caller,
        address target,
        uint256 value,
        bytes calldata data,
        bytes calldata result
    ) external returns (bool);
}