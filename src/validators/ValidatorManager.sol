// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ISignatureValidator} from "./ISignatureValidator.sol";

abstract contract ValidatorManager {
    mapping(address => bool) internal _validators;
    address[] internal _validatorList;

    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);

    function _addValidator(address validator) internal {
        require(validator != address(0), "zero validator");
        require(!_validators[validator], "already added");
        
        _validators[validator] = true;
        _validatorList.push(validator);
        
        emit ValidatorAdded(validator);
    }

    function _removeValidator(address validator) internal {
        require(_validators[validator], "not found");
        
        delete _validators[validator];
        
        // Remove from array
        for (uint256 i = 0; i < _validatorList.length; i++) {
            if (_validatorList[i] == validator) {
                _validatorList[i] = _validatorList[_validatorList.length - 1];
                _validatorList.pop();
                break;
            }
        }
        
        emit ValidatorRemoved(validator);
    }

    function isValidator(address validator) public view returns (bool) {
        return _validators[validator];
    }

    function getValidators() public view returns (address[] memory) {
        return _validatorList;
    }
}