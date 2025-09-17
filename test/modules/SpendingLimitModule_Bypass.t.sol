// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {SpendingLimitModule, SpendingLimitExceeded} from "../../src/modules/SpendingLimitModule.sol";
import {SmartAccount} from "../../src/SmartAccount.sol";
import {IModule} from "../../src/modules/IModule.sol";
import {ModuleManagerOptimized} from "../../src/modules/ModuleManagerOptimized.sol";

contract MockToken {
    mapping(address => uint256) public balanceOf;
    
    event Transfer(address indexed from, address indexed to, uint256 amount);
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
}

contract SpendingLimitModuleBypassTest is Test {
    SmartAccount account;
    SpendingLimitModule spendingModule;
    MockToken token;
    
    address owner = address(0x1);
    address recipient = address(0x999);
    
    event LimitBypassed(address indexed owner, address indexed token, uint256 amount);
    event BypassToggled(bool enabled);
    
    function setUp() public {
        // Deploy contracts
        vm.prank(owner);
        account = new SmartAccount(owner);
        
        spendingModule = new SpendingLimitModule(address(account));
        token = new MockToken();
        
        // Add spending module
        vm.prank(owner);
        account.addModule(address(spendingModule));
        
        // Fund account with tokens
        token.mint(address(account), 1000 ether);
        
        // Set a low spending limit (100 tokens per day)
        vm.prank(owner);
        account.execute(
            address(spendingModule),
            0,
            abi.encodeWithSelector(
                spendingModule.setLimit.selector,
                address(token),
                100 ether
            )
        );
    }
    
    function testOwnerBypassEnableAndDisable() public {
        // Enable bypass for 1 hour
        vm.expectEmit(true, true, true, true);
        emit BypassToggled(true);
        
        vm.prank(owner);
        account.execute(
            address(spendingModule),
            0,
            abi.encodeWithSelector(
                spendingModule.enableOwnerBypass.selector,
                1 hours
            )
        );
        
        assertTrue(spendingModule.ownerBypassEnabled());
        assertTrue(spendingModule.isBypassActive());
        assertEq(spendingModule.bypassEnabledUntil(), block.timestamp + 1 hours);
        
        // Disable bypass
        vm.expectEmit(true, true, true, true);
        emit BypassToggled(false);
        
        vm.prank(owner);
        account.execute(
            address(spendingModule),
            0,
            abi.encodeWithSelector(
                spendingModule.disableOwnerBypass.selector
            )
        );
        
        assertFalse(spendingModule.ownerBypassEnabled());
        assertFalse(spendingModule.isBypassActive());
        assertEq(spendingModule.bypassEnabledUntil(), 0);
    }
    
    function testBypassAllowsTransferOverLimit() public {
        // Enable bypass
        vm.prank(owner);
        account.execute(
            address(spendingModule),
            0,
            abi.encodeWithSelector(
                spendingModule.enableOwnerBypass.selector,
                1 hours
            )
        );
        
        // Transfer 500 tokens (way over 100 limit)
        vm.expectEmit(true, true, true, true);
        emit LimitBypassed(owner, address(token), 500 ether);
        
        vm.prank(owner);
        account.execute(
            address(token),
            0,
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                recipient,
                500 ether
            )
        );
        
        assertEq(token.balanceOf(recipient), 500 ether);
        assertEq(token.balanceOf(address(account)), 500 ether);
    }
    
    function testBypassExpiresAfterDuration() public {
        // Enable bypass for 1 hour
        vm.prank(owner);
        account.execute(
            address(spendingModule),
            0,
            abi.encodeWithSelector(
                spendingModule.enableOwnerBypass.selector,
                1 hours
            )
        );
        
        assertTrue(spendingModule.isBypassActive());
        
        // Warp 2 hours forward
        vm.warp(block.timestamp + 2 hours);
        
        // Bypass should be expired
        assertFalse(spendingModule.isBypassActive());
        
        // Transfer should now be blocked
        vm.prank(owner);
        vm.expectRevert(SpendingLimitExceeded.selector);
        account.execute(
            address(token),
            0,
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                recipient,
                500 ether
            )
        );
    }
    
    function testCannotEnableBypassForMoreThan24Hours() public {
        vm.prank(owner);
        vm.expectRevert("call failed");
        account.execute(
            address(spendingModule),
            0,
            abi.encodeWithSelector(
                spendingModule.enableOwnerBypass.selector,
                25 hours
            )
        );
    }
    
    function testOnlyOwnerCanEnableBypass() public {
        // Non-owner cannot enable bypass
        vm.prank(address(0x777));
        vm.expectRevert("not account");
        spendingModule.enableOwnerBypass(1 hours);
        
        // Owner via account can enable
        vm.prank(owner);
        account.execute(
            address(spendingModule),
            0,
            abi.encodeWithSelector(
                spendingModule.enableOwnerBypass.selector,
                1 hours
            )
        );
        
        assertTrue(spendingModule.isBypassActive());
    }
}
