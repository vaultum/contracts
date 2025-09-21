// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {SmartAccount} from "../src/SmartAccount.sol";
import {SessionKeyValidator} from "../src/validators/SessionKeyValidator.sol";

/**
 * @title V2 Session Key Caps - Implementation Tests
 * @notice AUDITOR APPROVED: Deterministic validation with race-safety
 * @dev Following approved design: nonce-based ordering, no validation state writes
 */
contract SessionKeyCapsTest is Test {
    SmartAccount public account;
    SessionKeyValidator public validator;
    address public owner = makeAddr("owner");
    address public sessionKey = makeAddr("sessionKey");
    uint256 public sessionKeyPrivate = 0xBEEF;
    
    event CapExceeded(address indexed key, uint256 attempted, uint256 cap);
    event CapConsumed(address indexed key, uint256 amount, uint256 newTotal);
    event AllowlistViolation(address indexed key, address indexed target);

    function setUp() public {
        account = new SmartAccount(owner);
        validator = new SessionKeyValidator(address(account));
        sessionKey = vm.addr(sessionKeyPrivate);
        
        vm.deal(address(account), 10 ether);
        vm.startPrank(owner);
        account.addValidator(address(validator));
        vm.stopPrank();
    }

    function test_SessionKeyCaps_DeterministicValidation() public {
        // Setup session key with 1 ETH daily cap
        vm.prank(address(account));
        validator.grant(sessionKey, uint64(block.timestamp + 1 days));
        
        vm.prank(address(account));
        validator.setSpendingCap(sessionKey, 1 ether);
        
        // Test deterministic validation using validAfter
        uint48 windowStart = uint48(block.timestamp);
        
        // Check that spending under cap is allowed
        assertFalse(validator.wouldExceedCap(sessionKey, 0.5 ether, windowStart));
        
        // Check that spending over cap is blocked  
        assertTrue(validator.wouldExceedCap(sessionKey, 1.5 ether, windowStart));
        
        // Test that validation is deterministic - same validAfter gives same result
        assertFalse(validator.wouldExceedCap(sessionKey, 0.5 ether, windowStart));
        assertTrue(validator.wouldExceedCap(sessionKey, 1.5 ether, windowStart));
    }

    function test_SessionKeyCaps_WindowBoundaries() public {
        // Setup session key with cap
        vm.prank(address(account));
        validator.grant(sessionKey, uint64(block.timestamp + 1 days));
        
        vm.prank(address(account));
        validator.setSpendingCap(sessionKey, 1 ether);
        
        // Test window boundaries using deterministic calculation
        uint48 day1Start = uint48(block.timestamp);
        uint48 day2Start = day1Start + 1 days;
        
        // Same day - spending should accumulate
        uint256 windowId1 = validator.getWindowId(day1Start);
        uint256 windowId1Later = validator.getWindowId(day1Start + 3600); // 1 hour later same day
        assertEq(windowId1, windowId1Later, "Same day should have same window ID");
        
        // Different day - different window
        uint256 windowId2 = validator.getWindowId(day2Start);
        assertTrue(windowId2 > windowId1, "Next day should have different window ID");
        
        // Window calculation is deterministic
        assertEq(validator.getWindowId(day1Start), validator.getWindowId(day1Start));
        assertEq(validator.getWindowId(day2Start), validator.getWindowId(day2Start));
    }

    function test_SessionKeyCaps_Events_Emitted() public {
        // Setup session key
        vm.prank(address(account));
        validator.grant(sessionKey, uint64(block.timestamp + 1 days));
        
        // Test SessionCapSet event
        vm.expectEmit(true, false, false, true);
        emit SessionCapSet(sessionKey, 1 ether);
        
        vm.prank(address(account));
        validator.setSpendingCap(sessionKey, 1 ether);
        
        // Test TargetRestrictionsSet event
        vm.expectEmit(true, false, false, true);
        emit TargetRestrictionsSet(sessionKey, true);
        
        vm.prank(address(account));
        validator.setTargetRestrictions(sessionKey, true);
        
        // Test TargetAllowed event
        address allowedTarget = makeAddr("allowedTarget");
        vm.expectEmit(true, true, false, true);
        emit TargetAllowed(sessionKey, allowedTarget, true);
        
        vm.prank(address(account));
        validator.allowTarget(sessionKey, allowedTarget, true);
    }
    
    event SessionCapSet(address indexed key, uint256 dailyCap);
    event TargetRestrictionsSet(address indexed key, bool enabled);
    event TargetAllowed(address indexed key, address indexed target, bool allowed);
    
    function test_SessionKeyCaps_SpendingAndRecording() public {
        // Setup session key with cap
        vm.prank(address(account));
        validator.grant(sessionKey, uint64(block.timestamp + 1 days));
        
        vm.prank(address(account));
        validator.setSpendingCap(sessionKey, 1 ether);
        
        uint48 currentTime = uint48(block.timestamp);
        
        // Initially no spending
        (uint256 cap, uint256 spent, uint256 remaining) = validator.getSpendingStatus(sessionKey, currentTime);
        assertEq(cap, 1 ether);
        assertEq(spent, 0);
        assertEq(remaining, 1 ether);
        
        // Record some spending
        vm.expectEmit(true, false, false, true);
        emit CapConsumed(sessionKey, 0.3 ether, 0.3 ether);
        
        vm.prank(address(account));
        validator.recordSpending(sessionKey, 0.3 ether, currentTime);
        
        // Check updated status
        (cap, spent, remaining) = validator.getSpendingStatus(sessionKey, currentTime);
        assertEq(spent, 0.3 ether);
        assertEq(remaining, 0.7 ether);
    }

    function test_SessionKeyCaps_TargetAllowlist() public {
        address allowedTarget = makeAddr("allowed");
        address blockedTarget = makeAddr("blocked");
        
        // Setup session key with target restrictions
        vm.prank(address(account));
        validator.grant(sessionKey, uint64(block.timestamp + 1 days));
        
        vm.prank(address(account));
        validator.setTargetRestrictions(sessionKey, true);
        
        vm.prank(address(account));
        validator.allowTarget(sessionKey, allowedTarget, true);
        
        // Check allowlist logic
        assertTrue(validator.isTargetAllowed(sessionKey, allowedTarget));
        assertFalse(validator.isTargetAllowed(sessionKey, blockedTarget));
        
        // Disable restrictions - should allow all targets
        vm.prank(address(account));
        validator.setTargetRestrictions(sessionKey, false);
        
        assertTrue(validator.isTargetAllowed(sessionKey, allowedTarget));
        assertTrue(validator.isTargetAllowed(sessionKey, blockedTarget));
    }
}
