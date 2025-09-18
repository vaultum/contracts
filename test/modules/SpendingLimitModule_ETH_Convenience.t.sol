// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {SmartAccount} from "../../src/SmartAccount.sol";
import {SpendingLimitModule, SpendingLimitExceeded} from "../../src/modules/SpendingLimitModule.sol";

contract SpendingLimitModule_ETH_Convenience_Test is Test {
    SmartAccount public account;
    SpendingLimitModule public limitModule;
    
    address public owner;
    address public recipient;
    
    event LimitSet(address indexed token, uint256 cap);
    event EthSpent(address indexed spender, uint256 amount);
    
    function setUp() public {
        owner = makeAddr("owner");
        recipient = makeAddr("recipient");
        
        // Deploy contracts
        account = new SmartAccount(owner);
        limitModule = new SpendingLimitModule(address(account));
        
        // Setup account with ETH
        vm.deal(address(account), 10 ether);
        
        // Add module
        vm.prank(owner);
        account.addModule(address(limitModule));
    }
    
    function test_SetEthLimit_Convenience() public {
        // Use convenience function to set ETH limit
        vm.expectEmit(true, false, false, true);
        emit LimitSet(address(0), 2 ether);
        
        vm.prank(address(account));
        limitModule.setEthLimit(2 ether);
        
        // Verify limit is set correctly
        (uint256 cap, uint256 spent, uint256 remaining,) = limitModule.getEthLimit();
        assertEq(cap, 2 ether);
        assertEq(spent, 0);
        assertEq(remaining, 2 ether);
    }
    
    function test_RemoveEthLimit() public {
        // First set a limit
        vm.prank(address(account));
        limitModule.setEthLimit(1 ether);
        
        // Verify limit exists
        (uint256 cap,,,) = limitModule.getEthLimit();
        assertEq(cap, 1 ether);
        
        // Remove the limit
        vm.expectEmit(true, false, false, true);
        emit LimitSet(address(0), 0);
        
        vm.prank(address(account));
        limitModule.removeEthLimit();
        
        // Verify limit is removed
        (cap,,,) = limitModule.getEthLimit();
        assertEq(cap, 0);
        
        // Should be able to send any amount now
        vm.prank(owner);
        account.execute(recipient, 5 ether, "");
        assertEq(recipient.balance, 5 ether);
    }
    
    function test_SetEthLimit_UpdatesExisting() public {
        // Set initial limit
        vm.prank(address(account));
        limitModule.setEthLimit(1 ether);
        
        // Spend some ETH
        vm.prank(owner);
        account.execute(recipient, 0.5 ether, "");
        
        // Update limit to higher value
        vm.prank(address(account));
        limitModule.setEthLimit(3 ether);
        
        // Check that spent amount is preserved
        (uint256 cap, uint256 spent,,) = limitModule.getEthLimit();
        assertEq(cap, 3 ether);
        assertEq(spent, 0.5 ether); // Spent amount preserved
        
        // Should be able to spend up to new limit minus already spent
        vm.prank(owner);
        account.execute(makeAddr("recipient2"), 2.4 ether, "");
        
        // This should fail (would be 2.9 ether total)
        vm.expectRevert(SpendingLimitExceeded.selector);
        vm.prank(owner);
        account.execute(makeAddr("recipient3"), 0.2 ether, "");
    }
    
    function test_SetEthLimit_EmitsCorrectEvent() public {
        // Test that setEthLimit emits the correct event with address(0)
        vm.expectEmit(true, false, false, true);
        emit LimitSet(address(0), 1.5 ether);
        
        vm.prank(address(account));
        limitModule.setEthLimit(1.5 ether);
    }
    
    function test_SetEthLimit_OnlyAccount() public {
        // Try to set limit from non-account address
        vm.expectRevert("not account");
        vm.prank(owner);
        limitModule.setEthLimit(1 ether);
        
        // Try removeEthLimit from non-account
        vm.expectRevert("not account");
        vm.prank(owner);
        limitModule.removeEthLimit();
    }
    
    function test_SetEthLimit_WorksWithTransfers() public {
        // Set ETH limit using convenience function
        vm.prank(address(account));
        limitModule.setEthLimit(1 ether);
        
        // Transfer should work under limit
        vm.prank(owner);
        account.execute(recipient, 0.8 ether, "");
        assertEq(recipient.balance, 0.8 ether);
        
        // Check spent tracking
        (, uint256 spent,,) = limitModule.getEthLimit();
        assertEq(spent, 0.8 ether);
        
        // Transfer exceeding limit should fail
        vm.expectRevert(SpendingLimitExceeded.selector);
        vm.prank(owner);
        account.execute(recipient, 0.3 ether, ""); // Would be 1.1 ether total
    }
    
    function test_SetEthLimit_ZeroCapDisablesLimit() public {
        // Set a limit first
        vm.prank(address(account));
        limitModule.setEthLimit(1 ether);
        
        // Set to zero
        vm.prank(address(account));
        limitModule.setEthLimit(0);
        
        // Should be able to send any amount (0 means no limit)
        vm.prank(owner);
        account.execute(recipient, 5 ether, "");
        assertEq(recipient.balance, 5 ether);
    }
}
