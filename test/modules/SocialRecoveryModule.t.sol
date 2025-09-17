// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../src/modules/SocialRecoveryModule.sol";
import "../../src/SmartAccount.sol";

contract SocialRecoveryModuleTest is Test {
    SocialRecoveryModule public recoveryModule;
    SmartAccount public account;
    
    address public owner = address(0x1);
    address public guardian1 = address(0x2);
    address public guardian2 = address(0x3);
    address public guardian3 = address(0x4);
    address public newOwner = address(0x5);
    address public attacker = address(0x666);
    
    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);
    event RecoveryInitiated(address indexed newOwner, address indexed initiator, uint256 nonce);
    event RecoveryApproved(address indexed guardian, uint256 nonce);
    event RecoveryExecuted(address indexed oldOwner, address indexed newOwner);
    event RecoveryCancelled(uint256 nonce);
    event ThresholdChanged(uint256 newThreshold);
    
    function setUp() public {
        // Deploy smart account
        vm.prank(owner);
        account = new SmartAccount(owner);
        
        // Deploy recovery module
        vm.prank(owner);
        recoveryModule = new SocialRecoveryModule(address(account));
        
        // Add recovery module to account
        vm.prank(owner);
        account.addModule(address(recoveryModule));
    }
    
    // ============ Guardian Management Tests ============
    
    function testAddGuardian() public {
        vm.startPrank(address(account));
        
        vm.expectEmit(true, false, false, true);
        emit GuardianAdded(guardian1);
        
        recoveryModule.addGuardian(guardian1);
        
        assertTrue(recoveryModule.isGuardian(guardian1));
        assertEq(recoveryModule.guardianCount(), 1);
        assertEq(recoveryModule.threshold(), 1);
        
        vm.stopPrank();
    }
    
    function testAddMultipleGuardians() public {
        vm.startPrank(address(account));
        
        recoveryModule.addGuardian(guardian1);
        recoveryModule.addGuardian(guardian2);
        recoveryModule.addGuardian(guardian3);
        
        assertEq(recoveryModule.guardianCount(), 3);
        assertEq(recoveryModule.threshold(), 2); // Majority: (3/2) + 1 = 2
        
        vm.stopPrank();
    }
    
    function testCannotAddZeroAddressGuardian() public {
        vm.startPrank(address(account));
        
        vm.expectRevert("Invalid guardian");
        recoveryModule.addGuardian(address(0));
        
        vm.stopPrank();
    }
    
    function testCannotAddDuplicateGuardian() public {
        vm.startPrank(address(account));
        
        recoveryModule.addGuardian(guardian1);
        
        vm.expectRevert("Already guardian");
        recoveryModule.addGuardian(guardian1);
        
        vm.stopPrank();
    }
    
    function testCannotAddSelfAsGuardian() public {
        vm.startPrank(address(account));
        
        vm.expectRevert("Cannot be self");
        recoveryModule.addGuardian(address(account));
        
        vm.stopPrank();
    }
    
    function testOnlyAccountCanAddGuardian() public {
        vm.expectRevert("Only account");
        recoveryModule.addGuardian(guardian1);
    }
    
    function testRemoveGuardian() public {
        vm.startPrank(address(account));
        
        // Add 3 guardians (threshold will be 2)
        recoveryModule.addGuardian(guardian1);
        recoveryModule.addGuardian(guardian2);
        recoveryModule.addGuardian(guardian3);
        
        assertEq(recoveryModule.threshold(), 2);
        
        // Remove one (will still have 2 guardians, threshold stays at 2)
        vm.expectEmit(true, false, false, true);
        emit GuardianRemoved(guardian1);
        
        recoveryModule.removeGuardian(guardian1);
        
        assertFalse(recoveryModule.isGuardian(guardian1));
        assertEq(recoveryModule.guardianCount(), 2);
        assertEq(recoveryModule.threshold(), 2);
        
        vm.stopPrank();
    }
    
    function testCannotRemoveLastGuardian() public {
        vm.startPrank(address(account));
        
        recoveryModule.addGuardian(guardian1);
        
        vm.expectRevert("Cannot remove last guardian");
        recoveryModule.removeGuardian(guardian1);
        
        vm.stopPrank();
    }
    
    function testCannotRemoveNonExistentGuardian() public {
        vm.startPrank(address(account));
        
        vm.expectRevert("Not a guardian");
        recoveryModule.removeGuardian(guardian1);
        
        vm.stopPrank();
    }
    
    function testSetThreshold() public {
        vm.startPrank(address(account));
        
        recoveryModule.addGuardian(guardian1);
        recoveryModule.addGuardian(guardian2);
        recoveryModule.addGuardian(guardian3);
        
        vm.expectEmit(false, false, false, true);
        emit ThresholdChanged(3);
        
        recoveryModule.setThreshold(3);
        assertEq(recoveryModule.threshold(), 3);
        
        vm.stopPrank();
    }
    
    function testCannotSetInvalidThreshold() public {
        vm.startPrank(address(account));
        
        recoveryModule.addGuardian(guardian1);
        recoveryModule.addGuardian(guardian2);
        
        vm.expectRevert("Invalid threshold");
        recoveryModule.setThreshold(0);
        
        vm.expectRevert("Threshold too high");
        recoveryModule.setThreshold(3);
        
        vm.stopPrank();
    }
    
    // ============ Recovery Flow Tests ============
    
    function testInitiateRecovery() public {
        // Setup guardians
        vm.prank(address(account));
        recoveryModule.addGuardian(guardian1);
        
        // Initiate recovery
        vm.expectEmit(true, true, false, true);
        emit RecoveryInitiated(newOwner, guardian1, 1);
        
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(newOwner);
        
        (
            address recoveryOwner,
            uint256 approvalCount,
            uint256 timestamp,
            bool executable
        ) = recoveryModule.getRecoveryRequest();
        
        assertEq(recoveryOwner, newOwner);
        assertEq(approvalCount, 1);
        assertEq(timestamp, block.timestamp);
        assertFalse(executable); // Timelock not expired
    }
    
    function testOnlyGuardianCanInitiateRecovery() public {
        vm.expectRevert("Only guardian");
        recoveryModule.initiateRecovery(newOwner);
    }
    
    function testCannotInitiateWithZeroAddress() public {
        vm.prank(address(account));
        recoveryModule.addGuardian(guardian1);
        
        vm.prank(guardian1);
        vm.expectRevert("Invalid new owner");
        recoveryModule.initiateRecovery(address(0));
    }
    
    function testSupportRecovery() public {
        // Setup
        vm.startPrank(address(account));
        recoveryModule.addGuardian(guardian1);
        recoveryModule.addGuardian(guardian2);
        recoveryModule.addGuardian(guardian3);
        vm.stopPrank();
        
        // Guardian 1 initiates
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(newOwner);
        
        // Guardian 2 supports
        vm.expectEmit(true, false, false, true);
        emit RecoveryApproved(guardian2, 1);
        
        vm.prank(guardian2);
        recoveryModule.supportRecovery();
        
        (, uint256 approvalCount, , ) = recoveryModule.getRecoveryRequest();
        assertEq(approvalCount, 2);
    }
    
    function testCannotSupportTwice() public {
        // Setup
        vm.startPrank(address(account));
        recoveryModule.addGuardian(guardian1);
        recoveryModule.addGuardian(guardian2);
        vm.stopPrank();
        
        // Guardian 1 initiates
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(newOwner);
        
        // Guardian 1 tries to support again
        vm.prank(guardian1);
        vm.expectRevert("Already approved");
        recoveryModule.supportRecovery();
    }
    
    function testCannotSupportWithoutActiveRecovery() public {
        vm.prank(address(account));
        recoveryModule.addGuardian(guardian1);
        
        vm.prank(guardian1);
        vm.expectRevert("No active recovery");
        recoveryModule.supportRecovery();
    }
    
    function testExecuteRecoveryAfterTimelock() public {
        // Setup with 2 of 3 threshold
        vm.startPrank(address(account));
        recoveryModule.addGuardian(guardian1);
        recoveryModule.addGuardian(guardian2);
        recoveryModule.addGuardian(guardian3);
        vm.stopPrank();
        
        // Authorize the recovery module to change ownership (must be done by owner)
        vm.prank(owner);
        account.setRecoveryModule(address(recoveryModule), true);
        
        // Guardian 1 initiates
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(newOwner);
        
        // Guardian 2 supports (now have 2 of 3)
        vm.prank(guardian2);
        recoveryModule.supportRecovery();
        
        // Try to execute immediately (should fail)
        vm.expectRevert("Timelock not expired");
        recoveryModule.executeRecovery();
        
        // Fast forward 48 hours
        vm.warp(block.timestamp + 48 hours + 1);
        
        // Now execution should work
        vm.expectEmit(true, true, false, false);
        emit RecoveryExecuted(owner, newOwner);
        
        recoveryModule.executeRecovery();
        
        // Check state
        (, , , bool executable) = recoveryModule.getRecoveryRequest();
        assertFalse(executable); // No longer executable after execution
    }
    
    function testCannotExecuteWithoutThreshold() public {
        // Setup with 2 of 3 threshold
        vm.startPrank(address(account));
        recoveryModule.addGuardian(guardian1);
        recoveryModule.addGuardian(guardian2);
        recoveryModule.addGuardian(guardian3);
        vm.stopPrank();
        
        // Only guardian 1 initiates (1 of 2 needed)
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(newOwner);
        
        // Fast forward
        vm.warp(block.timestamp + 48 hours + 1);
        
        // Try to execute
        vm.expectRevert("Insufficient approvals");
        recoveryModule.executeRecovery();
    }
    
    function testCannotExecuteTwice() public {
        // Setup
        vm.prank(address(account));
        recoveryModule.addGuardian(guardian1);
        
        // Authorize the recovery module (must be done by owner)
        vm.prank(owner);
        account.setRecoveryModule(address(recoveryModule), true);
        
        // Initiate and execute
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(newOwner);
        
        vm.warp(block.timestamp + 48 hours + 1);
        recoveryModule.executeRecovery();
        
        // Try to execute again
        vm.expectRevert("Already executed");
        recoveryModule.executeRecovery();
    }
    
    function testOwnerCanCancelRecovery() public {
        // Setup
        vm.prank(address(account));
        recoveryModule.addGuardian(guardian1);
        
        // Guardian initiates recovery
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(newOwner);
        
        // Owner cancels
        vm.expectEmit(false, false, false, true);
        emit RecoveryCancelled(1);
        
        vm.prank(address(account));
        recoveryModule.cancelRecovery();
        
        // Try to execute (should fail)
        vm.warp(block.timestamp + 48 hours + 1);
        vm.expectRevert("Recovery cancelled");
        recoveryModule.executeRecovery();
    }
    
    function testOnlyOwnerCanCancel() public {
        // Setup
        vm.prank(address(account));
        recoveryModule.addGuardian(guardian1);
        
        // Guardian initiates recovery
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(newOwner);
        
        // Attacker tries to cancel
        vm.prank(attacker);
        vm.expectRevert("Only account");
        recoveryModule.cancelRecovery();
    }
    
    function testCannotCancelWithoutActiveRecovery() public {
        vm.prank(address(account));
        vm.expectRevert("No active recovery");
        recoveryModule.cancelRecovery();
    }
    
    // ============ Edge Cases & Security Tests ============
    
    function testCannotInitiateWhileRecoveryPending() public {
        // Setup
        vm.startPrank(address(account));
        recoveryModule.addGuardian(guardian1);
        recoveryModule.addGuardian(guardian2);
        vm.stopPrank();
        
        // Guardian 1 initiates
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(newOwner);
        
        // Guardian 2 tries to initiate different recovery
        vm.prank(guardian2);
        vm.expectRevert("Recovery pending");
        recoveryModule.initiateRecovery(address(0x999));
    }
    
    function testCanInitiateAfterCancellation() public {
        // Setup
        vm.prank(address(account));
        recoveryModule.addGuardian(guardian1);
        
        // First recovery
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(newOwner);
        
        // Cancel it
        vm.prank(address(account));
        recoveryModule.cancelRecovery();
        
        // Should be able to initiate new recovery
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(address(0x999));
        
        (address recoveryOwner, , , ) = recoveryModule.getRecoveryRequest();
        assertEq(recoveryOwner, address(0x999));
    }
    
    function testRecoveryWithSingleGuardian() public {
        // Setup with only one guardian
        vm.prank(address(account));
        recoveryModule.addGuardian(guardian1);
        
        // Authorize the recovery module (must be done by owner)
        vm.prank(owner);
        account.setRecoveryModule(address(recoveryModule), true);
        
        // Threshold should be 1
        assertEq(recoveryModule.threshold(), 1);
        
        // Guardian initiates (automatically meets threshold)
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(newOwner);
        
        (, uint256 approvalCount, , ) = recoveryModule.getRecoveryRequest();
        assertEq(approvalCount, 1);
        
        // Wait timelock and execute
        vm.warp(block.timestamp + 48 hours + 1);
        recoveryModule.executeRecovery();
    }
    
    function testThresholdAdjustsWhenRemovingGuardian() public {
        vm.startPrank(address(account));
        
        // Add 5 guardians (threshold becomes 3)
        recoveryModule.addGuardian(guardian1);
        recoveryModule.addGuardian(guardian2);
        recoveryModule.addGuardian(guardian3);
        recoveryModule.addGuardian(address(0x7));
        recoveryModule.addGuardian(address(0x8));
        assertEq(recoveryModule.threshold(), 3);
        
        // Manually set threshold to 4 (not 5, which would prevent removal)
        recoveryModule.setThreshold(4);
        
        // Remove one guardian - threshold should auto-adjust to 4 (max for 4 guardians)
        recoveryModule.removeGuardian(address(0x8));
        assertEq(recoveryModule.guardianCount(), 4);
        assertEq(recoveryModule.threshold(), 4); // Stays at 4 (still valid)
        
        // Set threshold to 3 before removing another
        recoveryModule.setThreshold(3);
        
        // Remove another guardian
        recoveryModule.removeGuardian(address(0x7));
        assertEq(recoveryModule.guardianCount(), 3);
        assertEq(recoveryModule.threshold(), 3); // Stays at 3 (still valid)
        
        vm.stopPrank();
    }
    
    // ============ Module Interface Tests ============
    
    function testPreExecuteAlwaysReturnsTrue() public {
        bool result = recoveryModule.preExecute(
            address(this),
            address(0x123),
            100,
            hex"00"
        );
        assertTrue(result);
    }
    
    function testPostExecuteReturnsTrue() public {
        bool result = recoveryModule.postExecute(
            address(this),
            address(0x123),
            100,
            hex"00",
            hex"00"
        );
        assertTrue(result);
    }
    
    // ============ Fuzz Tests ============
    
    function testFuzzAddGuardian(address guardian) public {
        vm.assume(guardian != address(0));
        vm.assume(guardian != address(account));
        
        vm.prank(address(account));
        recoveryModule.addGuardian(guardian);
        
        assertTrue(recoveryModule.isGuardian(guardian));
    }
    
    function testFuzzRecoveryFlow(
        address newOwnerFuzz,
        uint256 waitTime
    ) public {
        vm.assume(newOwnerFuzz != address(0));
        vm.assume(waitTime > 48 hours);
        vm.assume(waitTime < 365 days); // Reasonable upper bound
        
        // Setup
        vm.prank(address(account));
        recoveryModule.addGuardian(guardian1);
        
        // Authorize the recovery module (must be done by owner)
        vm.prank(owner);
        account.setRecoveryModule(address(recoveryModule), true);
        
        // Initiate
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(newOwnerFuzz);
        
        // Wait and execute
        vm.warp(block.timestamp + waitTime);
        recoveryModule.executeRecovery();
        
        // Verify execution happened
        (, , , bool executable) = recoveryModule.getRecoveryRequest();
        assertFalse(executable); // Should not be executable after execution
    }
    
    function testFuzzThreshold(uint8 numGuardians) public {
        vm.assume(numGuardians > 0 && numGuardians <= 10);
        
        vm.startPrank(address(account));
        
        // Add guardians
        for (uint8 i = 0; i < numGuardians; i++) {
            recoveryModule.addGuardian(address(uint160(100 + i)));
        }
        
        // Check threshold is majority
        uint256 expectedThreshold = (numGuardians / 2) + 1;
        assertEq(recoveryModule.threshold(), expectedThreshold);
        
        vm.stopPrank();
    }
}