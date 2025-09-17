// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IModule} from "./IModule.sol";
import {SmartAccount} from "../SmartAccount.sol";

error SpendingLimitExceeded();

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract SpendingLimitModule is IModule {
    address public immutable account;

    struct Limit {
        uint256 cap;
        uint64 windowStart;
        uint256 spentInWindow;
        uint8 decimals;  // M-3 FIX: Track expected decimals
        bool isNormalized;  // M-3 FIX: Flag if cap is in normalized form
    }

    mapping(address token => Limit) public limits;
    
    // Owner bypass mechanism
    bool public ownerBypassEnabled;
    uint256 public bypassEnabledUntil; // timestamp when bypass expires

    event LimitSet(address indexed token, uint256 cap);
    event Spent(address indexed token, uint256 newSpent);
    event LimitExceeded(address indexed token, uint256 attempted, uint256 cap);
    event LimitBypassed(address indexed owner, address indexed token, uint256 amount);
    event BypassToggled(bool enabled);

    modifier onlyAccount() { require(msg.sender == account, "not account"); _; }

    constructor(address _account) { 
        require(_account != address(0), "zero account"); 
        account = _account; 
    }

    /**
     * @notice M-3 FIX: Set spending limit with decimal awareness
     * @param token Token address (address(0) for ETH)
     * @param cap Spending cap in token units
     * @param decimals Expected decimals for the token (18 for ETH)
     */
    function setLimitWithDecimals(address token, uint256 cap, uint8 decimals) external onlyAccount {
        limits[token].cap = cap;
        limits[token].decimals = decimals;
        limits[token].isNormalized = true;
        // initialize window on first set if not set
        if (limits[token].windowStart == 0) {
            limits[token].windowStart = uint64(block.timestamp);
        }
        emit LimitSet(token, cap);
    }
    
    // Legacy function for backwards compatibility (assumes 18 decimals)
    function setLimit(address token, uint256 cap) external onlyAccount {
        limits[token].cap = cap;
        limits[token].decimals = 18; // Default to 18 decimals
        limits[token].isNormalized = true;
        // initialize window on first set if not set
        if (limits[token].windowStart == 0) {
            limits[token].windowStart = uint64(block.timestamp);
        }
        emit LimitSet(token, cap);
    }

    function _rolloverIfNeeded(Limit storage L) internal {
        if (L.windowStart == 0) {
            L.windowStart = uint64(block.timestamp);
            L.spentInWindow = 0;
            return;
        }
        if (block.timestamp >= L.windowStart + 1 days) {
            L.windowStart = uint64(block.timestamp);
            L.spentInWindow = 0;
        }
    }

    /**
     * @notice Enable owner bypass for a limited time
     * @param duration How long the bypass should be active (max 24 hours)
     */
    function enableOwnerBypass(uint256 duration) external onlyAccount {
        require(duration > 0 && duration <= 24 hours, "Invalid duration");
        ownerBypassEnabled = true;
        bypassEnabledUntil = block.timestamp + duration;
        emit BypassToggled(true);
    }
    
    /**
     * @notice Disable owner bypass immediately
     */
    function disableOwnerBypass() external onlyAccount {
        ownerBypassEnabled = false;
        bypassEnabledUntil = 0;
        emit BypassToggled(false);
    }
    
    /**
     * @notice Check if bypass is currently active
     */
    function isBypassActive() public view returns (bool) {
        return ownerBypassEnabled && block.timestamp <= bypassEnabledUntil;
    }

    function preExecute(address caller, address target, uint256, bytes calldata data) external override returns (bool) {
        // Check if owner bypass is active
        if (isBypassActive() && caller == SmartAccount(payable(account)).owner()) {
            // Extract amount for logging
            if (data.length >= 68) {
                bytes4 selector;
                assembly {
                    selector := calldataload(data.offset)
                }
                
                uint256 amount;
                if (selector == 0xa9059cbb) { // transfer
                    assembly {
                        amount := calldataload(add(data.offset, 36))
                    }
                    emit LimitBypassed(caller, target, amount);
                } else if (selector == 0x23b872dd) { // transferFrom
                    assembly {
                        amount := calldataload(add(data.offset, 68))
                    }
                    emit LimitBypassed(caller, target, amount);
                }
            }
            return true; // Owner bypass active, skip limits
        }
        
        if (data.length < 4) return true;

        bytes4 sel;
        assembly {
            sel := calldataload(data.offset) // first 4 bytes when cast to bytes4
        }

        if (sel == 0xa9059cbb) {
            // transfer(address to, uint256 amount)
            uint256 amount;
            assembly {
                // 4 selector bytes, then first arg at +4..+35, second arg (amount) begins at +36
                amount := calldataload(add(data.offset, 36))
            }
            return _checkAndConsume(target, amount);
        }

        if (sel == 0x23b872dd) {
            // transferFrom(address from, address to, uint256 amount)
            uint256 amount;
            assembly {
                // amount is the third argument, starts at 4 + 32 + 32 = 68
                amount := calldataload(add(data.offset, 68))
            }
            return _checkAndConsume(target, amount);
        }

        return true;
    }

    function _checkAndConsume(address token, uint256 amount) internal returns (bool) {
        Limit storage L = limits[token];
        if (L.cap == 0) return true;
        _rolloverIfNeeded(L);
        unchecked {
            uint256 newSpent = L.spentInWindow + amount;
            if (newSpent > L.cap) {
                emit LimitExceeded(token, newSpent, L.cap);
                revert SpendingLimitExceeded();
            }
            L.spentInWindow = newSpent;
        }
        emit Spent(token, L.spentInWindow);
        return true;
    }

    function postExecute(address, address, uint256, bytes calldata, bytes calldata) external override returns (bool) {
        return true;
    }
}