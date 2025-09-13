// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {SmartAccount} from "../src/SmartAccount.sol";
import {Counter} from "../src/Counter.sol";

contract SmartAccountTest is Test {
    SmartAccount public account;
    Counter public counter;
    
    address public owner;
    uint256 public ownerPrivateKey;
    address public notOwner;
    uint256 public notOwnerPrivateKey;
    
    // Events to test
    event Executed(address indexed target, uint256 value, bytes data, bytes result);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event EntryPointSet(address indexed entryPoint);

    function setUp() public {
        // Setup owner with known private key for testing
        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);
        
        // Setup non-owner
        notOwnerPrivateKey = 0xB0B;
        notOwner = vm.addr(notOwnerPrivateKey);
        
        // Deploy contracts
        account = new SmartAccount(owner);
        counter = new Counter();
        
        // Fund the account
        vm.deal(address(account), 10 ether);
    }

    function testConstructor() public view {
        assertEq(account.owner(), owner);
        assertEq(account.entryPoint(), address(0));
    }

    function testConstructorRevertsZeroOwner() public {
        vm.expectRevert("zero owner");
        new SmartAccount(address(0));
    }

    function testOwnerCanExecute() public {
        bytes memory data = abi.encodeWithSelector(Counter.inc.selector, 5);
        
        vm.prank(owner);
        bytes memory result = account.execute(address(counter), 0, data);
        
        assertEq(counter.value(), 5);
        assertEq(result.length, 0);
    }

    function testNonOwnerCannotExecute() public {
        bytes memory data = abi.encodeWithSelector(Counter.inc.selector, 1);
        
        vm.prank(notOwner);
        vm.expectRevert("not allowed");
        account.execute(address(counter), 0, data);
    }

    function testEntryPointCanExecute() public {
        address entryPoint = address(0x1234);
        
        // Set entry point
        vm.prank(owner);
        account.setEntryPoint(entryPoint);
        
        // Execute from entry point
        bytes memory data = abi.encodeWithSelector(Counter.inc.selector, 3);
        vm.prank(entryPoint);
        account.execute(address(counter), 0, data);
        
        assertEq(counter.value(), 3);
    }

    function testExecuteRevertsZeroTarget() public {
        vm.prank(owner);
        vm.expectRevert("zero target");
        account.execute(address(0), 0, "");
    }

    function testExecuteWithValue() public {
        // Deploy a contract that can receive ETH
        address payable receiver = payable(address(new Counter()));
        uint256 sendValue = 1 ether;
        
        uint256 receiverBalanceBefore = receiver.balance;
        
        vm.prank(owner);
        account.execute(receiver, sendValue, "");
        
        assertEq(receiver.balance, receiverBalanceBefore + sendValue);
    }

    function testTransferOwnership() public {
        address newOwner = address(0xBEEF);
        
        vm.expectEmit(true, true, false, true, address(account));
        emit OwnerChanged(owner, newOwner);
        
        vm.prank(owner);
        account.transferOwnership(newOwner);
        
        assertEq(account.owner(), newOwner);
        
        // Old owner cannot execute anymore
        bytes memory data = abi.encodeWithSelector(Counter.inc.selector, 1);
        vm.prank(owner);
        vm.expectRevert("not allowed");
        account.execute(address(counter), 0, data);
        
        // New owner can execute
        vm.prank(newOwner);
        account.execute(address(counter), 0, data);
        assertEq(counter.value(), 1);
    }

    function testTransferOwnershipRevertsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("zero owner");
        account.transferOwnership(address(0));
    }

    function testOnlyOwnerCanTransferOwnership() public {
        vm.prank(notOwner);
        vm.expectRevert("not owner");
        account.transferOwnership(address(0xBEEF));
    }

    function testSetEntryPoint() public {
        address entryPoint = address(0x5678);
        
        vm.expectEmit(true, false, false, true, address(account));
        emit EntryPointSet(entryPoint);
        
        vm.prank(owner);
        account.setEntryPoint(entryPoint);
        
        assertEq(account.entryPoint(), entryPoint);
    }

    function testSetEntryPointRevertsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("zero entry");
        account.setEntryPoint(address(0));
    }

    function testOnlyOwnerCanSetEntryPoint() public {
        vm.prank(notOwner);
        vm.expectRevert("not owner");
        account.setEntryPoint(address(0x5678));
    }

    function testReceiveETH() public {
        uint256 sendAmount = 1 ether;
        uint256 balanceBefore = address(account).balance;
        
        (bool success, ) = address(account).call{value: sendAmount}("");
        assertTrue(success);
        
        assertEq(address(account).balance, balanceBefore + sendAmount);
    }
}