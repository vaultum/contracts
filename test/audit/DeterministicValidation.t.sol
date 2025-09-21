// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {SmartAccount, ISessionKeyExpiry} from "../../src/SmartAccount.sol";
import {SessionKeyValidator} from "../../src/validators/SessionKeyValidator.sol";
import {UserOperation, IEntryPoint} from "../../src/interfaces/IEntryPoint.sol";

/**
 * @title AUDITOR REQUIRED: Deterministic Validation Tests
 * @notice Tests that validation is deterministic and packs time bounds correctly
 */
contract DeterministicValidationTest is Test {
    SmartAccount public account;
    SessionKeyValidator public validator;
    IEntryPoint public entryPoint;
    
    address public owner = makeAddr("owner");
    address public sessionKey = makeAddr("sessionKey");
    uint256 public sessionKeyPrivate = 0xBEEF;

    function setUp() public {
        account = new SmartAccount(owner);
        validator = new SessionKeyValidator(address(account));
        entryPoint = IEntryPoint(makeAddr("entryPoint"));
        sessionKey = vm.addr(sessionKeyPrivate);
        
        vm.startPrank(owner);
        account.setEntryPoint(address(entryPoint));
        account.addValidator(address(validator));
        vm.stopPrank();
        
        // Setup session key
        vm.prank(address(account));
        validator.grant(sessionKey, uint64(block.timestamp + 1 days));
        
        vm.prank(address(account));
        validator.allowSelector(sessionKey, bytes4(keccak256("executeWithSessionKey(address,address,uint256,bytes,uint256)")), true);
    }

    function test_SessionKeyExpiry_PackedInValidationData() public {
        // Create a UserOperation
        UserOperation memory userOp = UserOperation({
            sender: address(account),
            nonce: 0,
            initCode: "",
            callData: abi.encodeWithSelector(
                bytes4(keccak256("executeWithSessionKey(address,address,uint256,bytes,uint256)")),
                sessionKey,
                makeAddr("target"),
                0.1 ether,
                "",
                uint256(block.timestamp / 1 days)
            ),
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 21000,
            maxFeePerGas: 1e9,
            maxPriorityFeePerGas: 1e9,
            paymasterAndData: "",
            signature: "" // Will be set below
        });
        
        // Sign the UserOp with session key (proper ERC-4337 hash)
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionKeyPrivate, ethSignedHash);
        userOp.signature = abi.encodePacked(r, s, v);
        
        // Call validateUserOp and check that validUntil is packed
        vm.prank(address(entryPoint));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);
        
        // Extract validUntil from packed validation data
        uint48 packedValidUntil = uint48(validationData >> 160);
        
        // Should match session key expiry
        uint64 expectedExpiry = validator.sessionExpiry(sessionKey);
        assertEq(uint256(packedValidUntil), uint256(expectedExpiry), "validUntil should be packed from session expiry");
    }

    function test_Validation_NoTimestampReads() public {
        // Test that isValidUserOp is purely deterministic
        bytes32 userOpHash = keccak256("test");
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionKeyPrivate, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // Call should be deterministic regardless of block.timestamp
        bool result1 = validator.isValidUserOp(signature, userOpHash);
        
        // Advance time
        vm.warp(block.timestamp + 3600);
        
        // Result should be identical (deterministic)
        bool result2 = validator.isValidUserOp(signature, userOpHash);
        assertEq(result1, result2, "isValidUserOp should be deterministic");
        
        // Both should be true (session key is registered)
        assertTrue(result1, "Session key should be valid");
        assertTrue(result2, "Session key should remain valid");
    }

    function test_SimVsInclusion_NoDrift_WithExpiry() public {
        // Setup UserOp that could cross time boundary
        UserOperation memory userOp = UserOperation({
            sender: address(account),
            nonce: 0,
            initCode: "",
            callData: abi.encodeWithSelector(
                bytes4(keccak256("executeWithSessionKey(address,address,uint256,bytes,uint256)")),
                sessionKey,
                makeAddr("target"),
                0.1 ether,
                "",
                uint256(block.timestamp / 1 days)
            ),
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 21000,
            maxFeePerGas: 1e9,
            maxPriorityFeePerGas: 1e9,
            paymasterAndData: "",
            signature: ""
        });
        
        // Sign UserOp  
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionKeyPrivate, ethSignedHash);
        userOp.signature = abi.encodePacked(r, s, v);
        
        // Simulate validation at current time
        vm.prank(address(entryPoint));
        uint256 validationData1 = account.validateUserOp(userOp, userOpHash, 0);
        
        // "Include" transaction at different time (simulate sim vs inclusion)
        vm.warp(block.timestamp + 3600); // 1 hour later
        
        vm.prank(address(entryPoint));
        uint256 validationData2 = account.validateUserOp(userOp, userOpHash, 0);
        
        // Results must be identical (deterministic)
        assertEq(validationData1, validationData2, "Validation must be deterministic");
    }

    function test_ConcurrentSpending_Protection_Regression() public {
        // Verify the concurrent protection still works with deterministic validation
        vm.prank(address(account));
        validator.setSpendingCap(sessionKey, 1 ether);
        
        uint48 currentTime = uint48(block.timestamp);
        
        // First operation consumes 0.8 ETH
        vm.prank(address(account));
        validator.consumeOrRevert(sessionKey, 0.8 ether, currentTime);
        
        // Verify first consumption
        (, uint256 spent,) = validator.getSpendingStatus(sessionKey, currentTime);
        assertEq(spent, 0.8 ether);
        
        // Second operation tries to consume 0.8 ETH - should fail
        vm.expectRevert("Daily cap exceeded");
        vm.prank(address(account));
        validator.consumeOrRevert(sessionKey, 0.8 ether, currentTime);
        
        // Only first operation should have succeeded
        (, spent,) = validator.getSpendingStatus(sessionKey, currentTime);
        assertEq(spent, 0.8 ether);
    }

    function test_Events_CapExceeded_And_CapConsumed() public {
        vm.prank(address(account));
        validator.setSpendingCap(sessionKey, 1 ether);
        
        uint48 currentTime = uint48(block.timestamp);
        
        // Test CapConsumed event
        vm.expectEmit(true, false, false, true);
        emit CapConsumed(sessionKey, 0.5 ether, 0.5 ether);
        
        vm.prank(address(account));
        validator.consumeOrRevert(sessionKey, 0.5 ether, currentTime);
        
        // Test CapExceeded event
        vm.expectEmit(true, false, false, true);
        emit CapExceeded(sessionKey, 0.8 ether, 1 ether);
        
        vm.expectRevert("Daily cap exceeded");
        vm.prank(address(account));
        validator.consumeOrRevert(sessionKey, 0.8 ether, currentTime); // 0.5 + 0.8 > 1.0
    }

    event CapConsumed(address indexed key, uint256 amount, uint256 newTotal);
    event CapExceeded(address indexed key, uint256 attempted, uint256 cap);
}
