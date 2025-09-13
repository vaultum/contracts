// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {SmartAccount} from "../../src/SmartAccount.sol";
import {SocialRecoveryModule} from "../../src/modules/SocialRecoveryModule.sol";

contract SocialRecoveryModuleTest is Test {
    SmartAccount acc;
    SocialRecoveryModule module;
    address owner;
    address g1;
    address g2;
    address g3;

    function setUp() public {
        owner = address(0xA11CE);
        g1 = address(0x1);
        g2 = address(0x2);
        g3 = address(0x3);
        acc = new SmartAccount(owner);

        address[] memory guards = new address[](3);
        guards[0] = g1; 
        guards[1] = g2; 
        guards[2] = g3;

        module = new SocialRecoveryModule(address(acc), guards, 2, 1 days);

        vm.prank(owner);
        acc.addModule(address(module));
    }

    function testRecoveryFlow() public {
        // g1 proposes new owner
        address newOwner = address(0xB0B);
        vm.prank(g1);
        module.propose(newOwner);

        // g2 approves
        vm.prank(g2);
        module.approve();

        // before timelock, cannot execute
        vm.prank(g1);
        vm.expectRevert(bytes("timelock"));
        module.execute();

        // warp past timelock
        vm.warp(block.timestamp + 1 days);

        // execute, owner should change
        vm.prank(g1);
        module.execute();
        
        // verify owner changed
        assertEq(acc.owner(), newOwner);
    }

    function testGuardianSetup() public {
        assertTrue(module.guardian(g1));
        assertTrue(module.guardian(g2));
        assertTrue(module.guardian(g3));
        assertEq(module.threshold(), 2);
        assertEq(module.timelock(), 1 days);
    }

    function testOnlyGuardianCanPropose() public {
        address notGuardian = address(0x999);
        address newOwner = address(0xB0B);
        
        vm.prank(notGuardian);
        vm.expectRevert(bytes("not guardian"));
        module.propose(newOwner);
    }

    function testThresholdRequired() public {
        address newOwner = address(0xB0B);
        
        // g1 proposes (auto-approves)
        vm.prank(g1);
        module.propose(newOwner);
        
        // warp past timelock
        vm.warp(block.timestamp + 1 days);
        
        // try to execute with only 1 approval (need 2)
        vm.prank(g1);
        vm.expectRevert(bytes("not enough approvals"));
        module.execute();
        
        // g2 approves
        vm.prank(g2);
        module.approve();
        
        // now it should work
        vm.prank(g1);
        module.execute();
        assertEq(acc.owner(), newOwner);
    }

    function testTimelockEnforced() public {
        address newOwner = address(0xB0B);
        
        // g1 proposes and g2 approves
        vm.prank(g1);
        module.propose(newOwner);
        vm.prank(g2);
        module.approve();
        
        // try to execute immediately
        vm.prank(g1);
        vm.expectRevert(bytes("timelock"));
        module.execute();
        
        // warp halfway
        vm.warp(block.timestamp + 12 hours);
        vm.prank(g1);
        vm.expectRevert(bytes("timelock"));
        module.execute();
        
        // warp past timelock
        vm.warp(block.timestamp + 12 hours + 1);
        vm.prank(g1);
        module.execute();
        assertEq(acc.owner(), newOwner);
    }

    function testProposalReset() public {
        address newOwner1 = address(0xB0B);
        address newOwner2 = address(0xC0C);
        
        // g1 proposes first owner
        vm.prank(g1);
        module.propose(newOwner1);
        
        // g2 approves
        vm.prank(g2);
        module.approve();
        
        // g3 proposes different owner (should reset)
        vm.prank(g3);
        module.propose(newOwner2);
        
        // check that proposal was reset
        assertEq(module.pendingOwner(), newOwner2);
        assertEq(module.approvals(), 1); // only g3's auto-approval
    }

    function testCannotProposeZeroAddress() public {
        vm.prank(g1);
        vm.expectRevert(bytes("zero owner"));
        module.propose(address(0));
    }

    function testOnlyAccountCanSetGuardian() public {
        address newGuardian = address(0x999);
        
        // non-owner cannot set guardian
        vm.prank(g1);
        vm.expectRevert(bytes("not account"));
        module.setGuardian(newGuardian, true);
        
        // owner (via account) can set guardian
        vm.prank(owner);
        acc.execute(address(module), 0, abi.encodeWithSelector(module.setGuardian.selector, newGuardian, true));
        
        assertTrue(module.guardian(newGuardian));
    }

    function testOnlyAccountCanSetThreshold() public {
        // non-owner cannot set threshold
        vm.prank(g1);
        vm.expectRevert(bytes("not account"));
        module.setThreshold(3);
        
        // owner (via account) can set threshold
        vm.prank(owner);
        acc.execute(address(module), 0, abi.encodeWithSelector(module.setThreshold.selector, 3));
        
        assertEq(module.threshold(), 3);
    }

    function testOnlyAccountCanSetTimelock() public {
        // non-owner cannot set timelock
        vm.prank(g1);
        vm.expectRevert(bytes("not account"));
        module.setTimelock(2 days);
        
        // owner (via account) can set timelock
        vm.prank(owner);
        acc.execute(address(module), 0, abi.encodeWithSelector(module.setTimelock.selector, 2 days));
        
        assertEq(module.timelock(), 2 days);
    }

    function testCannotExecuteWithoutProposal() public {
        vm.prank(g1);
        vm.expectRevert(bytes("no proposal"));
        module.execute();
    }

    function testCannotApproveWithoutProposal() public {
        vm.prank(g1);
        vm.expectRevert(bytes("no proposal"));
        module.approve();
    }

    function testDoubleApprovalDoesNotCount() public {
        address newOwner = address(0xB0B);
        
        // g1 proposes (auto-approves)
        vm.prank(g1);
        module.propose(newOwner);
        assertEq(module.approvals(), 1);
        
        // g1 approves again
        vm.prank(g1);
        module.approve();
        assertEq(module.approvals(), 1); // still 1
        
        // g2 approves
        vm.prank(g2);
        module.approve();
        assertEq(module.approvals(), 2);
    }

    function testExecutionClearsProposal() public {
        address newOwner = address(0xB0B);
        
        // setup and execute
        vm.prank(g1);
        module.propose(newOwner);
        vm.prank(g2);
        module.approve();
        vm.warp(block.timestamp + 1 days);
        vm.prank(g1);
        module.execute();
        
        // check state is cleared
        assertEq(module.pendingOwner(), address(0));
        assertEq(module.proposedAt(), 0);
        assertEq(module.approvals(), 0);
    }
}
