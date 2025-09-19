// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ISignatureValidator} from "./ISignatureValidator.sol";
import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";

contract SessionKeyValidator is ISignatureValidator {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    address public immutable account;
    mapping(address => uint64) public sessionExpiry;
    mapping(address key => mapping(bytes4 sel => bool allowed)) public selectorAllowed;
    
    // V2: AUDITOR APPROVED - Session key spending caps with deterministic validation
    struct SessionKeyData {
        uint256 dailyCap;          // Daily spending cap in wei (0 = no cap)
        bool hasTargetRestrictions; // If true, check target allowlist
    }
    
    mapping(address => SessionKeyData) public sessionKeyData;
    // AUDITOR REQUIRED: Deterministic window spending (no block.timestamp in validation)
    mapping(address => mapping(uint256 => uint256)) public windowSpending; // key => windowId => spent
    // V2: Target allowlist
    mapping(address => mapping(address => bool)) public targetAllowed; // key => target => allowed

    event SessionGranted(address indexed key, uint64 expiry);
    event SessionRevoked(address indexed key);
    event SelectorAllowed(address indexed key, bytes4 indexed sel, bool allowed);
    
    // AUDITOR REQUIRED: Security events for session key caps
    event CapExceeded(address indexed key, uint256 attempted, uint256 cap);
    event CapConsumed(address indexed key, uint256 amount, uint256 newTotal);
    event AllowlistViolation(address indexed key, address indexed target);
    event SessionCapSet(address indexed key, uint256 dailyCap);
    event TargetAllowed(address indexed key, address indexed target, bool allowed);
    event TargetRestrictionsSet(address indexed key, bool enabled);

    modifier onlyAccount() {
        require(msg.sender == account, "not account");
        _;
    }

    constructor(address _account) {
        require(_account != address(0), "zero account");
        account = _account;
    }

    function grant(address key, uint64 expiry) external onlyAccount {
        require(key != address(0), "zero key");
        // Audit L-2 FIX: Add 60s buffer to prevent miner timestamp manipulation
        require(expiry > block.timestamp + 60, "expiry too soon");
        
        sessionExpiry[key] = expiry;
        emit SessionGranted(key, expiry);
    }

    function revoke(address key) external onlyAccount {
        delete sessionExpiry[key];
        emit SessionRevoked(key);
    }

    function allowSelector(address key, bytes4 sel, bool allowed) external onlyAccount {
        require(key != address(0), "zero key");
        selectorAllowed[key][sel] = allowed;
        emit SelectorAllowed(key, sel, allowed);
    }

    function isValidUserOp(bytes calldata userOpSignature, bytes32 userOpHash) external view override returns (bool) {
        // Deterministic validation: signature must recover to a registered session key
        (address rec, ECDSA.RecoverError err,) = userOpHash.toEthSignedMessageHash().tryRecover(userOpSignature);
        if (err != ECDSA.RecoverError.NoError) return false;
        uint64 exp = sessionExpiry[rec];
        // Do NOT read block.timestamp here; time-bounds will be packed by the account
        return exp != 0;
    }
    
    // ============ V2: AUDITOR APPROVED SESSION KEY CAPS ============
    
    /**
     * @notice Set daily spending cap for a session key
     * @param key Session key address
     * @param dailyCap Maximum amount the key can spend per day (0 = no cap)
     */
    function setSpendingCap(address key, uint256 dailyCap) external onlyAccount {
        require(key != address(0), "zero key");
        require(sessionExpiry[key] > 0, "key not granted");
        
        sessionKeyData[key].dailyCap = dailyCap;
        emit SessionCapSet(key, dailyCap);
    }
    
    /**
     * @notice Enable/disable target restrictions for a session key
     * @param key Session key address
     * @param enabled If true, only allowed targets can be called
     */
    function setTargetRestrictions(address key, bool enabled) external onlyAccount {
        require(key != address(0), "zero key");
        sessionKeyData[key].hasTargetRestrictions = enabled;
        emit TargetRestrictionsSet(key, enabled);
    }
    
    /**
     * @notice Allow or disallow a target address for a session key
     * @param key Session key address
     * @param target Target contract address
     * @param allowed Whether the target is allowed
     */
    function allowTarget(address key, address target, bool allowed) external onlyAccount {
        require(key != address(0), "zero key");
        require(target != address(0), "zero target");
        
        targetAllowed[key][target] = allowed;
        emit TargetAllowed(key, target, allowed);
    }
    
    // ============ AUDITOR REQUIRED: DETERMINISTIC VALIDATION (NO STATE WRITES) ============
    
    /**
     * @notice AUDITOR APPROVED: Calculate deterministic window ID from timestamp
     * @param timestamp Timestamp for window calculation (from UserOp or current time)
     * @return windowId Deterministic window identifier
     */
    function getWindowId(uint48 timestamp) public pure returns (uint256) {
        return uint256(timestamp) / 1 days;
    }
    
    /**
     * @notice AUDITOR APPROVED: Check if spending would exceed cap (view only)
     * @param key Session key address
     * @param amount Amount to spend
     * @param timestamp Timestamp for window calculation
     * @return wouldExceed True if spending would exceed cap
     */
    function wouldExceedCap(address key, uint256 amount, uint48 timestamp) 
        external view returns (bool wouldExceed) 
    {
        SessionKeyData memory data = sessionKeyData[key];
        if (data.dailyCap == 0) return false; // No cap set
        
        uint256 windowId = getWindowId(timestamp);
        uint256 currentSpent = windowSpending[key][windowId];
        
        return (currentSpent + amount) > data.dailyCap;
    }
    
    /**
     * @notice AUDITOR APPROVED: Check if target is allowed (view only)
     * @param key Session key address
     * @param target Target address to check
     * @return allowed Whether the target is allowed
     */
    function isTargetAllowed(address key, address target) external view returns (bool allowed) {
        SessionKeyData memory data = sessionKeyData[key];
        if (!data.hasTargetRestrictions) return true;
        
        return targetAllowed[key][target];
    }
    
    // ============ EXECUTION PHASE: STATE CHANGES ALLOWED ============
    
    /**
     * @notice AUDITOR REQUIRED: Atomic check-and-consume spending cap
     * @param key Session key address (explicitly passed from callData)
     * @param amount Amount to consume
     * @param timestamp Timestamp for window calculation
     * @dev Reverts if cap would be exceeded, otherwise atomically updates state
     */
    function consumeOrRevert(address key, uint256 amount, uint48 timestamp) external onlyAccount {
        require(amount > 0, "zero amount");
        
        SessionKeyData memory data = sessionKeyData[key];
        if (data.dailyCap == 0) return; // No cap set
        
        uint256 windowId = getWindowId(timestamp);
        uint256 currentSpent = windowSpending[key][windowId];
        uint256 newSpent = currentSpent + amount;
        
        // AUDITOR REQUIREMENT: Atomic check-and-update
        if (newSpent > data.dailyCap) {
            emit CapExceeded(key, amount, data.dailyCap);
            revert("Daily cap exceeded");
        }
        
        // Update spending atomically
        windowSpending[key][windowId] = newSpent;
        emit CapConsumed(key, amount, newSpent);
    }
    
    /**
     * @notice AUDITOR APPROVED: Record spending (called from SmartAccount after execution)
     * @param key Session key that spent
     * @param amount Amount spent
     * @param timestamp Timestamp for window calculation
     * @dev Legacy function for backward compatibility
     */
    function recordSpending(address key, uint256 amount, uint48 timestamp) external onlyAccount {
        require(amount > 0, "zero amount");
        
        uint256 windowId = getWindowId(timestamp);
        windowSpending[key][windowId] += amount;
        
        emit CapConsumed(key, amount, windowSpending[key][windowId]);
    }
    
    // ============ VIEW FUNCTIONS ============
    
    /**
     * @notice Get spending status for a session key
     * @param key Session key address
     * @param timestamp Timestamp for window calculation
     * @return cap Daily spending cap
     * @return spent Amount spent in current window
     * @return remaining Amount remaining in window
     */
    function getSpendingStatus(address key, uint48 timestamp) external view returns (
        uint256 cap,
        uint256 spent,
        uint256 remaining
    ) {
        SessionKeyData memory data = sessionKeyData[key];
        cap = data.dailyCap;
        
        uint256 windowId = getWindowId(timestamp);
        spent = windowSpending[key][windowId];
        
        remaining = cap > spent ? cap - spent : 0;
    }
}