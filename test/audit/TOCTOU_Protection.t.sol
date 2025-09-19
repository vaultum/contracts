// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {SmartAccount} from "../../src/SmartAccount.sol";
import {SessionKeyValidator} from "../../src/validators/SessionKeyValidator.sol";

/**
 * @title AUDITOR REQUIRED: TOCTOU Protection Tests
 * @notice Proves session key binding prevents Time-of-Check, Time-of-Use attacks
 */
contract TOCTOU_ProtectionTest is Test {
    SmartAccount public account;
    SessionKeyValidator public validator;
    
    address public owner = makeAddr("owner");
    address public sessionKey = makeAddr("sessionKey");
    address public target = makeAddr("target");

    function setUp() public {
        account = new SmartAccount(owner);
        validator = new SessionKeyValidator(address(account));
        
        vm.deal(address(account), 10 ether);
        
        vm.startPrank(owner);
        account.addValidator(address(validator));
        vm.stopPrank();
        
        vm.prank(address(account));
        validator.grant(sessionKey, uint64(block.timestamp + 1 days));
        
        vm.prank(address(account));
        validator.allowSelector(sessionKey, bytes4(keccak256("executeWithSessionKey(address,address,uint256,bytes,uint256)")), true);
    }

    function test_TOCTOU_SessionKeyBinding() public {
        // Set spending cap
        vm.prank(address(account));
        validator.setSpendingCap(sessionKey, 1 ether);
        
        // Test executeWithSessionKey with explicit binding
        uint256 currentWindowId = validator.getWindowId(uint48(block.timestamp));
        vm.prank(owner); // Simulating EntryPoint call
        account.executeWithSessionKey(sessionKey, target, 0.5 ether, "", currentWindowId);
        
        // Verify spending was consumed
        uint48 currentTime = uint48(block.timestamp);
        (, uint256 spent,) = validator.getSpendingStatus(sessionKey, currentTime);
        assertEq(spent, 0.5 ether);
        
        // Verify target received funds
        assertEq(target.balance, 0.5 ether);
    }

    function test_TOCTOU_AtomicConsumption() public {
        // Set cap near limit
        vm.prank(address(account));
        validator.setSpendingCap(sessionKey, 1 ether);
        
        // Consume most of cap
        uint48 currentTime = uint48(block.timestamp);
        vm.prank(address(account));
        validator.consumeOrRevert(sessionKey, 0.9 ether, currentTime);
        
        // Verify consumption
        (, uint256 spent,) = validator.getSpendingStatus(sessionKey, currentTime);
        assertEq(spent, 0.9 ether);
        
        // Try to exceed remaining cap - should revert atomically
        vm.expectRevert("Daily cap exceeded");
        vm.prank(address(account));
        validator.consumeOrRevert(sessionKey, 0.2 ether, currentTime); // 0.9 + 0.2 > 1.0
        
        // Spending should remain unchanged after revert
        (, spent,) = validator.getSpendingStatus(sessionKey, currentTime);
        assertEq(spent, 0.9 ether);
    }

    function test_TOCTOU_WindowDeterminism() public {
        uint48 windowStart = uint48(block.timestamp);
        uint48 sameDay = windowStart + 3600; // 1 hour later
        uint48 nextDay = windowStart + 1 days;
        
        // Same day should have same window ID
        assertEq(
            validator.getWindowId(windowStart), 
            validator.getWindowId(sameDay),
            "Same day should have same window"
        );
        
        // Different day should have different window ID
        assertTrue(
            validator.getWindowId(nextDay) > validator.getWindowId(windowStart),
            "Next day should have different window"
        );
        
        // Window calculation is pure and deterministic
        assertEq(validator.getWindowId(windowStart), validator.getWindowId(windowStart));
        assertEq(validator.getWindowId(nextDay), validator.getWindowId(nextDay));
    }

    function test_TOCTOU_ConcurrentProtection() public {
        // Set 1 ETH cap
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
        // This simulates the race condition: both would pass validation
        // but only one can succeed in atomic consumption
        vm.expectRevert("Daily cap exceeded");
        vm.prank(address(account));
        validator.consumeOrRevert(sessionKey, 0.8 ether, currentTime); // 0.8 + 0.8 > 1.0
        
        // Only first operation should have succeeded
        (, spent,) = validator.getSpendingStatus(sessionKey, currentTime);
        assertEq(spent, 0.8 ether); // Still 0.8, second consumption failed
    }

    function test_TOCTOU_TargetAllowlistBinding() public {
        address allowedTarget = makeAddr("allowedTarget");
        address blockedTarget = makeAddr("blockedTarget");
        
        // Setup target restrictions
        vm.startPrank(address(account));
        validator.setTargetRestrictions(sessionKey, true);
        validator.allowTarget(sessionKey, allowedTarget, true);
        vm.stopPrank();
        
        // Allowed target should work
        assertTrue(validator.isTargetAllowed(sessionKey, allowedTarget));
        
        // Blocked target should fail
        assertFalse(validator.isTargetAllowed(sessionKey, blockedTarget));
        
        // Test with executeWithSessionKey
        uint256 currentWindowId = validator.getWindowId(uint48(block.timestamp));
        vm.prank(owner);
        account.executeWithSessionKey(sessionKey, allowedTarget, 0.1 ether, "", currentWindowId);
        assertEq(allowedTarget.balance, 0.1 ether);
    }
}
