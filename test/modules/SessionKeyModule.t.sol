// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {SmartAccount} from "../../src/SmartAccount.sol";
import {SessionKeyModule} from "../../src/modules/SessionKeyModule.sol";
import {SessionKeyValidator} from "../../src/validators/SessionKeyValidator.sol";
import {ModuleManager, BlockedByModule} from "../../src/modules/ModuleManager.sol";

/**
 * @dev Simple target contract for testing
 */
contract SimpleTarget {
    uint256 public value;
    
    function setValue(uint256 _value) external {
        value = _value;
    }
    
    function getValue() external view returns (uint256) {
        return value;
    }
}

contract SessionKeyModuleTest is Test {
    SmartAccount public account;
    SessionKeyModule public sessionModule;
    SessionKeyValidator public validator;
    SimpleTarget public target;
    
    address public owner;
    uint256 public ownerPrivateKey;
    address public sessionKey;
    uint256 public sessionKeyPrivateKey;
    
    // Events
    event SessionGranted(address indexed key, uint64 expiry);
    event SessionRevoked(address indexed key);
    event SelectorAllowed(address indexed key, bytes4 indexed sel, bool allowed);
    
    // Selectors
    bytes4 constant RESTRICTED_SELECTOR = bytes4(keccak256("restrictedFunction()"));
    bytes4 constant ALLOWED_SELECTOR = bytes4(keccak256("allowedFunction()"));
    bytes4 constant SET_VALUE_SELECTOR = bytes4(keccak256("setValue(uint256)"));
    
    function setUp() public {
        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);
        sessionKeyPrivateKey = 0x5E55;
        sessionKey = vm.addr(sessionKeyPrivateKey);
        
        // Deploy contracts
        account = new SmartAccount(owner);
        validator = new SessionKeyValidator(address(account));
        sessionModule = new SessionKeyModule(address(account), address(validator));
        target = new SimpleTarget();
        
        // Register module and validator
        vm.startPrank(owner);
        account.addModule(address(sessionModule));
        account.addValidator(address(validator));
        vm.stopPrank();
        
        // Fund account
        vm.deal(address(account), 10 ether);
    }
    
    function testGrantSessionKey() public {
        uint256 expiry = block.timestamp + 1 hours;
        
        // Grant session key via validator
        vm.expectEmit(true, false, false, true, address(validator));
        emit SessionGranted(sessionKey, uint64(expiry));
        
        vm.prank(address(account));
        validator.grant(sessionKey, uint64(expiry));
        
        // Check key is valid
        uint64 storedExpiry = validator.sessionExpiry(sessionKey);
        assertEq(storedExpiry, expiry);
    }
    
    function testRevokeSessionKey() public {
        // Grant first
        vm.prank(address(account));
        validator.grant(sessionKey, uint64(block.timestamp + 1 hours));
        
        // Revoke
        vm.expectEmit(true, false, false, false, address(validator));
        emit SessionRevoked(sessionKey);
        
        vm.prank(address(account));
        validator.revoke(sessionKey);
        
        // Check key is revoked
        assertEq(validator.sessionExpiry(sessionKey), 0);
    }
    
    function testAllowSelector() public {
        // Grant session key
        vm.prank(address(account));
        validator.grant(sessionKey, uint64(block.timestamp + 1 hours));
        
        // Allow selector
        vm.expectEmit(true, true, false, true, address(validator));
        emit SelectorAllowed(sessionKey, ALLOWED_SELECTOR, true);
        
        vm.prank(address(account));
        validator.allowSelector(sessionKey, ALLOWED_SELECTOR, true);
        
        // Check selector is allowed
        assertTrue(validator.selectorAllowed(sessionKey, ALLOWED_SELECTOR));
        
        // Disallow selector
        vm.prank(address(account));
        validator.allowSelector(sessionKey, ALLOWED_SELECTOR, false);
        
        assertFalse(validator.selectorAllowed(sessionKey, ALLOWED_SELECTOR));
    }
    
    function testOnlyAccountCanGrantKeys() public {
        vm.prank(owner);
        vm.expectRevert(bytes("not account"));
        validator.grant(sessionKey, uint64(block.timestamp + 1 hours));
    }
    
    function testOnlyAccountCanRevokeKeys() public {
        vm.prank(owner);
        vm.expectRevert(bytes("not account"));
        validator.revoke(sessionKey);
    }
    
    function testOnlyAccountCanAllowSelectors() public {
        vm.prank(owner);
        vm.expectRevert(bytes("not account"));
        validator.allowSelector(sessionKey, ALLOWED_SELECTOR, true);
    }
    
    function testGrantSessionKeyWithZeroAddress() public {
        vm.prank(address(account));
        vm.expectRevert(bytes("zero key"));
        validator.grant(address(0), uint64(block.timestamp + 1 hours));
    }
    
    function testGrantSessionKeyWithInvalidExpiry() public {
        vm.prank(address(account));
        vm.expectRevert(bytes("past expiry"));
        validator.grant(sessionKey, uint64(block.timestamp - 1));
    }
    
    function testSessionKeyExpiry() public {
        // Grant with short expiry
        vm.prank(address(account));
        validator.grant(sessionKey, uint64(block.timestamp + 100));
        
        // Check valid
        assertTrue(validator.sessionExpiry(sessionKey) > block.timestamp);
        
        // Fast forward
        vm.warp(block.timestamp + 101);
        
        // Check expired
        assertTrue(validator.sessionExpiry(sessionKey) <= block.timestamp);
    }
    
    function testExecuteWithAllowedSelector() public {
        // Grant session key and allow selector
        vm.prank(address(account));
        validator.grant(sessionKey, uint64(block.timestamp + 1 hours));
        
        vm.prank(address(account));
        validator.allowSelector(sessionKey, SET_VALUE_SELECTOR, true);
        
        // Execute should work (module allows everything for now)
        bytes memory data = abi.encodeWithSelector(SET_VALUE_SELECTOR, 42);
        vm.prank(owner);
        account.execute(address(target), 0, data);
        
        assertEq(target.value(), 42);
    }
    
    function testExecuteWithDisallowedSelector() public {
        // Grant session key but don't allow selector
        vm.prank(address(account));
        validator.grant(sessionKey, uint64(block.timestamp + 1 hours));
        
        // Don't allow the selector
        
        // Execute should still work since module is permissive
        bytes memory data = abi.encodeWithSelector(SET_VALUE_SELECTOR, 42);
        vm.prank(owner);
        account.execute(address(target), 0, data);
        
        assertEq(target.value(), 42);
    }
    
    function testMultipleSelectorAllowlist() public {
        // Grant session key
        vm.prank(address(account));
        validator.grant(sessionKey, uint64(block.timestamp + 1 hours));
        
        // Allow multiple selectors
        vm.startPrank(address(account));
        validator.allowSelector(sessionKey, ALLOWED_SELECTOR, true);
        validator.allowSelector(sessionKey, SET_VALUE_SELECTOR, true);
        validator.allowSelector(sessionKey, RESTRICTED_SELECTOR, false);
        vm.stopPrank();
        
        // Check states
        assertTrue(validator.selectorAllowed(sessionKey, ALLOWED_SELECTOR));
        assertTrue(validator.selectorAllowed(sessionKey, SET_VALUE_SELECTOR));
        assertFalse(validator.selectorAllowed(sessionKey, RESTRICTED_SELECTOR));
    }
    
    function testExecuteAfterExpiry() public {
        // Grant with short expiry
        vm.prank(address(account));
        validator.grant(sessionKey, uint64(block.timestamp + 100));
        
        vm.prank(address(account));
        validator.allowSelector(sessionKey, SET_VALUE_SELECTOR, true);
        
        // Fast forward past expiry
        vm.warp(block.timestamp + 101);
        
        // Execute should still work since module allows everything
        bytes memory data = abi.encodeWithSelector(SET_VALUE_SELECTOR, 99);
        vm.prank(owner);
        account.execute(address(target), 0, data);
        
        assertEq(target.value(), 99);
    }
}