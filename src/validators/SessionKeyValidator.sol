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

    event SessionGranted(address indexed key, uint64 expiry);
    event SessionRevoked(address indexed key);
    event SelectorAllowed(address indexed key, bytes4 indexed sel, bool allowed);
    
    // AUDITOR REQUIRED: Security events for future session key caps
    event CapExceeded(address indexed key, uint256 attempted, uint256 cap);
    event CapConsumed(address indexed key, uint256 amount, uint256 newTotal);
    event AllowlistViolation(address indexed key, address indexed target);

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
        // Accept only if signer is an active session key
        (address rec, ECDSA.RecoverError err,) = userOpHash.toEthSignedMessageHash().tryRecover(userOpSignature);
        if (err != ECDSA.RecoverError.NoError) return false;
        uint64 exp = sessionExpiry[rec];
        return exp != 0 && exp > block.timestamp;
    }
}