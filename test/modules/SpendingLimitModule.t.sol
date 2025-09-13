// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {SmartAccount} from "../../src/SmartAccount.sol";
import {SpendingLimitModule, IERC20Like, SpendingLimitExceeded} from "../../src/modules/SpendingLimitModule.sol";
import {ModuleManager} from "../../src/modules/ModuleManager.sol";

/**
 * @dev Mock ERC20 token for testing
 */
contract MockERC20 is IERC20Like {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract SpendingLimitModuleTest is Test {
    SmartAccount public account;
    SpendingLimitModule public spendingModule;
    MockERC20 public token;
    
    address public owner;
    uint256 public ownerPrivateKey;
    address public recipient;
    
    uint256 public constant SPENDING_CAP = 1000 ether;
    uint256 public constant WINDOW_DURATION = 24 hours;
    
    // Events to test
    event LimitSet(address indexed token, uint256 cap);
    event Spent(address indexed token, uint256 newSpent);
    
    function setUp() public {
        // Setup accounts
        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);
        recipient = address(0xBEEF);
        
        // Deploy contracts
        account = new SmartAccount(owner);
        spendingModule = new SpendingLimitModule(address(account));
        token = new MockERC20();
        
        // Register module
        vm.prank(owner);
        account.addModule(address(spendingModule));
        
        // Fund account with tokens
        token.mint(address(account), 10000 ether);
        
        // Fund account with ETH
        vm.deal(address(account), 10 ether);
    }
    
    function testSetLimit() public {
        // Set spending limit
        vm.expectEmit(true, false, false, true, address(spendingModule));
        emit LimitSet(address(token), SPENDING_CAP);
        
        vm.prank(address(account));
        spendingModule.setLimit(address(token), SPENDING_CAP);
        
        // Check limit is set
        (uint256 cap, uint256 windowStart, uint256 spentInWindow) = spendingModule.limits(address(token));
        assertEq(cap, SPENDING_CAP);
        assertEq(windowStart, block.timestamp);
        assertEq(spentInWindow, 0);
    }
    
    function testSetLimitZeroAddress() public {
        // New module allows setting limit for address(0), which won't affect anything
        vm.prank(address(account));
        spendingModule.setLimit(address(0), SPENDING_CAP);
        (uint256 cap,,) = spendingModule.limits(address(0));
        assertEq(cap, SPENDING_CAP);
    }
    
    function testSetLimitZeroCap() public {
        // Zero cap means no limit (always passes)
        vm.prank(address(account));
        spendingModule.setLimit(address(token), 0);
        (uint256 cap,,) = spendingModule.limits(address(token));
        assertEq(cap, 0);
    }
    
    function testOnlyAccountCanSetLimit() public {
        vm.prank(owner);
        vm.expectRevert(bytes("not account"));
        spendingModule.setLimit(address(token), SPENDING_CAP);
    }
    
    function testTransferUnderCap() public {
        // Set limit
        vm.prank(address(account));
        spendingModule.setLimit(address(token), SPENDING_CAP);
        
        // Transfer under cap
        uint256 transferAmount = 500 ether;
        bytes memory data = abi.encodeWithSelector(IERC20Like.transfer.selector, recipient, transferAmount);
        
        vm.expectEmit(true, false, false, true, address(spendingModule));
        emit Spent(address(token), transferAmount);
        
        vm.prank(owner);
        account.execute(address(token), 0, data);
        
        // Check transfer succeeded
        assertEq(token.balanceOf(recipient), transferAmount);
        
        // Check spending status
        (uint256 cap, uint64 windowStart, uint256 spent) = spendingModule.limits(address(token));
        uint256 remaining = cap > spent ? cap - spent : 0;
        assertEq(cap, SPENDING_CAP);
        assertEq(spent, transferAmount);
        assertEq(remaining, SPENDING_CAP - transferAmount);
    }
    
    function testTransferExceedsCap() public {
        // Set limit
        vm.prank(address(account));
        spendingModule.setLimit(address(token), SPENDING_CAP);
        
        // Try to transfer over cap
        uint256 transferAmount = SPENDING_CAP + 1;
        bytes memory data = abi.encodeWithSelector(IERC20Like.transfer.selector, recipient, transferAmount);
        
        vm.prank(owner);
        vm.expectRevert(SpendingLimitExceeded.selector);
        account.execute(address(token), 0, data);
        
        // Check transfer didn't happen
        assertEq(token.balanceOf(recipient), 0);
    }
    
    function testMultipleTransfersUnderCap() public {
        // Set limit
        vm.prank(address(account));
        spendingModule.setLimit(address(token), SPENDING_CAP);
        
        // First transfer
        uint256 firstAmount = 300 ether;
        bytes memory data1 = abi.encodeWithSelector(IERC20Like.transfer.selector, recipient, firstAmount);
        vm.prank(owner);
        account.execute(address(token), 0, data1);
        
        // Second transfer
        uint256 secondAmount = 400 ether;
        bytes memory data2 = abi.encodeWithSelector(IERC20Like.transfer.selector, recipient, secondAmount);
        vm.prank(owner);
        account.execute(address(token), 0, data2);
        
        // Check both succeeded
        assertEq(token.balanceOf(recipient), firstAmount + secondAmount);
        
        // Check spending status
        (uint256 cap, uint64 windowStart, uint256 spent) = spendingModule.limits(address(token));
        uint256 remaining = cap > spent ? cap - spent : 0;
        assertEq(cap, SPENDING_CAP);
        assertEq(spent, firstAmount + secondAmount);
        assertEq(remaining, SPENDING_CAP - (firstAmount + secondAmount));
    }
    
    function testMultipleTransfersExceedCap() public {
        // Set limit
        vm.prank(address(account));
        spendingModule.setLimit(address(token), SPENDING_CAP);
        
        // First transfer (under cap)
        uint256 firstAmount = 800 ether;
        bytes memory data1 = abi.encodeWithSelector(IERC20Like.transfer.selector, recipient, firstAmount);
        vm.prank(owner);
        account.execute(address(token), 0, data1);
        
        // Second transfer (would exceed cap)
        uint256 secondAmount = 300 ether;
        bytes memory data2 = abi.encodeWithSelector(IERC20Like.transfer.selector, recipient, secondAmount);
        vm.prank(owner);
        vm.expectRevert(SpendingLimitExceeded.selector);
        account.execute(address(token), 0, data2);
        
        // Check only first transfer succeeded
        assertEq(token.balanceOf(recipient), firstAmount);
    }
    
    function testWindowReset() public {
        // Set limit
        vm.prank(address(account));
        spendingModule.setLimit(address(token), SPENDING_CAP);
        
        // Transfer near cap
        uint256 firstAmount = 900 ether;
        bytes memory data1 = abi.encodeWithSelector(IERC20Like.transfer.selector, recipient, firstAmount);
        vm.prank(owner);
        account.execute(address(token), 0, data1);
        
        // Try another transfer (should fail)
        uint256 secondAmount = 200 ether;
        bytes memory data2 = abi.encodeWithSelector(IERC20Like.transfer.selector, recipient, secondAmount);
        vm.prank(owner);
        vm.expectRevert(SpendingLimitExceeded.selector);
        account.execute(address(token), 0, data2);
        
        // Warp past 24 hours
        vm.warp(block.timestamp + WINDOW_DURATION + 1);
        
        // Now the transfer should succeed (window reset)
        vm.prank(owner);
        account.execute(address(token), 0, data2);
        
        // Check both transfers succeeded
        assertEq(token.balanceOf(recipient), firstAmount + secondAmount);
        
        // Check spending status (should be reset)
        (uint256 cap, uint64 windowStart, uint256 spent) = spendingModule.limits(address(token));
        uint256 remaining = cap > spent ? cap - spent : 0;
        assertEq(cap, SPENDING_CAP);
        assertEq(spent, secondAmount);
        assertEq(remaining, SPENDING_CAP - secondAmount);
    }
    
    function testNoLimitSetAllowsTransfer() public {
        // Don't set any limit
        
        // Transfer any amount (should succeed)
        uint256 transferAmount = 5000 ether;
        bytes memory data = abi.encodeWithSelector(IERC20Like.transfer.selector, recipient, transferAmount);
        
        vm.prank(owner);
        account.execute(address(token), 0, data);
        
        // Check transfer succeeded
        assertEq(token.balanceOf(recipient), transferAmount);
    }
    
    function testETHTransferNotAffected() public {
        // Set limit for some token
        vm.prank(address(account));
        spendingModule.setLimit(address(token), SPENDING_CAP);
        
        // Transfer ETH (should not be affected by spending limit)
        uint256 ethAmount = 1 ether;
        vm.prank(owner);
        account.execute(recipient, ethAmount, "");
        
        // Check ETH transfer succeeded
        assertEq(recipient.balance, ethAmount);
    }
    
    function testNonTransferFunctionAllowed() public {
        // Set limit
        vm.prank(address(account));
        spendingModule.setLimit(address(token), SPENDING_CAP);
        
        // Call balanceOf (not a transfer)
        bytes memory data = abi.encodeWithSelector(IERC20Like.balanceOf.selector, address(account));
        
        vm.prank(owner);
        bytes memory result = account.execute(address(token), 0, data);
        
        // Decode result
        uint256 balance = abi.decode(result, (uint256));
        assertEq(balance, 10000 ether);
    }
    
    function testMultipleTokensWithDifferentLimits() public {
        // Deploy second token
        MockERC20 token2 = new MockERC20();
        token2.mint(address(account), 10000 ether);
        
        // Set different limits
        vm.startPrank(address(account));
        spendingModule.setLimit(address(token), 1000 ether);
        spendingModule.setLimit(address(token2), 500 ether);
        vm.stopPrank();
        
        // Transfer from token1 (under its cap)
        bytes memory data1 = abi.encodeWithSelector(IERC20Like.transfer.selector, recipient, 800 ether);
        vm.prank(owner);
        account.execute(address(token), 0, data1);
        
        // Transfer from token2 (under its cap)
        bytes memory data2 = abi.encodeWithSelector(IERC20Like.transfer.selector, recipient, 400 ether);
        vm.prank(owner);
        account.execute(address(token2), 0, data2);
        
        // Check both succeeded
        assertEq(token.balanceOf(recipient), 800 ether);
        assertEq(token2.balanceOf(recipient), 400 ether);
        
        // Try to exceed token2's cap
        bytes memory data3 = abi.encodeWithSelector(IERC20Like.transfer.selector, recipient, 200 ether);
        vm.prank(owner);
        vm.expectRevert(SpendingLimitExceeded.selector);
        account.execute(address(token2), 0, data3);
    }
    
    function testTODO_TransferFromNotYetChecked() public {
        // This is a reminder that SpendingLimitModule guards only transfer(selector 0xa9059cbb)
        // A real wallet must also consider transferFrom and permit flows
        // For now, this test documents the gap and should be updated in Sprint 2
        assertTrue(true);
    }
}
