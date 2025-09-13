// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {SmartAccount} from "../../src/SmartAccount.sol";
import {IModule} from "../../src/modules/IModule.sol";
import {ModuleManager, ModuleAlreadyAdded, ModuleNotFound, InvalidModule, BlockedByModule} from "../../src/modules/ModuleManager.sol";

/**
 * @dev Mock module for testing
 */
contract MockModule is IModule {
    bool public shouldAllow = true;
    bool public preExecuteCalled;
    bool public postExecuteCalled;
    
    // Store last call parameters
    address public lastCaller;
    address public lastTarget;
    uint256 public lastValue;
    bytes public lastData;
    bytes public lastResult;
    
    function setAllowed(bool _allowed) external {
        shouldAllow = _allowed;
    }
    
    function preExecute(
        address caller,
        address target,
        uint256 value,
        bytes calldata data
    ) external override returns (bool) {
        preExecuteCalled = true;
        lastCaller = caller;
        lastTarget = target;
        lastValue = value;
        lastData = data;
        return shouldAllow;
    }
    
    function postExecute(
        address caller,
        address target,
        uint256 value,
        bytes calldata data,
        bytes calldata result
    ) external override returns (bool) {
        postExecuteCalled = true;
        lastCaller = caller;
        lastTarget = target;
        lastValue = value;
        lastData = data;
        lastResult = result;
        return true;
    }
    
    function resetState() external {
        preExecuteCalled = false;
        postExecuteCalled = false;
        lastCaller = address(0);
        lastTarget = address(0);
        lastValue = 0;
        lastData = "";
        lastResult = "";
    }
}

/**
 * @dev Simple target contract for testing
 */
contract TestTarget {
    uint256 public value;
    
    function setValue(uint256 _value) external {
        value = _value;
    }
    
    function getValue() external view returns (uint256) {
        return value;
    }
    
    receive() external payable {}
}

contract ModuleManagerTest is Test {
    SmartAccount public account;
    MockModule public module1;
    MockModule public module2;
    TestTarget public target;
    
    address public owner;
    uint256 public ownerPrivateKey;
    address public notOwner;
    
    // Events to test
    event ModuleAdded(address indexed module);
    event ModuleRemoved(address indexed module);
    
    function setUp() public {
        // Setup owner
        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);
        notOwner = address(0xB0B);
        
        // Deploy contracts
        account = new SmartAccount(owner);
        module1 = new MockModule();
        module2 = new MockModule();
        target = new TestTarget();
        
        // Fund account
        vm.deal(address(account), 10 ether);
    }
    
    function testAddModule() public {
        // Check module is not added initially
        assertFalse(account.isModule(address(module1)));
        assertEq(account.getModules().length, 0);
        
        // Add module
        vm.expectEmit(true, false, false, true, address(account));
        emit ModuleAdded(address(module1));
        
        vm.prank(owner);
        account.addModule(address(module1));
        
        // Check module is added
        assertTrue(account.isModule(address(module1)));
        address[] memory modules = account.getModules();
        assertEq(modules.length, 1);
        assertEq(modules[0], address(module1));
    }
    
    function testAddMultipleModules() public {
        vm.startPrank(owner);
        account.addModule(address(module1));
        account.addModule(address(module2));
        vm.stopPrank();
        
        address[] memory modules = account.getModules();
        assertEq(modules.length, 2);
        assertTrue(account.isModule(address(module1)));
        assertTrue(account.isModule(address(module2)));
    }
    
    function testCannotAddSameModuleTwice() public {
        vm.prank(owner);
        account.addModule(address(module1));
        
        vm.prank(owner);
        vm.expectRevert(ModuleAlreadyAdded.selector);
        account.addModule(address(module1));
    }
    
    function testCannotAddZeroAddressModule() public {
        vm.prank(owner);
        vm.expectRevert(InvalidModule.selector);
        account.addModule(address(0));
    }
    
    function testOnlyOwnerCanAddModule() public {
        vm.prank(notOwner);
        vm.expectRevert("not owner");
        account.addModule(address(module1));
    }
    
    function testRemoveModule() public {
        // Add module first
        vm.prank(owner);
        account.addModule(address(module1));
        
        // Remove module
        vm.expectEmit(true, false, false, true, address(account));
        emit ModuleRemoved(address(module1));
        
        vm.prank(owner);
        account.removeModule(address(module1));
        
        // Check module is removed
        assertFalse(account.isModule(address(module1)));
        assertEq(account.getModules().length, 0);
    }
    
    function testRemoveModuleFromMiddle() public {
        // Add three modules
        MockModule module3 = new MockModule();
        vm.startPrank(owner);
        account.addModule(address(module1));
        account.addModule(address(module2));
        account.addModule(address(module3));
        
        // Remove middle module
        account.removeModule(address(module2));
        vm.stopPrank();
        
        // Check correct module was removed
        assertTrue(account.isModule(address(module1)));
        assertFalse(account.isModule(address(module2)));
        assertTrue(account.isModule(address(module3)));
        
        address[] memory modules = account.getModules();
        assertEq(modules.length, 2);
        // Order might change due to swap-and-pop
        assertTrue(modules[0] == address(module1) || modules[0] == address(module3));
        assertTrue(modules[1] == address(module1) || modules[1] == address(module3));
    }
    
    function testCannotRemoveNonExistentModule() public {
        vm.prank(owner);
        vm.expectRevert(ModuleNotFound.selector);
        account.removeModule(address(module1));
    }
    
    function testOnlyOwnerCanRemoveModule() public {
        vm.prank(owner);
        account.addModule(address(module1));
        
        vm.prank(notOwner);
        vm.expectRevert("not owner");
        account.removeModule(address(module1));
    }
    
    function testPreExecuteHookAllows() public {
        // Add module
        vm.prank(owner);
        account.addModule(address(module1));
        
        // Execute should work when module allows
        bytes memory data = abi.encodeWithSelector(TestTarget.setValue.selector, 42);
        vm.prank(owner);
        account.execute(address(target), 0, data);
        
        // Check pre-hook was called
        assertTrue(module1.preExecuteCalled());
        assertEq(module1.lastTarget(), address(target));
        assertEq(module1.lastValue(), 0);
        assertEq(module1.lastData(), data);
        
        // Check execution succeeded
        assertEq(target.value(), 42);
    }
    
    function testPreExecuteHookBlocks() public {
        // Add module and set to block
        vm.prank(owner);
        account.addModule(address(module1));
        module1.setAllowed(false);
        
        // Execute should fail when module blocks
        bytes memory data = abi.encodeWithSelector(TestTarget.setValue.selector, 42);
        vm.prank(owner);
        vm.expectRevert(BlockedByModule.selector);
        account.execute(address(target), 0, data);
        
        // After revert, we can't check module state (it was reverted too)
        // But we can verify target state didn't change
        assertEq(target.value(), 0); // Value should not change
    }
    
    function testMultipleModulesAllAllow() public {
        // Add two modules
        vm.startPrank(owner);
        account.addModule(address(module1));
        account.addModule(address(module2));
        
        // Both allow
        bytes memory data = abi.encodeWithSelector(TestTarget.setValue.selector, 99);
        account.execute(address(target), 0, data);
        vm.stopPrank();
        
        // Check both pre-hooks were called
        assertTrue(module1.preExecuteCalled());
        assertTrue(module2.preExecuteCalled());
        
        // Check execution succeeded
        assertEq(target.value(), 99);
    }
    
    function testMultipleModulesOneBlocks() public {
        // Add two modules
        vm.startPrank(owner);
        account.addModule(address(module1));
        account.addModule(address(module2));
        vm.stopPrank();
        
        // Second module blocks
        module2.setAllowed(false);
        
        // Execute should fail
        bytes memory data = abi.encodeWithSelector(TestTarget.setValue.selector, 99);
        vm.prank(owner);
        vm.expectRevert(BlockedByModule.selector);
        account.execute(address(target), 0, data);
        
        // After revert, we can't check module state (it was reverted too)
        // But we can verify target state didn't change
        assertEq(target.value(), 0);
    }
    
    function testPostExecuteHookCalled() public {
        // Add module
        vm.prank(owner);
        account.addModule(address(module1));
        
        // Execute
        bytes memory data = abi.encodeWithSelector(TestTarget.getValue.selector);
        vm.prank(owner);
        bytes memory result = account.execute(address(target), 0, data);
        
        // Check post-hook was called
        assertTrue(module1.postExecuteCalled());
        assertEq(module1.lastTarget(), address(target));
        assertEq(module1.lastValue(), 0);
        assertEq(module1.lastData(), data);
        assertEq(module1.lastResult(), result);
    }
    
    function testPostExecuteWithValue() public {
        // Add module
        vm.prank(owner);
        account.addModule(address(module1));
        
        // Execute with ETH value
        uint256 sendValue = 1 ether;
        vm.prank(owner);
        account.execute(address(target), sendValue, "");
        
        // Check post-hook was called with correct value
        assertTrue(module1.postExecuteCalled());
        assertEq(module1.lastTarget(), address(target));
        assertEq(module1.lastValue(), sendValue);
        assertEq(address(target).balance, sendValue);
    }
}
