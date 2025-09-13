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

    function preExecute(address caller, address, uint256, bytes calldata data) external override returns (bool) {
        uint64 exp = validator.sessionExpiry(caller);
        if (exp == 0 || exp <= block.timestamp) return true;
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