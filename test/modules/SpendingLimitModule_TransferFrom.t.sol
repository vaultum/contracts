// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {SmartAccount} from "../../src/SmartAccount.sol";
import {SpendingLimitModule, SpendingLimitExceeded, IERC20Like} from "../../src/modules/SpendingLimitModule.sol";

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

contract SpendingLimitModuleTransferFromTest is Test {
    SmartAccount public account;
    SpendingLimitModule public spendingModule;
    MockERC20 public token;
    
    address public owner;
    address public spender;
    address public recipient;
    
    function setUp() public {
        owner = address(0xA11CE);
        spender = address(0xBEEF);
        recipient = address(0xCAFE);
        
        account = new SmartAccount(owner);
        spendingModule = new SpendingLimitModule(address(account));
        token = new MockERC20();
        
        // Add module to account
        vm.prank(owner);
        account.addModule(address(spendingModule));
        
        // Mint tokens to account
        token.mint(address(account), 1000 ether);
        
        // Account approves spender and itself (for transferFrom tests)
        vm.prank(owner);
        account.execute(
            address(token),
            0,
            abi.encodeWithSelector(token.approve.selector, spender, 1000 ether)
        );
        
        // Account also approves itself for transferFrom
        vm.prank(owner);
        account.execute(
            address(token),
            0,
            abi.encodeWithSelector(token.approve.selector, address(account), 1000 ether)
        );
    }
    
    function testTransferFromBlockedWhenExceedsCap() public {
        // Set a low cap
        vm.prank(address(account));
        spendingModule.setLimit(address(token), 100 ether);
        
        // Try to transferFrom more than the cap
        bytes memory transferFromData = abi.encodeWithSelector(
            token.transferFrom.selector,
            address(account),
            recipient,
            200 ether
        );
        
        // This should be blocked by the module
        vm.prank(owner);
        vm.expectRevert(SpendingLimitExceeded.selector);
        account.execute(address(token), 0, transferFromData);
    }
    
    function testTransferFromAllowedUnderCap() public {
        // Set a reasonable cap
        vm.prank(address(account));
        spendingModule.setLimit(address(token), 500 ether);
        
        // TransferFrom under the cap
        bytes memory transferFromData = abi.encodeWithSelector(
            token.transferFrom.selector,
            address(account),
            recipient,
            100 ether
        );
        
        // This should succeed
        vm.prank(owner);
        account.execute(address(token), 0, transferFromData);
        
        // Verify transfer happened
        assertEq(token.balanceOf(recipient), 100 ether);
        assertEq(token.balanceOf(address(account)), 900 ether);
    }
    
    function testTransferFromSharesCapWithTransfer() public {
        // Set cap
        vm.prank(address(account));
        spendingModule.setLimit(address(token), 150 ether);
        
        // First do a regular transfer for 50 ether
        bytes memory transferData = abi.encodeWithSelector(
            token.transfer.selector,
            recipient,
            50 ether
        );
        vm.prank(owner);
        account.execute(address(token), 0, transferData);
        
        // Now try transferFrom for 120 ether (total would be 170, exceeds 150 cap)
        bytes memory transferFromData = abi.encodeWithSelector(
            token.transferFrom.selector,
            address(account),
            recipient,
            120 ether
        );
        
        vm.prank(owner);
        vm.expectRevert(SpendingLimitExceeded.selector);
        account.execute(address(token), 0, transferFromData);
        
        // But 100 ether should work (total 150)
        transferFromData = abi.encodeWithSelector(
            token.transferFrom.selector,
            address(account),
            recipient,
            100 ether
        );
        
        vm.prank(owner);
        account.execute(address(token), 0, transferFromData);
        
        assertEq(token.balanceOf(recipient), 150 ether);
    }
    
    function testLimitExceededEventEmitted() public {
        // Set a low cap
        vm.prank(address(account));
        spendingModule.setLimit(address(token), 50 ether);
        
        // Try to transferFrom more than the cap
        bytes memory transferFromData = abi.encodeWithSelector(
            token.transferFrom.selector,
            address(account),
            recipient,
            100 ether
        );
        
        // Expect the LimitExceeded event
        vm.expectEmit(true, false, false, true);
        emit SpendingLimitModule.LimitExceeded(address(token), 100 ether, 50 ether);
        
        // This should revert after emitting the event
        vm.prank(owner);
        vm.expectRevert(SpendingLimitExceeded.selector);
        account.execute(address(token), 0, transferFromData);
    }
}
