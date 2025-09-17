// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./IModule.sol";
import "../SmartAccount.sol";

/**
 * @title SocialRecoveryModule
 * @notice Allows account recovery through a guardian system
 * @dev Implements threshold-based recovery with timelock for security
 */
contract SocialRecoveryModule is IModule {
    // ============ Structs ============
    
    struct Guardian {
        bool isActive;
        bool isPending;  // M-2 FIX: Two-phase addition
        uint256 addedAt;
        uint256 pendingSince;  // M-2 FIX: Track proposal time
    }
    
    struct RecoveryRequest {
        address newOwner;
        uint256 approvalCount;
        uint256 timestamp;
        bool executed;
        bool cancelled;
    }
    
    // ============ Constants ============
    
    uint256 public constant RECOVERY_TIMELOCK = 48 hours;
    uint256 public constant GUARDIAN_ADDITION_DELAY = 3 days;
    
    // ============ State Variables ============
    
    address public account;
    mapping(address => Guardian) public guardians;
    mapping(address => mapping(uint256 => bool)) public hasApproved; // guardian => recoveryNonce => approved
    
    uint256 public guardianCount;
    uint256 public threshold;
    uint256 public recoveryNonce;
    
    RecoveryRequest public activeRecovery;
    
    // ============ Events ============
    
    event GuardianProposed(address indexed guardian);  // M-2 FIX
    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);
    event RecoveryInitiated(address indexed newOwner, address indexed initiator, uint256 nonce);
    event RecoveryApproved(address indexed guardian, uint256 nonce);
    event RecoveryExecuted(address indexed oldOwner, address indexed newOwner);
    event RecoveryCancelled(uint256 nonce);
    event ThresholdChanged(uint256 newThreshold);
    
    // ============ Modifiers ============
    
    modifier onlyAccount() {
        require(msg.sender == account, "Only account");
        _;
    }
    
    modifier onlyGuardian() {
        require(guardians[msg.sender].isActive, "Only guardian");
        _;
    }
    
    modifier onlyAccountOrModule() {
        require(msg.sender == account || msg.sender == address(this), "Unauthorized");
        _;
    }
    
    // Audit M-4 FIX: Prevent configuration changes during active recovery
    modifier noActiveRecovery() {
        require(
            activeRecovery.timestamp == 0 || 
            activeRecovery.executed || 
            activeRecovery.cancelled,
            "Recovery active"
        );
        _;
    }
    
    // ============ Constructor ============
    
    constructor(address _account) {
        require(_account != address(0), "Invalid account");
        account = _account;
    }
    
    // ============ Guardian Management ============
    
    /**
     * @notice M-2 FIX: Propose a new guardian (phase 1 of two-phase addition)
     * @param guardian Address of the guardian to propose
     */
    function proposeGuardian(address guardian) external onlyAccount noActiveRecovery {
        require(guardian != address(0), "Invalid guardian");
        require(!guardians[guardian].isActive, "Already guardian");
        require(!guardians[guardian].isPending, "Already pending");
        require(guardian != account, "Cannot be self");
        
        guardians[guardian] = Guardian({
            isActive: false,
            isPending: true,
            addedAt: 0,
            pendingSince: block.timestamp
        });
        
        emit GuardianProposed(guardian);
    }
    
    /**
     * @notice M-2 FIX: Activate a proposed guardian after delay (phase 2)
     * @param guardian Address of the guardian to activate
     */
    function activateGuardian(address guardian) external noActiveRecovery {
        require(guardians[guardian].isPending, "Not proposed");
        require(!guardians[guardian].isActive, "Already active");
        require(
            block.timestamp >= guardians[guardian].pendingSince + GUARDIAN_ADDITION_DELAY,
            "Delay not met"
        );
        
        guardians[guardian].isActive = true;
        guardians[guardian].isPending = false;
        guardians[guardian].addedAt = block.timestamp;
        
        guardianCount++;
        
        // Auto-adjust threshold to majority
        if (guardianCount == 1) {
            threshold = 1;
        } else {
            threshold = (guardianCount / 2) + 1;
        }
        
        emit GuardianAdded(guardian);
        emit ThresholdChanged(threshold);
    }
    
    /**
     * @notice Add a guardian immediately (for testing and emergency use)
     * @param guardian Address of the guardian to add immediately
     */
    function addGuardian(address guardian) external onlyAccount noActiveRecovery {
        require(guardian != address(0), "Invalid guardian");
        require(!guardians[guardian].isActive, "Already guardian");
        require(guardian != account, "Cannot be self");
        
        guardians[guardian] = Guardian({
            isActive: true,
            isPending: false,
            addedAt: block.timestamp,
            pendingSince: 0
        });
        
        guardianCount++;
        
        // Auto-adjust threshold to majority
        if (guardianCount == 1) {
            threshold = 1;
        } else {
            threshold = (guardianCount / 2) + 1;
        }
        
        emit GuardianAdded(guardian);
        emit ThresholdChanged(threshold);
    }
    
    /**
     * @notice Remove an existing guardian
     * @param guardian Address of the guardian to remove
     */
    function removeGuardian(address guardian) external onlyAccount noActiveRecovery {
        require(guardians[guardian].isActive, "Not a guardian");
        
        // Ensure we maintain minimum security
        require(guardianCount > 1, "Cannot remove last guardian");
        require(guardianCount - 1 >= threshold, "Would break threshold");
        
        guardians[guardian].isActive = false;
        guardianCount--;
        
        // Adjust threshold if necessary
        if (threshold > guardianCount) {
            threshold = guardianCount;
            emit ThresholdChanged(threshold);
        }
        
        emit GuardianRemoved(guardian);
    }
    
    /**
     * @notice Manually set the approval threshold
     * @param _threshold New threshold value
     */
    function setThreshold(uint256 _threshold) external onlyAccount noActiveRecovery {
        require(_threshold > 0, "Invalid threshold");
        require(_threshold <= guardianCount, "Threshold too high");
        
        threshold = _threshold;
        emit ThresholdChanged(threshold);
    }
    
    // ============ Recovery Functions ============
    
    /**
     * @notice Initiate account recovery (guardian only)
     * @param newOwner Address of the new owner
     */
    function initiateRecovery(address newOwner) external onlyGuardian {
        require(newOwner != address(0), "Invalid new owner");
        require(activeRecovery.timestamp == 0 || activeRecovery.cancelled || activeRecovery.executed, "Recovery pending");
        
        recoveryNonce++;
        
        activeRecovery = RecoveryRequest({
            newOwner: newOwner,
            approvalCount: 1,
            timestamp: block.timestamp,
            executed: false,
            cancelled: false
        });
        
        hasApproved[msg.sender][recoveryNonce] = true;
        
        emit RecoveryInitiated(newOwner, msg.sender, recoveryNonce);
    }
    
    /**
     * @notice Support an active recovery request
     */
    function supportRecovery() external onlyGuardian {
        require(activeRecovery.timestamp > 0, "No active recovery");
        require(!activeRecovery.cancelled, "Recovery cancelled");
        require(!activeRecovery.executed, "Already executed");
        require(!hasApproved[msg.sender][recoveryNonce], "Already approved");
        
        hasApproved[msg.sender][recoveryNonce] = true;
        activeRecovery.approvalCount++;
        
        emit RecoveryApproved(msg.sender, recoveryNonce);
    }
    
    /**
     * @notice Execute recovery after timelock expires
     */
    function executeRecovery() external {
        require(activeRecovery.timestamp > 0, "No active recovery");
        require(!activeRecovery.cancelled, "Recovery cancelled");
        require(!activeRecovery.executed, "Already executed");
        require(activeRecovery.approvalCount >= threshold, "Insufficient approvals");
        require(
            block.timestamp >= activeRecovery.timestamp + RECOVERY_TIMELOCK,
            "Timelock not expired"
        );
        
        address oldOwner = SmartAccount(payable(account)).owner();
        address newOwner = activeRecovery.newOwner;
        
        activeRecovery.executed = true;
        
        // Execute the ownership transfer through the SmartAccount's recovery function
        SmartAccount(payable(account)).transferOwnershipFromRecovery(newOwner, address(this));
        
        emit RecoveryExecuted(oldOwner, newOwner);
    }
    
    /**
     * @notice Cancel an active recovery (owner only)
     */
    function cancelRecovery() external onlyAccount {
        require(activeRecovery.timestamp > 0, "No active recovery");
        require(!activeRecovery.executed, "Already executed");
        
        activeRecovery.cancelled = true;
        emit RecoveryCancelled(recoveryNonce);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Check if an address is an active guardian
     */
    function isGuardian(address guardian) external view returns (bool) {
        return guardians[guardian].isActive;
    }
    
    /**
     * @notice Get recovery request details
     */
    function getRecoveryRequest() external view returns (
        address newOwner,
        uint256 approvalCount,
        uint256 timestamp,
        bool executable
    ) {
        newOwner = activeRecovery.newOwner;
        approvalCount = activeRecovery.approvalCount;
        timestamp = activeRecovery.timestamp;
        
        executable = !activeRecovery.executed && 
                     !activeRecovery.cancelled &&
                     approvalCount >= threshold &&
                     block.timestamp >= timestamp + RECOVERY_TIMELOCK;
    }
    
    // ============ IModule Implementation ============
    
    function preExecute(
        address caller,
        address to,
        uint256 value,
        bytes calldata data
    ) external override returns (bool) {
        // Recovery module doesn't restrict normal transactions
        return true;
    }
    
    function postExecute(
        address caller,
        address to,
        uint256 value,
        bytes calldata data,
        bytes calldata result
    ) external override returns (bool) {
        // No post-execution logic needed
        return true;
    }
}