// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IModule} from "./IModule.sol";
import {SessionKeyValidator} from "../validators/SessionKeyValidator.sol";

contract SessionKeyModule is IModule {
    address public immutable account;
    SessionKeyValidator public immutable validator;

    constructor(address _account, address _validator) {
        require(_account != address(0) && _validator != address(0), "zero");
        account = _account;
        validator = SessionKeyValidator(_validator);
    }

    function preExecute(address caller, address target, uint256, bytes calldata data) external override returns (bool) {
        // First check if this is a session key (has expiry)
        uint64 exp = validator.sessionExpiry(caller);
        
        // If not a session key (exp == 0), allow everything (owner/entrypoint can execute anything)
        if (exp == 0) return true;
        
        // For session keys, check expiry
        if (exp <= block.timestamp) return false;
        
        // H-1 FIX: Prevent session keys from calling the account itself
        // This prevents bypass of selector restrictions via recursive calls
        if (target == account) return false;
        
        // Check selector allowlist for session keys
        if (data.length < 4) return false;
        bytes4 sel;
        assembly {
            sel := calldataload(data.offset) // first 4 bytes when cast to bytes4
        }
        return validator.selectorAllowed(caller, sel);
    }

    function postExecute(address, address, uint256, bytes calldata, bytes calldata) external override returns (bool) {
        return true;
    }
}