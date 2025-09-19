// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {SpendingLimitModule, SpendingLimitExceeded} from "../../src/modules/SpendingLimitModule.sol";
import {SmartAccount} from "../../src/SmartAccount.sol";

/**
 * @title AUDITOR P3: ETH Batch Limits Tests
 * @notice Tests that ETH limits are enforced on batch execution aggregates
 */
contract SpendingLimitBatchTest is Test {
    SmartAccount public account;
    SpendingLimitModule public spendingModule;
    address public owner = makeAddr("owner");
    
    SmartAccount.Call[] calls;

    event LimitBypassed(address indexed owner, address indexed token, uint256 amount);
    event EthSpent(address indexed spender, uint256 amount);
    event EthLimitExceeded(uint256 attempted, uint256 cap);

    function setUp() public {
        account = new SmartAccount(owner);
        spendingModule = new SpendingLimitModule(address(account));
        
        vm.deal(address(account), 10 ether);
        vm.startPrank(owner);
        account.addModule(address(spendingModule));
        vm.stopPrank();
        
        vm.prank(address(account));
        spendingModule.setEthLimit(1 ether); // 1 ETH daily limit
        
        // Clear calls array
        delete calls;
    }

    function test_ETHLimit_SingleCall_Enforced() public {
        // Single call under limit should work
        vm.prank(owner);
        account.execute(makeAddr("recipient"), 0.5 ether, "");
        
        // Single call over remaining limit should fail
        vm.expectRevert(SpendingLimitExceeded.selector);
        vm.prank(owner);
        account.execute(makeAddr("recipient2"), 0.6 ether, ""); // 0.5 + 0.6 > 1.0
    }

    function test_ETHLimit_Batch_AggregateEnforced() public {
        // Create batch that individually are under limit but aggregate exceeds
        calls.push(SmartAccount.Call({
            target: makeAddr("recipient1"),
            value: 0.4 ether,
            data: ""
        }));
        calls.push(SmartAccount.Call({
            target: makeAddr("recipient2"), 
            value: 0.4 ether,
            data: ""
        }));
        calls.push(SmartAccount.Call({
            target: makeAddr("recipient3"),
            value: 0.3 ether, // Total: 1.1 ETH > 1.0 ETH limit
            data: ""
        }));
        
        // Batch should fail due to aggregate ETH limit
        vm.expectRevert(SpendingLimitExceeded.selector);
        vm.prank(owner);
        account.executeBatch(calls);
    }

    function test_ETHLimit_Batch_UnderLimitSucceeds() public {
        // Create batch under aggregate limit
        calls.push(SmartAccount.Call({
            target: makeAddr("recipient1"),
            value: 0.3 ether,
            data: ""
        }));
        calls.push(SmartAccount.Call({
            target: makeAddr("recipient2"),
            value: 0.3 ether,
            data: ""
        }));
        calls.push(SmartAccount.Call({
            target: makeAddr("recipient3"),
            value: 0.3 ether, // Total: 0.9 ETH < 1.0 ETH limit
            data: ""
        }));
        
        // Should succeed and emit ETH spent event
        vm.expectEmit(true, false, false, true);
        emit EthSpent(owner, 0.9 ether);
        
        vm.prank(owner);
        account.executeBatch(calls);
        
        // Verify recipients received funds
        assertEq(makeAddr("recipient1").balance, 0.3 ether);
        assertEq(makeAddr("recipient2").balance, 0.3 ether);
        assertEq(makeAddr("recipient3").balance, 0.3 ether);
    }

    function test_ETHLimit_OwnerBypass_EmitsEvent() public {
        // Enable owner bypass
        vm.prank(address(account));
        spendingModule.enableOwnerBypass(1 hours);
        
        // Large transfer should work and emit bypass event
        vm.expectEmit(true, true, false, true);
        emit LimitBypassed(owner, address(0), 2 ether);
        
        vm.prank(owner);
        account.execute(makeAddr("recipient"), 2 ether, "");
        
        assertEq(makeAddr("recipient").balance, 2 ether);
    }

    function test_ETHLimit_BatchBypass_EmitsEvent() public {
        // Enable owner bypass
        vm.prank(address(account));
        spendingModule.enableOwnerBypass(1 hours);
        
        // Create batch that exceeds limit
        calls.push(SmartAccount.Call({
            target: makeAddr("recipient1"),
            value: 1 ether,
            data: ""
        }));
        calls.push(SmartAccount.Call({
            target: makeAddr("recipient2"),
            value: 1 ether, // Total: 2 ETH > 1 ETH limit
            data: ""
        }));
        
        // Should emit bypass event for total amount
        vm.expectEmit(true, true, false, true);
        emit LimitBypassed(owner, address(0), 2 ether);
        
        vm.prank(owner);
        account.executeBatch(calls);
        
        // Verify recipients received funds
        assertEq(makeAddr("recipient1").balance, 1 ether);
        assertEq(makeAddr("recipient2").balance, 1 ether);
    }

    function test_ETHLimit_BatchMixed_TokensNotAffected() public {
        address mockToken = makeAddr("mockToken");
        
        // Create batch with ETH and token transfers
        calls.push(SmartAccount.Call({
            target: makeAddr("recipient1"),
            value: 0.9 ether, // Under ETH limit
            data: ""
        }));
        calls.push(SmartAccount.Call({
            target: mockToken,
            value: 0, // No ETH, just token call
            data: abi.encodeWithSelector(0xa9059cbb, makeAddr("recipient2"), 100 ether) // transfer(to, amount)
        }));
        
        // Should succeed - token transfers aren't affected by ETH limits
        vm.prank(owner);
        account.executeBatch(calls);
        
        assertEq(makeAddr("recipient1").balance, 0.9 ether);
    }

    function test_ETHLimit_BatchZeroValue_NoLimitCheck() public {
        // Create batch with only zero-value calls
        calls.push(SmartAccount.Call({
            target: makeAddr("contract1"),
            value: 0,
            data: abi.encodeWithSelector(bytes4(keccak256("someFunction()")))
        }));
        calls.push(SmartAccount.Call({
            target: makeAddr("contract2"),
            value: 0,
            data: abi.encodeWithSelector(bytes4(keccak256("anotherFunction()")))
        }));
        
        // Should succeed without limit checks
        vm.prank(owner);
        account.executeBatch(calls);
    }

    function test_ETHLimit_BatchAfterSingleSpend_CumulativeLimit() public {
        // First spend some ETH with single call
        vm.prank(owner);
        account.execute(makeAddr("recipient0"), 0.4 ether, "");
        
        // Create batch that would exceed remaining limit
        calls.push(SmartAccount.Call({
            target: makeAddr("recipient1"),
            value: 0.4 ether,
            data: ""
        }));
        calls.push(SmartAccount.Call({
            target: makeAddr("recipient2"),
            value: 0.3 ether, // 0.4 + 0.4 + 0.3 = 1.1 > 1.0 limit
            data: ""
        }));
        
        // Should fail due to cumulative limit
        vm.expectRevert(SpendingLimitExceeded.selector);
        vm.prank(owner);
        account.executeBatch(calls);
    }
}
