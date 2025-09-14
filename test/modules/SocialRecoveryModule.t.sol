// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../src/modules/SocialRecoveryModule.sol";
import "../../src/SmartAccount.sol";

contract SocialRecoveryModuleTest is Test {
    SocialRecoveryModule public recoveryModule;
    SmartAccount public account;
    
    address public owner = address(0x1);
    address public guardian1 = address(0x2);
    address public guardian2 = address(0x3);
    address public guardian3 = address(0x4);
    address public newOwner = address(0x5);
    address public attacker = address(0x666);
    
    event GuardianAdded(address indexed guardian);
    event RecoveryInitiated(address indexed newOwner, address indexed initiator, uint256 nonce);
    
    function setUp() public {
        // Deploy smart account
        vm.prank(owner);
        account = new SmartAccount(owner);
        
        // Deploy recovery module
        vm.prank(owner);
        recoveryModule = new SocialRecoveryModule(address(account));
        
        // Add recovery module to account
        vm.prank(owner);
        account.addModule(address(recoveryModule));
    }
    
    function testAddGuardian() public {
        vm.startPrank(address(account));
        
        vm.expectEmit(true, false, false, true);
        emit GuardianAdded(guardian1);
        
        recoveryModule.addGuardian(guardian1);
        
        assertTrue(recoveryModule.isGuardian(guardian1));
        assertEq(recoveryModule.guardianCount(), 1);
        assertEq(recoveryModule.threshold(), 1);
        
        vm.stopPrank();
    }
    
    function testInitiateRecovery() public {
        // Setup guardians
        vm.prank(address(account));
        recoveryModule.addGuardian(guardian1);
        
        // Initiate recovery
        vm.expectEmit(true, true, false, true);
        emit RecoveryInitiated(newOwner, guardian1, 1);
        
        vm.prank(guardian1);
        recoveryModule.initiateRecovery(newOwner);
        
        (
            address recoveryOwner,
            uint256 approvalCount,
            uint256 timestamp,
            bool executable
        ) = recoveryModule.getRecoveryRequest();
        
        assertEq(recoveryOwner, newOwner);
        assertEq(approvalCount, 1);
        assertEq(timestamp, block.timestamp);
        assertFalse(executable); // Timelock not expired
    }
}