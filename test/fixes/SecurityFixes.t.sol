// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {SmartAccount} from "../../src/SmartAccount.sol";
import {SocialRecoveryModule} from "../../src/modules/SocialRecoveryModule.sol";
import {SessionKeyModule} from "../../src/modules/SessionKeyModule.sol";
import {SessionKeyValidator} from "../../src/validators/SessionKeyValidator.sol";
import {EntryPointMock} from "../mocks/EntryPointMock.sol";
import {UserOperation} from "../../src/interfaces/IEntryPoint.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract SecurityFixesTest is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    
    SmartAccount account;
    SocialRecoveryModule recoveryModule;
    SessionKeyModule sessionModule;
    SessionKeyValidator sessionValidator;
    EntryPointMock entryPoint;
    
    address owner = address(0x1);
    address guardian1 = address(0x11);
    address guardian2 = address(0x12);
    address guardian3 = address(0x13);
    address sessionKey;
    uint256 sessionKeyPrivate;
    
    // Helper function to compute UserOp hash
    function getUserOpHash(UserOperation memory userOp) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            userOp.sender,
            userOp.nonce,
            keccak256(userOp.initCode),
            keccak256(userOp.callData),
            userOp.callGasLimit,
            userOp.verificationGasLimit,
            userOp.preVerificationGas,
            userOp.maxFeePerGas,
            userOp.maxPriorityFeePerGas,
            keccak256(userOp.paymasterAndData)
        ));
    }
    
    function setUp() public {
        // Deploy EntryPoint mock
        entryPoint = new EntryPointMock();
        
        // Deploy account
        account = new SmartAccount(owner);
        vm.prank(owner);
        account.setEntryPoint(address(entryPoint));
        
        // Deploy and setup recovery module
        recoveryModule = new SocialRecoveryModule(address(account));
        vm.prank(owner);
        account.addModule(address(recoveryModule));
        vm.prank(owner);
        account.setRecoveryModule(address(recoveryModule), true);
        
        // Deploy and setup session key module
        sessionValidator = new SessionKeyValidator(address(account));
        sessionModule = new SessionKeyModule(address(account), address(sessionValidator));
        vm.prank(owner);
        account.addModule(address(sessionModule));
        vm.prank(owner);
        account.addValidator(address(sessionValidator));
        
        // Setup guardians - need to call through the account
        vm.startPrank(owner);
        account.execute(
            address(recoveryModule),
            0,
            abi.encodeWithSelector(recoveryModule.addGuardian.selector, guardian1)
        );
        account.execute(
            address(recoveryModule),
            0,
            abi.encodeWithSelector(recoveryModule.addGuardian.selector, guardian2)
        );
        account.execute(
            address(recoveryModule),
            0,
            abi.encodeWithSelector(recoveryModule.addGuardian.selector, guardian3)
        );
        account.execute(
            address(recoveryModule),
            0,
            abi.encodeWithSelector(recoveryModule.setThreshold.selector, 2)
        );
        vm.stopPrank();
        
        // Setup session key
        (sessionKey, sessionKeyPrivate) = makeAddrAndKey("sessionKey");
        vm.prank(owner);
        account.execute(
            address(sessionValidator),
            0,
            abi.encodeWithSelector(sessionValidator.grant.selector, sessionKey, uint64(block.timestamp + 1 hours))
        );
    }
    
    // ============ Test Fix 1: Session Key Selector Allowlist for UserOps ============
    
    function testSessionKeySelectorAllowlistEnforcedInUserOps() public {
        // Allow transfer selector for session key
        bytes4 transferSelector = bytes4(keccak256("transfer(address,uint256)"));
        vm.prank(owner);
        account.execute(
            address(sessionValidator),
            0,
            abi.encodeWithSelector(sessionValidator.allowSelector.selector, sessionKey, transferSelector, true)
        );
        
        // Create UserOp with transfer calldata
        bytes memory callData = abi.encodeWithSignature("transfer(address,uint256)", address(0x999), 100);
        
        UserOperation memory userOp = UserOperation({
            sender: address(account),
            nonce: 0,
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 21000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: "",
            signature: ""
        });
        
        bytes32 userOpHash = getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionKeyPrivate, userOpHash.toEthSignedMessageHash());
        userOp.signature = abi.encodePacked(r, s, v);
        
        // Should pass validation with allowed selector
        vm.prank(address(entryPoint));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);
        assertEq(validationData >> 160, 0, "Should validate with allowed selector");
    }
    
    function testSessionKeySelectorBlockedForDisallowedFunction() public {
        // Allow only transfer, not approve
        bytes4 transferSelector = bytes4(keccak256("transfer(address,uint256)"));
        vm.prank(owner);
        account.execute(
            address(sessionValidator),
            0,
            abi.encodeWithSelector(sessionValidator.allowSelector.selector, sessionKey, transferSelector, true)
        );
        
        // Create UserOp with approve calldata (not allowed)
        bytes memory callData = abi.encodeWithSignature("approve(address,uint256)", address(0x999), 100);
        
        UserOperation memory userOp = UserOperation({
            sender: address(account),
            nonce: 0,
            initCode: "",
            callData: callData,
            callGasLimit: 100000,
            verificationGasLimit: 100000,
            preVerificationGas: 21000,
            maxFeePerGas: 1 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: "",
            signature: ""
        });
        
        bytes32 userOpHash = getUserOpHash(userOp);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionKeyPrivate, userOpHash.toEthSignedMessageHash());
        userOp.signature = abi.encodePacked(r, s, v);
        
        // Should fail validation with disallowed selector
        vm.prank(address(entryPoint));
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);
        assertEq(validationData, 1, "Should fail validation with disallowed selector");
    }
    
    // ============ Test Fix 2: Allow New Recovery After Execute ============
    
    function testCanInitiateNewRecoveryAfterExecutingPrevious() public {
        address newOwner1 = address(0x201);
        address newOwner2 = address(0x202);
        
        // First recovery
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(newOwner1);
        
        vm.prank(guardian2);
        recoveryModule.supportRecovery();
        
        // Wait for timelock
        vm.warp(block.timestamp + 48 hours + 1);
        
        // Execute first recovery
        recoveryModule.executeRecovery();
        assertEq(account.owner(), newOwner1, "First recovery should succeed");
        
        // Should be able to initiate new recovery after execution
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(newOwner2);
        
        vm.prank(guardian3);
        recoveryModule.supportRecovery();
        
        // Wait and execute second recovery
        vm.warp(block.timestamp + 48 hours + 1);
        recoveryModule.executeRecovery();
        assertEq(account.owner(), newOwner2, "Second recovery should succeed");
    }
    
    function testCannotInitiateRecoveryWhilePending() public {
        address newOwner1 = address(0x201);
        address newOwner2 = address(0x202);
        
        // First recovery
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(newOwner1);
        
        // Try to initiate another recovery while first is pending
        vm.prank(guardian2);
        vm.expectRevert("Recovery pending");
        recoveryModule.initiateRecovery(newOwner2);
    }
    
    // ============ Test Fix 3: Block Guardian Activation During Active Recovery ============
    
    function testCannotActivateGuardianDuringActiveRecovery() public {
        address newGuardian = address(0x99);
        
        // Propose a new guardian
        vm.prank(owner);
        account.execute(
            address(recoveryModule),
            0,
            abi.encodeWithSelector(recoveryModule.proposeGuardian.selector, newGuardian)
        );
        
        // Start a recovery
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(address(0x500));
        
        // Fast forward past guardian delay
        vm.warp(block.timestamp + 3 days + 1);
        
        // Try to activate guardian during active recovery
        vm.expectRevert("Recovery active");
        recoveryModule.activateGuardian(newGuardian);
    }
    
    function testCanActivateGuardianAfterRecoveryCancelled() public {
        address newGuardian = address(0x99);
        
        // Propose a new guardian
        vm.prank(owner);
        account.execute(
            address(recoveryModule),
            0,
            abi.encodeWithSelector(recoveryModule.proposeGuardian.selector, newGuardian)
        );
        
        // Start and cancel a recovery
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(address(0x500));
        
        vm.prank(owner);
        account.execute(
            address(recoveryModule),
            0,
            abi.encodeWithSelector(recoveryModule.cancelRecovery.selector)
        );
        
        // Fast forward past guardian delay
        vm.warp(block.timestamp + 3 days + 1);
        
        // Should be able to activate after cancellation
        recoveryModule.activateGuardian(newGuardian);
        
        (bool isActive, , , ) = recoveryModule.guardians(newGuardian);
        assertTrue(isActive, "Guardian should be activated");
    }
    
    function testCanActivateGuardianAfterRecoveryExecuted() public {
        address newGuardian = address(0x99);
        address newOwner = address(0x500);
        
        // Execute a recovery first
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(newOwner);
        
        vm.prank(guardian2);
        recoveryModule.supportRecovery();
        
        vm.warp(block.timestamp + 48 hours + 1);
        recoveryModule.executeRecovery();
        
        // Now propose and activate a new guardian
        vm.prank(newOwner); // New owner proposes
        account.execute(
            address(recoveryModule),
            0,
            abi.encodeWithSelector(recoveryModule.proposeGuardian.selector, newGuardian)
        );
        
        vm.warp(block.timestamp + 3 days + 1);
        recoveryModule.activateGuardian(newGuardian);
        
        (bool isActive, , , ) = recoveryModule.guardians(newGuardian);
        assertTrue(isActive, "Guardian should be activated after recovery");
    }
}
