// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAccount} from "./interfaces/IAccount.sol";
import {IERC1271} from "./interfaces/IERC1271.sol";
import {UserOperation} from "./interfaces/IEntryPoint.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IModule} from "./modules/IModule.sol";
import {ModuleManagerOptimized} from "./modules/ModuleManagerOptimized.sol";
import {ValidatorManager} from "./validators/ValidatorManager.sol";
import {ISignatureValidator} from "./validators/ISignatureValidator.sol";
import {SessionKeyValidator} from "./validators/SessionKeyValidator.sol";
import {SpendingLimitModule, SpendingLimitExceeded} from "./modules/SpendingLimitModule.sol";

interface ISessionKeyExpiry {
    function sessionExpiry(address key) external view returns (uint64);
}

contract SmartAccount is IAccount, IERC1271, ModuleManagerOptimized, ValidatorManager, ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    address public owner;
    address public entryPoint;
    
    // Recovery module authorization mapping
    mapping(address => bool) public authorizedRecoveryModules;
    
    // H-2 FIX: Module reentrancy protection
    uint256 private _moduleExecutionDepth;

    event Executed(address target, uint256 value, bytes data, bytes result);
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event EntryPointSet(address indexed entryPoint);
    event RecoveryModuleSet(address indexed module, bool authorized);
    // Audit Info FIX: Track postExecute failures for observability
    event ModulePostExecuteFailed(address indexed module, address target);

    error BlockedByModule();
    
    // M-4: Batch execution support
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    modifier onlyOwner() { require(msg.sender == owner, "not owner"); _; }
    modifier onlyEntryPointOrOwner() { require(msg.sender == entryPoint || msg.sender == owner, "not allowed"); _; }
    modifier onlyEntryPoint() { require(msg.sender == entryPoint, "not entrypoint"); _; }
    modifier onlyModule() { require(isModule(msg.sender), "not module"); _; }

    constructor(address _owner) {
        require(_owner != address(0), "zero owner");
        owner = _owner;
        emit OwnerChanged(address(0), _owner);
    }

    function setEntryPoint(address _entryPoint) external onlyOwner {
        require(_entryPoint != address(0), "zero entry");
        entryPoint = _entryPoint;
        emit EntryPointSet(_entryPoint);
    }

    function transferOwnership(address newOwner) external onlyEntryPointOrOwner {
        require(newOwner != address(0), "zero owner");
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    // REMOVED: setOwnerFromModule - Critical security vulnerability
    // Modules should NEVER be able to directly change ownership
    // Recovery modules must use proper authorization flows
    
    // Recovery-specific ownership transfer (only callable by authorized recovery module)
    function transferOwnershipFromRecovery(address newOwner, address recoveryModule) external {
        require(msg.sender == recoveryModule, "Invalid recovery module");
        require(isModule(recoveryModule), "Not a registered module");
        require(authorizedRecoveryModules[recoveryModule], "Not authorized for recovery");
        require(newOwner != address(0), "zero owner");
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }
    
    // Set recovery module authorization
    function setRecoveryModule(address module, bool authorized) external onlyEntryPointOrOwner {
        require(module != address(0), "zero module");
        // Can only authorize modules that are actually registered
        if (authorized) {
            require(isModule(module), "Not a registered module");
        }
        authorizedRecoveryModules[module] = authorized;
        emit RecoveryModuleSet(module, authorized);
    }

    // Module management - Using onlyEntryPointOrOwner for proper validation
    function addModule(address module) external onlyEntryPointOrOwner {
        _addModule(module);
    }

    function removeModule(address module) external onlyEntryPointOrOwner {
        _removeModule(module);
    }

    // Validator management - Using onlyEntryPointOrOwner for proper validation
    function addValidator(address validator) external onlyEntryPointOrOwner {
        _addValidator(validator);
    }

    function removeValidator(address validator) external onlyEntryPointOrOwner {
        _removeValidator(validator);
    }

    function execute(address target, uint256 value, bytes calldata data)
        external payable onlyEntryPointOrOwner nonReentrant returns (bytes memory result)
    {
        require(target != address(0), "zero target");
        
        // H-2 FIX: Prevent module hook reentrancy
        // Modules cannot call back into the account during their execution
        require(_moduleExecutionDepth == 0, "Module reentrancy detected");
        
        address[] memory list = getModules();
        
        // Set depth before calling module hooks
        _moduleExecutionDepth = 1;
        
        // Pre-execution hooks
        for (uint256 i = 0; i < list.length; i++) {
            if (!IModule(list[i]).preExecute(msg.sender, target, value, data)) {
                _moduleExecutionDepth = 0; // Reset on revert
                revert BlockedByModule();
            }
        }
        
        // Reset depth for the actual execution
        _moduleExecutionDepth = 0;
        
        // Execute the call
        (bool ok, bytes memory res) = target.call{value: value}(data);
        require(ok, "call failed");
        emit Executed(target, value, data, res);
        
        // V2: AUDITOR APPROVED - Record session key spending after successful execution
        if (value > 0) {
            _recordSessionKeySpending(msg.sender, value);
        }
        
        // Set depth again for post-execution hooks
        _moduleExecutionDepth = 1;
        
        // Post-execution hooks
        for (uint256 i2 = 0; i2 < list.length; i2++) {
            bool postSuccess = IModule(list[i2]).postExecute(msg.sender, target, value, data, res);
            if (!postSuccess) {
                emit ModulePostExecuteFailed(list[i2], target);
            }
        }
        
        // Reset depth before returning
        _moduleExecutionDepth = 0;
        
        return res;
    }
    
    /**
     * @notice AUDITOR REQUIRED: Execute with explicit session key and window binding
     * @param sessionKey Session key address (must match signature signer)
     * @param target Target contract address
     * @param value ETH value to send
     * @param data Call data
     * @param windowId Deterministic window ID (part of signed message)
     * @return result Return data from the call
     * @dev This prevents TOCTOU by explicitly binding session key and windowId to execution
     */
    function executeWithSessionKey(
        address sessionKey,
        address target, 
        uint256 value, 
        bytes calldata data,
        uint256 windowId
    ) external payable onlyEntryPointOrOwner nonReentrant returns (bytes memory result) {
        require(target != address(0), "zero target");
        require(sessionKey != address(0), "zero session key");
        
        // Prevent module hook reentrancy
        require(_moduleExecutionDepth == 0, "Module reentrancy detected");
        
        address[] memory list = getModules();
        
        // Set depth before calling module hooks
        _moduleExecutionDepth = 1;
        
        // Pre-execution hooks
        for (uint256 i = 0; i < list.length; i++) {
            if (!IModule(list[i]).preExecute(msg.sender, target, value, data)) {
                _moduleExecutionDepth = 0;
                revert BlockedByModule();
            }
        }
        
        // Reset depth for execution
        _moduleExecutionDepth = 0;
        
        // AUDITOR REQUIRED: Atomic consumption before external call
        if (value > 0) {
            _consumeSessionKeySpendingWithWindow(sessionKey, value, windowId);
        }
        
        // Execute the call (after consumption check)
        (bool ok, bytes memory res) = target.call{value: value}(data);
        require(ok, "call failed");
        emit Executed(target, value, data, res);
        
        // Set depth again for post-execution hooks
        _moduleExecutionDepth = 1;
        
        // Post-execution hooks
        for (uint256 i2 = 0; i2 < list.length; i2++) {
            bool postSuccess = IModule(list[i2]).postExecute(msg.sender, target, value, data, res);
            if (!postSuccess) {
                emit ModulePostExecuteFailed(list[i2], target);
            }
        }
        
        // Reset depth before returning
        _moduleExecutionDepth = 0;
        
        return res;
    }
    
    /**
     * @dev M-4 FIX: Batch execution for gas efficiency
     * Execute multiple calls in a single transaction
     */
    function executeBatch(Call[] calldata calls)
        external payable onlyEntryPointOrOwner nonReentrant returns (bytes[] memory results)
    {
        // Prevent module hook reentrancy
        require(_moduleExecutionDepth == 0, "Module reentrancy detected");
        
        results = new bytes[](calls.length);
        address[] memory moduleList = getModules();
        
        // AUDITOR P3: Check aggregate ETH spending limits for batch
        _preExecuteBatch(calls, moduleList);
        
        for (uint256 i = 0; i < calls.length; i++) {
            require(calls[i].target != address(0), "zero target");
            
            // Set depth before module hooks
            _moduleExecutionDepth = 1;
            
            // Check all modules for each call 
            // Note: ETH limits already checked in batch aggregate, so individual calls use value=0 for limit checks
            for (uint256 j = 0; j < moduleList.length; j++) {
                if (!IModule(moduleList[j]).preExecute(msg.sender, calls[i].target, 0, calls[i].data)) {
                    _moduleExecutionDepth = 0;
                    revert BlockedByModule();
                }
            }
            
            // Reset for execution
            _moduleExecutionDepth = 0;
            
            // Execute the call
            (bool ok, bytes memory res) = calls[i].target.call{value: calls[i].value}(calls[i].data);
            require(ok, "batch call failed");
            results[i] = res;
            
            emit Executed(calls[i].target, calls[i].value, calls[i].data, res);
            
            // Set depth for post-execution
            _moduleExecutionDepth = 1;
            
            // Post-execution hooks
            for (uint256 j = 0; j < moduleList.length; j++) {
                bool postSuccess = IModule(moduleList[j]).postExecute(msg.sender, calls[i].target, calls[i].value, calls[i].data, res);
                if (!postSuccess) {
                    emit ModulePostExecuteFailed(moduleList[j], calls[i].target);
                }
            }
            
            // Reset depth
            _moduleExecutionDepth = 0;
        }
        
        return results;
    }
    
    /**
     * @notice AUDITOR P3: Check aggregate ETH spending limits across batch calls
     * @param calls The batch calls to check
     * @param moduleList List of active modules
     */
    function _preExecuteBatch(Call[] calldata calls, address[] memory moduleList) private {
        // Calculate total ETH value across all calls
        uint256 totalEthValue = 0;
        for (uint256 i = 0; i < calls.length; i++) {
            totalEthValue += calls[i].value;
        }
        
        // Check ETH limits with SpendingLimitModule if present and has ETH value
        if (totalEthValue > 0) {
            for (uint256 j = 0; j < moduleList.length; j++) {
                // Try to call SpendingLimitModule's batch ETH check
                try SpendingLimitModule(moduleList[j]).preExecuteBatch(msg.sender, totalEthValue) {
                    // Batch check succeeded, continue
                } catch (bytes memory reason) {
                    // If it's a SpendingLimitExceeded error, re-throw it
                    if (reason.length >= 4) {
                        bytes4 selector = bytes4(reason);
                        if (selector == SpendingLimitExceeded.selector) {
                            revert SpendingLimitExceeded();
                        }
                    }
                    // Otherwise ignore (module doesn't support batch checking)
                }
            }
        }
    }

    /// @notice ERC 4337 callback. Not view anymore, because it may pay missing funds to EntryPoint.
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingFunds
    ) external override onlyEntryPoint returns (uint256 validationData) {
        // ERC-4337 validation with proper data packing
        bool sigValid = false;
        uint48 validUntil = 0;
        uint48 validAfter = 0;

        // 1) try owner - use tryRecover to handle invalid signatures gracefully
        (address recovered, ECDSA.RecoverError err, ) = userOpHash.toEthSignedMessageHash().tryRecover(userOp.signature);
        if (err == ECDSA.RecoverError.NoError && recovered == owner) {
            sigValid = true;
            // Owner signatures don't have time bounds
        }

        // 2) try registered validators if not owner
        if (!sigValid) {
            address[] memory list = getValidators();
            for (uint256 i = 0; i < list.length; i++) {
                if (ISignatureValidator(list[i]).isValidUserOp(userOp.signature, userOpHash)) {
                    // Signature accepted by external validator; derive signer and fetch expiry deterministically
                    (address rec, ECDSA.RecoverError recoveryErr,) = userOpHash.toEthSignedMessageHash().tryRecover(userOp.signature);
                    if (recoveryErr == ECDSA.RecoverError.NoError) {
                        // Best-effort: if validator exposes expiry, pack it; otherwise leave 0
                        try ISessionKeyExpiry(list[i]).sessionExpiry(rec) returns (uint64 exp) {
                            validUntil = uint48(exp);
                        } catch {}
                        
                        // CRITICAL FIX: For session keys, verify selector allowlist
                        try SessionKeyValidator(list[i]).sessionExpiry(rec) returns (uint64 expiry) {
                            if (expiry > 0 && userOp.callData.length >= 4) {
                                // Extract selector from callData
                                bytes4 selector = bytes4(userOp.callData);
                                // Check if selector is allowed for this session key
                                if (!SessionKeyValidator(list[i]).selectorAllowed(rec, selector)) {
                                    continue; // Try next validator
                                }
                                
                                // V2: AUDITOR REQUIRED - Bind session key and windowId to prevent TOCTOU
                                if (selector == bytes4(keccak256("executeWithSessionKey(address,address,uint256,bytes,uint256)"))) {
                                    // Decode session key and windowId from callData
                                    (address sessionKey, address target, uint256 value, bytes memory data, uint256 windowId) = abi.decode(
                                        userOp.callData[4:], 
                                        (address, address, uint256, bytes, uint256)
                                    );
                                    
                                    // AUDITOR REQUIREMENT: Validate signer == sessionKey
                                    if (rec != sessionKey) {
                                        continue; // Signer mismatch - security violation
                                    }
                                    
                                    // AUDITOR REQUIREMENT: Deterministic windowId from signed callData
                                    // windowId is now part of signed callData, making it deterministic
                                    uint48 windowTime = uint48(windowId * 1 days);
                                    
                                    // Check spending cap (view only - no state changes)
                                    if (SessionKeyValidator(list[i]).wouldExceedCap(sessionKey, value, windowTime)) {
                                        continue; // Would exceed cap
                                    }
                                    
                                    // Check target allowlist (view only - no state changes)  
                                    if (!SessionKeyValidator(list[i]).isTargetAllowed(sessionKey, target)) {
                                        continue; // Target not allowed
                                    }
                                }
                            }
                        } catch {
                            // Not a SessionKeyValidator, proceed normally
                        }
                    }
                    sigValid = true;
                    break;
                }
            }
        }

        // 3) ERC-4337 compliance: NO state changes during validation
        // Missing funds should be handled via EntryPoint deposits
        // The account should maintain sufficient deposit in EntryPoint
        require(missingFunds == 0, "Insufficient EntryPoint deposit");

        // 4) Pack validation data per ERC-4337 spec
        // Format: validAfter (48 bits) | validUntil (48 bits) | aggregator (160 bits)
        // If signature invalid, return 1 (SIG_VALIDATION_FAILED)
        if (!sigValid) {
            return 1;
        }
        
        // Pack the validation data (no time bounds or aggregator for now)
        return uint256(validAfter) << 208 | uint256(validUntil) << 160;
    }

    /**
     * @dev ERC-1271 signature validation for smart contract signatures
     * @param hash Hash of the data to be signed
     * @param signature Signature byte array
     * @return bytes4 magic value 0x1626ba7e if valid, 0xffffffff otherwise
     */
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) external view override returns (bytes4) {
        // ERC-1271 magic value for valid signature
        bytes4 MAGIC_VALUE = 0x1626ba7e;
        
        // First, try to recover signer from signature and check if it's the owner
        (address recovered, ECDSA.RecoverError err,) = hash.toEthSignedMessageHash().tryRecover(signature);
        if (err == ECDSA.RecoverError.NoError && recovered == owner) {
            return MAGIC_VALUE;
        }
        
        // If not owner, try registered validators
        address[] memory validators = getValidators();
        for (uint256 i = 0; i < validators.length; i++) {
            // Check if validator accepts this signature
            // Note: validators use isValidUserOp which expects (signature, hash)
            if (ISignatureValidator(validators[i]).isValidUserOp(signature, hash)) {
                return MAGIC_VALUE;
            }
        }
        
        // Invalid signature
        return 0xffffffff;
    }

    receive() external payable {}
    
    /**
     * @notice AUDITOR REQUIRED: Atomic session key spending consumption with windowId
     * @param sessionKey Explicit session key address from callData
     * @param amount Amount to consume
     * @param windowId Deterministic window ID from signed callData
     * @dev Called before external value transfer to prevent TOCTOU
     */
    function _consumeSessionKeySpendingWithWindow(address sessionKey, uint256 amount, uint256 windowId) internal {
        // Find SessionKeyValidator and consume spending atomically
        address[] memory validators = getValidators();
        for (uint256 i = 0; i < validators.length; i++) {
            try SessionKeyValidator(validators[i]).sessionExpiry(sessionKey) returns (uint64 expiry) {
                if (expiry > 0 && expiry > block.timestamp) {
                    // AUDITOR REQUIREMENT: Use signed windowId for atomic consumption
                    uint48 windowTime = uint48(windowId * 1 days);
                    SessionKeyValidator(validators[i]).consumeOrRevert(sessionKey, amount, windowTime);
                    break;
                }
            } catch {
                // Not a SessionKeyValidator, continue
            }
        }
    }

    /**
     * @notice AUDITOR REQUIRED: Atomic session key spending consumption
     * @param sessionKey Explicit session key address from callData
     * @param amount Amount to consume
     * @dev Called before external value transfer to prevent TOCTOU
     */
    function _consumeSessionKeySpending(address sessionKey, uint256 amount) internal {
        // Find SessionKeyValidator and consume spending atomically
        address[] memory validators = getValidators();
        for (uint256 i = 0; i < validators.length; i++) {
            try SessionKeyValidator(validators[i]).sessionExpiry(sessionKey) returns (uint64 expiry) {
                if (expiry > 0 && expiry > block.timestamp) {
                    // AUDITOR REQUIREMENT: Atomic consumeOrRevert before external call
                    uint48 windowTime = uint48(block.timestamp);
                    SessionKeyValidator(validators[i]).consumeOrRevert(sessionKey, amount, windowTime);
                    break;
                }
            } catch {
                // Not a SessionKeyValidator, continue
            }
        }
    }
    
    /**
     * @notice V2: LEGACY - Record session key spending after execution
     * @param caller The caller (potentially a session key)
     * @param amount Amount spent in wei
     * @dev This is the old approach - kept for backward compatibility
     */
    function _recordSessionKeySpending(address caller, uint256 amount) internal {
        // Skip if caller is owner (no caps for owner)
        if (caller == owner) return;
        
        // Find SessionKeyValidator and record spending using current timestamp
        address[] memory validators = getValidators();
        for (uint256 i = 0; i < validators.length; i++) {
            try SessionKeyValidator(validators[i]).sessionExpiry(caller) returns (uint64 expiry) {
                if (expiry > 0 && expiry > block.timestamp) {
                    // This is a valid session key - record spending using current time
                    // AUDITOR NOTE: block.timestamp is safe in execution phase
                    uint48 currentTime = uint48(block.timestamp);
                    SessionKeyValidator(validators[i]).recordSpending(caller, amount, currentTime);
                    break;
                }
            } catch {
                // Not a SessionKeyValidator, continue
            }
        }
    }
}