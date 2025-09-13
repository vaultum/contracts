// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SmartAccount} from "../../src/SmartAccount.sol";
import {SessionKeyValidator} from "../../src/validators/SessionKeyValidator.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UserOperation} from "../../src/interfaces/IEntryPoint.sol";

contract SessionKeyValidatorTest is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    SmartAccount public account;
    SessionKeyValidator public validator;
    
    address owner = address(0x1);
    address sessionKey;
    uint256 sessionKeyPrivateKey = 0x12345;
    
    address entryPoint = address(0x5555);

    function setUp() public {
        // Create session key from private key
        sessionKey = vm.addr(sessionKeyPrivateKey);
        
        // Deploy smart account
        account = new SmartAccount(owner);
        
        // Deploy validator with account address
        validator = new SessionKeyValidator(address(account));
        
        // Set entry point and add validator
        vm.startPrank(owner);
        account.setEntryPoint(entryPoint);
        account.addValidator(address(validator));
        vm.stopPrank();
    }

    function testGrantSessionKey() public {
        // Grant session key with 1 day expiry
        uint64 expiry = uint64(block.timestamp + 1 days);
        
        vm.prank(address(account));
        validator.grant(sessionKey, expiry);
        
        // Check key is valid
        assertTrue(validator.sessionExpiry(sessionKey) > block.timestamp);
        assertEq(validator.sessionExpiry(sessionKey), expiry);
    }

    function testGrantSessionKeyFailsIfNotAccount() public {
        uint64 expiry = uint64(block.timestamp + 1 days);
        
        vm.prank(owner);
        vm.expectRevert(bytes("not account"));
        validator.grant(sessionKey, expiry);
    }

    function testGrantSessionKeyFailsWithPastExpiry() public {
        uint64 expiry = uint64(block.timestamp - 1);
        
        vm.prank(address(account));
        vm.expectRevert(bytes("past expiry"));
        validator.grant(sessionKey, expiry);
    }

    function testValidateWithSessionKey() public {
        // Grant session key
        uint64 expiry = uint64(block.timestamp + 1 days);
        vm.prank(address(account));
        validator.grant(sessionKey, expiry);
        
        // Create a user op hash
        bytes32 userOpHash = keccak256("test user operation");
        
        // Sign with session key
        bytes32 ethSignedHash = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionKeyPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Validate should pass
        assertTrue(validator.isValidUserOp(signature, userOpHash));
    }

    function testValidateFailsWithInvalidSignature() public {
        // Grant session key
        uint64 expiry = uint64(block.timestamp + 1 days);
        vm.prank(address(account));
        validator.grant(sessionKey, expiry);
        
        // Create a user op hash
        bytes32 userOpHash = keccak256("test user operation");
        
        // Sign with different key
        uint256 wrongKeyPrivate = 0x99999;
        bytes32 ethSignedHash = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKeyPrivate, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Validate should fail
        assertFalse(validator.isValidUserOp(signature, userOpHash));
    }

    function testValidateFailsAfterRevoke() public {
        // Grant session key
        uint64 expiry = uint64(block.timestamp + 1 days);
        vm.prank(address(account));
        validator.grant(sessionKey, expiry);
        
        // Revoke key
        vm.prank(address(account));
        validator.revoke(sessionKey);
        
        // Check key is no longer valid
        assertEq(validator.sessionExpiry(sessionKey), 0);
        assertEq(validator.sessionExpiry(sessionKey), 0);
        
        // Create and sign user op
        bytes32 userOpHash = keccak256("test user operation");
        bytes32 ethSignedHash = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionKeyPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Validate should fail
        assertFalse(validator.isValidUserOp(signature, userOpHash));
    }

    function testValidateFailsAfterExpiry() public {
        // Grant session key with short expiry
        uint64 expiry = uint64(block.timestamp + 1 hours);
        vm.prank(address(account));
        validator.grant(sessionKey, expiry);
        
        // Fast forward past expiry
        vm.warp(block.timestamp + 2 hours);
        
        // Check key expiry is still set but has passed
        assertEq(validator.sessionExpiry(sessionKey), expiry);
        assertTrue(block.timestamp > expiry);
        
        // Create and sign user op
        bytes32 userOpHash = keccak256("test user operation");
        bytes32 ethSignedHash = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionKeyPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Validate should fail
        assertFalse(validator.isValidUserOp(signature, userOpHash));
    }

    function testValidateFailsWithMalformedSignature() public {
        // Grant session key
        uint64 expiry = uint64(block.timestamp + 1 days);
        vm.prank(address(account));
        validator.grant(sessionKey, expiry);
        
        bytes32 userOpHash = keccak256("test user operation");
        
        // Test with wrong length signature
        bytes memory shortSig = new bytes(64);
        assertFalse(validator.isValidUserOp(shortSig, userOpHash));
        
        bytes memory longSig = new bytes(66);
        assertFalse(validator.isValidUserOp(longSig, userOpHash));
    }

    function testEndToEndValidationWithSmartAccount() public {
        // Grant session key through smart account
        vm.prank(owner);
        account.execute(
            address(validator),
            0,
            abi.encodeWithSelector(SessionKeyValidator.grant.selector, sessionKey, uint64(block.timestamp + 1 days))
        );
        
        // Create user op
        bytes32 userOpHash = keccak256("test user operation");
        bytes32 ethSignedHash = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionKeyPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Create mock user operation
        UserOperation memory userOp = UserOperation({
            sender: address(account),
            nonce: 0,
            initCode: "",
            callData: "",
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 21000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: "",
            signature: signature
        });
        
        // Validate through smart account (should succeed)
        vm.prank(entryPoint);
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);
        assertEq(validationData, 0, "Validation should succeed");
    }

}
