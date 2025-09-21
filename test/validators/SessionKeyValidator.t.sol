// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SmartAccount} from "../../src/SmartAccount.sol";
import {EntryPointMock} from "../mocks/EntryPointMock.sol";
import {SessionKeyValidator} from "../../src/validators/SessionKeyValidator.sol";
import {UserOperation} from "../../src/interfaces/IEntryPoint.sol";

contract SessionKeyValidatorTest is Test {
    SmartAccount account;
    EntryPointMock entryPoint;
    SessionKeyValidator validator;
    
    uint256 ownerPrivateKey = 0xA11CE;
    address owner;
    
    uint256 sessionPrivateKey = 0xB0B;
    address sessionKey;
    
    function setUp() public {
        owner = vm.addr(ownerPrivateKey);
        sessionKey = vm.addr(sessionPrivateKey);
        
        // Deploy SmartAccount
        account = new SmartAccount(owner);
        
        // Deploy EntryPointMock
        entryPoint = new EntryPointMock();
        
        // Set entry point
        vm.prank(owner);
        account.setEntryPoint(address(entryPoint));
        
        // Deploy SessionKeyValidator bound to the account
        validator = new SessionKeyValidator(address(account));
        
        // Register validator on account
        vm.prank(owner);
        account.addValidator(address(validator));
        
        // Grant session key with 1 day expiry
        vm.prank(address(account));
        validator.grant(sessionKey, uint64(block.timestamp + 1 days));
    }
    
    function _createUserOp(bytes memory signature) internal view returns (UserOperation memory) {
        UserOperation memory op;
        op.sender = address(account);
        op.signature = signature;
        // Other fields can be left as default for these tests
        return op;
    }
    
    function _signUserOpHash(bytes32 opHash, uint256 privateKey) internal pure returns (bytes memory) {
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", opHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
    
    function testSessionKeySignatureAccepted() public {
        bytes32 opHash = keccak256("test-op-1");
        bytes memory signature = _signUserOpHash(opHash, sessionPrivateKey);
        UserOperation memory op = _createUserOp(signature);
        
        uint256 result = entryPoint.callValidate(account, op, opHash);
        // V2 Fix: Success is indicated by validationData != 1, not == 0 (due to time bounds)
        assertTrue(result != 1, "Session key signature should be accepted");
        // Verify that validUntil is properly set (should be the session expiry)
        uint256 validUntil = result >> 160;
        assertTrue(validUntil > block.timestamp, "Session should have valid expiry");
    }
    
    function testRevokedKeyFails() public {
        // Revoke the session key
        vm.prank(address(account));
        validator.revoke(sessionKey);
        
        bytes32 opHash = keccak256("test-op-2");
        bytes memory signature = _signUserOpHash(opHash, sessionPrivateKey);
        UserOperation memory op = _createUserOp(signature);
        
        uint256 result = entryPoint.callValidate(account, op, opHash);
        assertEq(result, 1, "Revoked key should fail validation");
    }
    
    function testExpiredKeyFails() public {
        // Move time forward past expiry
        vm.warp(block.timestamp + 2 days);
        
        bytes32 opHash = keccak256("test-op-3");
        bytes memory signature = _signUserOpHash(opHash, sessionPrivateKey);
        UserOperation memory op = _createUserOp(signature);
        
        uint256 result = entryPoint.callValidate(account, op, opHash);
        // V2 Fix: Check that validation failed properly
        // For expired keys, validation should still succeed but with past validUntil
        assertTrue(result != 1, "Signature should still be valid");
        uint256 validUntil = result >> 160;
        assertTrue(validUntil < block.timestamp, "Session should be expired");
    }
    
    function testOwnerSignatureStillValid() public {
        bytes32 opHash = keccak256("test-op-4");
        bytes memory signature = _signUserOpHash(opHash, ownerPrivateKey);
        UserOperation memory op = _createUserOp(signature);
        
        uint256 result = entryPoint.callValidate(account, op, opHash);
        assertEq(result, 0, "Owner signature should still be valid");
    }
    
    function testMissingFundsReceivedByEntryPoint() public {
        // Fund the account
        vm.deal(address(account), 1 ether);
        
        bytes32 opHash = keccak256("test-op-5");
        bytes memory signature = _signUserOpHash(opHash, ownerPrivateKey);
        UserOperation memory op = _createUserOp(signature);
        
        // Our security fix now requires zero missing funds
        // The account should maintain sufficient deposit in EntryPoint
        uint256 missingFunds = 0.1 ether;
        
        // Expect revert when missing funds > 0
        vm.expectRevert("Insufficient EntryPoint deposit");
        entryPoint.callValidateWithFunds{value: 0}(account, op, opHash, missingFunds);
        
        // Test with zero missing funds - should pass
        uint256 result = entryPoint.callValidateWithFunds{value: 0}(account, op, opHash, 0);
        assertEq(result, 0, "Validation should pass with zero missing funds");
    }
    
    function testMultipleValidators() public {
        // Deploy another validator
        SessionKeyValidator validator2 = new SessionKeyValidator(address(account));
        
        // Register second validator
        vm.prank(owner);
        account.addValidator(address(validator2));
        
        // Create another session key
        uint256 sessionKey2PrivateKey = 0xCAFE;
        address sessionKey2 = vm.addr(sessionKey2PrivateKey);
        
        // Grant on second validator
        vm.prank(address(account));
        validator2.grant(sessionKey2, uint64(block.timestamp + 1 days));
        
        // Test that second session key works
        bytes32 opHash = keccak256("test-op-6");
        bytes memory signature = _signUserOpHash(opHash, sessionKey2PrivateKey);
        UserOperation memory op = _createUserOp(signature);
        
        uint256 result = entryPoint.callValidate(account, op, opHash);
        // V2 Fix: Success is indicated by validationData != 1, not == 0
        assertTrue(result != 1, "Second validator's session key should work");
        uint256 validUntil = result >> 160;
        assertTrue(validUntil > block.timestamp, "Second session should have valid expiry");
    }
    
    function testRemoveValidator() public {
        // Remove the validator
        vm.prank(owner);
        account.removeValidator(address(validator));
        
        // Session key should no longer work
        bytes32 opHash = keccak256("test-op-7");
        bytes memory signature = _signUserOpHash(opHash, sessionPrivateKey);
        UserOperation memory op = _createUserOp(signature);
        
        uint256 result = entryPoint.callValidate(account, op, opHash);
        assertEq(result, 1, "Session key should fail after validator removal");
    }
    
    function testOnlyAccountCanGrant() public {
        address randomUser = address(0x1234);
        vm.prank(randomUser);
        vm.expectRevert("not account");
        validator.grant(randomUser, uint64(block.timestamp + 1 days));
    }
    
    function testOnlyAccountCanRevoke() public {
        address randomUser = address(0x1234);
        vm.prank(randomUser);
        vm.expectRevert("not account");
        validator.revoke(sessionKey);
    }
    
    function testCannotGrantZeroAddress() public {
        vm.prank(address(account));
        vm.expectRevert("zero key");
        validator.grant(address(0), uint64(block.timestamp + 1 days));
    }
    
    function testCannotGrantPastExpiry() public {
        vm.prank(address(account));
        vm.expectRevert("expiry too soon");
        validator.grant(sessionKey, uint64(block.timestamp + 30)); // Less than 60s buffer
    }
}