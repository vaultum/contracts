// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title ModuleManagerOptimized
 * @notice Gas-optimized module management using EnumerableSet
 * M-1 FIX: O(1) operations instead of O(n) array searches
 */
abstract contract ModuleManagerOptimized {
    using EnumerableSet for EnumerableSet.AddressSet;
    
    EnumerableSet.AddressSet private _modules;
    
    event ModuleAdded(address indexed module);
    event ModuleRemoved(address indexed module);
    
    error ModuleAlreadyAdded();
    error ModuleNotFound();
    
    function _addModule(address module) internal {
        require(module != address(0), "Invalid module");
        if (!_modules.add(module)) {
            revert ModuleAlreadyAdded();
        }
        emit ModuleAdded(module);
    }
    
    function _removeModule(address module) internal {
        if (!_modules.remove(module)) {
            revert ModuleNotFound();
        }
        emit ModuleRemoved(module);
    }
    
    function getModules() public view returns (address[] memory) {
        return _modules.values();
    }
    
    function isModule(address module) public view returns (bool) {
        return _modules.contains(module);
    }
    
    function getModuleCount() public view returns (uint256) {
        return _modules.length();
    }
    
    // For iteration in execute function
    function getModuleAt(uint256 index) public view returns (address) {
        return _modules.at(index);
    }
}
