// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {SmartAccount} from "../../src/SmartAccount.sol";
import {SpendingLimitModule, SpendingLimitExceeded} from "../../src/modules/SpendingLimitModule.sol";
import {ModuleManager} from "../../src/modules/ModuleManager.sol";

contract SpendingLimitModule_ETH_Test is Test {
    SmartAccount public account;
    SpendingLimitModule public limitModule;
    
    address public owner;
    address public recipient;
    
    event EthSpent(address indexed spender, uint256 amount);
    event EthLimitExceeded(uint256 attempted, uint256 cap);
    event LimitSet(address indexed token, uint256 cap);
    
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
    
    function test_SetEthLimit() public {
        // Set 1 ETH daily limit
        vm.expectEmit(true, false, false, true);
        emit LimitSet(address(0), 1 ether);
        
        vm.prank(address(account));
        limitModule.setLimit(address(0), 1 ether);
        
        // Check limit is set
        (uint256 cap,,,,) = limitModule.limits(address(0));
        assertEq(cap, 1 ether);
    }
    
    function test_EthTransferUnderLimit() public {
        // Set 1 ETH limit
        vm.prank(address(account));
        limitModule.setLimit(address(0), 1 ether);
        
        // Send 0.5 ETH (under limit)
        vm.expectEmit(true, false, false, true);
        emit EthSpent(owner, 0.5 ether);
        
        vm.prank(owner);
        account.execute(recipient, 0.5 ether, "");
        
        // Check recipient received ETH
        assertEq(recipient.balance, 0.5 ether);
        
        // Check spent amount updated
        (,, uint256 spent,,) = limitModule.limits(address(0));
        assertEq(spent, 0.5 ether);
    }
    
    function test_EthTransferExceedsLimit() public {
        // Set 1 ETH limit
        vm.prank(address(account));
        limitModule.setLimit(address(0), 1 ether);
        
        // Try to send 2 ETH (over limit)
        vm.expectRevert(SpendingLimitExceeded.selector);
        vm.prank(owner);
        account.execute(recipient, 2 ether, "");
        
        // Check recipient didn't receive ETH
        assertEq(recipient.balance, 0);
    }
    
    function test_EthLimitRollover() public {
        // Set 1 ETH daily limit
        vm.prank(address(account));
        limitModule.setLimit(address(0), 1 ether);
        
        // Spend 0.8 ETH
        vm.prank(owner);
        account.execute(recipient, 0.8 ether, "");
        
        // Try to spend 0.5 ETH more (would exceed)
        vm.expectRevert(SpendingLimitExceeded.selector);
        vm.prank(owner);
        account.execute(recipient, 0.5 ether, "");
        
        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);
        
        // Now should be able to spend again
        vm.prank(owner);
        account.execute(recipient, 0.5 ether, "");
        
        assertEq(recipient.balance, 1.3 ether); // 0.8 + 0.5
    }
    
    function test_EthBypassForOwner() public {
        // Set 1 ETH limit
        vm.prank(address(account));
        limitModule.setLimit(address(0), 1 ether);
        
        // Enable bypass for 1 hour
        vm.prank(address(account));
        limitModule.enableOwnerBypass(1 hours);
        
        // Should be able to send more than limit
        vm.prank(owner);
        account.execute(recipient, 5 ether, "");
        
        assertEq(recipient.balance, 5 ether);
    }
    
    function test_MultipleEthTransfers() public {
        // Set 1 ETH limit
        vm.prank(address(account));
        limitModule.setLimit(address(0), 1 ether);
        
        // Send multiple small amounts
        vm.startPrank(owner);
        account.execute(recipient, 0.3 ether, "");
        account.execute(recipient, 0.3 ether, "");
        account.execute(recipient, 0.3 ether, "");
        
        // This should fail (total would be 1.2 ETH)
        vm.expectRevert(SpendingLimitExceeded.selector);
        account.execute(recipient, 0.3 ether, "");
        vm.stopPrank();
        
        assertEq(recipient.balance, 0.9 ether);
    }
    
    function test_NoLimitSetAllowsAnyAmount() public {
        // No limit set, should allow any amount
        vm.prank(owner);
        account.execute(recipient, 5 ether, "");
        
        assertEq(recipient.balance, 5 ether);
    }
    
    function test_EthAndTokenLimitsIndependent() public {
        // Set both ETH and token limits
        vm.startPrank(address(account));
        limitModule.setLimit(address(0), 1 ether); // ETH limit
        limitModule.setLimit(address(0x1234), 1000); // Token limit
        vm.stopPrank();
        
        // Spend ETH up to limit
        vm.prank(owner);
        account.execute(recipient, 0.9 ether, "");
        
        // ETH limit should be tracked separately from token
        (,, uint256 ethSpent,,) = limitModule.limits(address(0));
        (,, uint256 tokenSpent,,) = limitModule.limits(address(0x1234));
        
        assertEq(ethSpent, 0.9 ether);
        assertEq(tokenSpent, 0); // Token not spent
    }
}
