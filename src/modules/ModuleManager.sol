// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IModule} from "./IModule.sol";

error ModuleAlreadyAdded();
error ModuleNotFound();
error InvalidModule();
error BlockedByModule();

abstract contract ModuleManager {
    mapping(address => bool) internal _modules;
    address[] internal _moduleList;

    event ModuleAdded(address indexed module);
    event ModuleRemoved(address indexed module);

    function _addModule(address module) internal {
        if (module == address(0)) revert InvalidModule();
        if (_modules[module]) revert ModuleAlreadyAdded();
        _modules[module] = true;
        _moduleList.push(module);
        emit ModuleAdded(module);
    }

    function _removeModule(address module) internal {
        if (!_modules[module]) revert ModuleNotFound();
        delete _modules[module];
        for (uint256 i = 0; i < _moduleList.length; i++) {
            if (_moduleList[i] == module) {
                _moduleList[i] = _moduleList[_moduleList.length - 1];
                _moduleList.pop();
                break;
            }
        }
        emit ModuleRemoved(module);
    }

    function isModule(address module) public view returns (bool) {
        return _modules[module];
    }

    function getModules() public view returns (address[] memory) {
        return _moduleList;
    }
}