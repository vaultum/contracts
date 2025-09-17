// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {SmartAccount} from "../src/SmartAccount.sol";
import {EntryPointMock} from "./mocks/EntryPointMock.sol";
import {UserOperation} from "../src/interfaces/IEntryPoint.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract ValidateUserOpTest is Test {
    using MessageHashUtils for bytes32;
    
    SmartAccount public account;
    EntryPointMock public entryPoint;
    
    address public owner;
    uint256 public ownerPrivateKey;
    address public notOwner; 
    uint256 public notOwnerPrivateKey;

    function setUp() public {
        // Setup owner with known private key
        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);
        
        // Setup non-owner with different key
        notOwnerPrivateKey = 0xB0B;
        notOwner = vm.addr(notOwnerPrivateKey);
        
        // Deploy contracts
        account = new SmartAccount(owner);
        entryPoint = new EntryPointMock();
        
        // Set entry point
        vm.prank(owner);
        account.setEntryPoint(address(entryPoint));
        
        // Fund account for potential missing funds
        vm.deal(address(account), 10 ether);
    }

    function _createUserOp(bytes memory signature) internal view returns (UserOperation memory) {
        return UserOperation({
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
    }

    function testOnlyEntryPointCanCallValidateUserOp() public {
        bytes32 userOpHash = keccak256("test");
        bytes memory signature = "";
        UserOperation memory userOp = _createUserOp(signature);
        
        // Try to call validateUserOp directly (not from entry point)
        vm.expectRevert("not entrypoint");
        account.validateUserOp(userOp, userOpHash, 0);
    }

    function testValidateUserOpWithValidSignature() public {
        // Create a user operation hash
        bytes32 userOpHash = keccak256("test_user_op");
        
        // Sign the hash with owner's private key
        bytes32 ethSignedHash = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        UserOperation memory userOp = _createUserOp(signature);
        
        // Call validateUserOp through entry point mock
        uint256 validationData = entryPoint.callValidate(account, userOp, userOpHash);
        
        // Should return 0 for valid signature
        assertEq(validationData, 0, "Validation should succeed with valid signature");
    }

    function testValidateUserOpWithInvalidSignature() public {
        // Create a user operation hash
        bytes32 userOpHash = keccak256("test_user_op");
        
        // Sign with wrong private key (not owner)
        bytes32 ethSignedHash = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(notOwnerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        UserOperation memory userOp = _createUserOp(signature);
        
        // Call validateUserOp through entry point mock
        uint256 validationData = entryPoint.callValidate(account, userOp, userOpHash);
        
        // Should return 1 for invalid signature
        assertEq(validationData, 1, "Validation should fail with invalid signature");
    }

    function testValidateUserOpWithMissingFunds() public {
        // Create valid signature
        bytes32 userOpHash = keccak256("test_user_op");
        bytes32 ethSignedHash = userOpHash.toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        UserOperation memory userOp = _createUserOp(signature);
        
        // Our security fix now requires zero missing funds
        uint256 missingFunds = 0.1 ether;
        
        // Should revert when missing funds > 0
        vm.expectRevert("Insufficient EntryPoint deposit");
        entryPoint.callValidateWithFunds{value: 0}(account, userOp, userOpHash, missingFunds);
        
        // Should succeed with zero missing funds
        uint256 validationData = entryPoint.callValidateWithFunds{value: 0}(account, userOp, userOpHash, 0);
        assertEq(validationData, 0, "Validation should succeed with zero missing funds");
    }

    function testValidateUserOpWithEmptySignature() public {
        bytes32 userOpHash = keccak256("test_user_op");
        bytes memory emptySignature = "";
        
        UserOperation memory userOp = _createUserOp(emptySignature);
        
        // Should fail with empty signature
        uint256 validationData = entryPoint.callValidate(account, userOp, userOpHash);
        assertEq(validationData, 1, "Validation should fail with empty signature");
    }

    function testValidateUserOpWithMalformedSignature() public {
        bytes32 userOpHash = keccak256("test_user_op");
        
        // Create malformed signature (wrong length)
        bytes memory malformedSignature = abi.encodePacked(bytes32(bytes("malformed")));
        
        UserOperation memory userOp = _createUserOp(malformedSignature);
        
        // Should fail with malformed signature
        uint256 validationData = entryPoint.callValidate(account, userOp, userOpHash);
        assertEq(validationData, 1, "Validation should fail with malformed signature");
    }

    function testValidateUserOpAfterOwnershipTransfer() public {
        // Transfer ownership to new owner
        uint256 newOwnerPrivateKey = 0xBEEF;
        address newOwner = vm.addr(newOwnerPrivateKey);
        
        vm.prank(owner);
        account.transferOwnership(newOwner);
        
        // Create user op hash
        bytes32 userOpHash = keccak256("test_after_transfer");
        bytes32 ethSignedHash = userOpHash.toEthSignedMessageHash();
        
        // Test old owner's signature fails
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedHash);
            bytes memory sig = abi.encodePacked(r, s, v);
            UserOperation memory userOp = _createUserOp(sig);
            uint256 result = entryPoint.callValidate(account, userOp, userOpHash);
            assertEq(result, 1, "Old owner signature should fail");
        }
        
        // Test new owner's signature succeeds
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(newOwnerPrivateKey, ethSignedHash);
            bytes memory sig = abi.encodePacked(r, s, v);
            UserOperation memory userOp = _createUserOp(sig);
            uint256 result = entryPoint.callValidate(account, userOp, userOpHash);
            assertEq(result, 0, "New owner signature should succeed");
        }
    }
}
