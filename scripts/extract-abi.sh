#!/bin/bash

# Extract ABIs for npm package
# Run after forge build

set -e

echo "📦 Extracting ABIs for @vaultum/abi package..."

# Create package directory
PACKAGE_DIR="../packages/abi"
mkdir -p $PACKAGE_DIR/contracts
mkdir -p $PACKAGE_DIR/docs
mkdir -p $PACKAGE_DIR/types

# Extract ABIs from forge artifacts
echo "📋 Extracting contract ABIs..."

# Core contracts
jq '.abi' out/SmartAccount.sol/SmartAccount.json > $PACKAGE_DIR/contracts/SmartAccount.json
jq '.abi' out/SocialRecoveryModule.sol/SocialRecoveryModule.json > $PACKAGE_DIR/contracts/SocialRecoveryModule.json
jq '.abi' out/SessionKeyModule.sol/SessionKeyModule.json > $PACKAGE_DIR/contracts/SessionKeyModule.json
jq '.abi' out/SessionKeyValidator.sol/SessionKeyValidator.json > $PACKAGE_DIR/contracts/SessionKeyValidator.json
jq '.abi' out/SpendingLimitModule.sol/SpendingLimitModule.json > $PACKAGE_DIR/contracts/SpendingLimitModule.json

# Extract deployment bytecode for factory use
echo "🔨 Extracting deployment bytecode..."
jq -r '.bytecode.object' out/SmartAccount.sol/SmartAccount.json > $PACKAGE_DIR/contracts/SmartAccount.bytecode
jq -r '.bytecode.object' out/SocialRecoveryModule.sol/SocialRecoveryModule.json > $PACKAGE_DIR/contracts/SocialRecoveryModule.bytecode

# Generate events documentation
echo "📝 Generating events documentation..."
cat > $PACKAGE_DIR/docs/events.md << 'EOF'
# Event Documentation

## SmartAccount Events

### Executed
Emitted when a transaction is executed.
```solidity
event Executed(address target, uint256 value, bytes data, bytes result)
```

### OwnerChanged
Emitted when ownership is transferred.
```solidity
event OwnerChanged(address indexed oldOwner, address indexed newOwner)
```

### ModuleAdded
Emitted when a module is added.
```solidity
event ModuleAdded(address indexed module)
```

### ModuleRemoved
Emitted when a module is removed.
```solidity
event ModuleRemoved(address indexed module)
```

## SocialRecoveryModule Events

### GuardianAdded
Emitted when a guardian is added.
```solidity
event GuardianAdded(address indexed guardian)
```

### RecoveryInitiated
Emitted when recovery is initiated.
```solidity
event RecoveryInitiated(address indexed newOwner, address indexed initiator, uint256 nonce)
```

### RecoveryExecuted
Emitted when recovery is completed.
```solidity
event RecoveryExecuted(address indexed oldOwner, address indexed newOwner)
```

## SessionKeyModule Events

### SessionGranted
Emitted when a session key is granted.
```solidity
event SessionGranted(address indexed key, uint64 expiry)
```

### SessionRevoked
Emitted when a session key is revoked.
```solidity
event SessionRevoked(address indexed key)
```

## SpendingLimitModule Events

### LimitSet
Emitted when a spending limit is set.
```solidity
event LimitSet(address indexed token, uint256 cap)
```
EOF

# Generate error documentation
echo "❌ Generating error documentation..."
cat > $PACKAGE_DIR/docs/errors.md << 'EOF'
# Error Documentation

## Common Errors

### Authorization Errors
- `"not allowed"` - Caller is not authorized for this action
- `"not owner"` - Caller is not the wallet owner
- `"not entrypoint"` - Caller is not the EntryPoint

### Validation Errors
- `"zero address"` - Invalid zero address provided
- `"zero owner"` - Cannot set owner to zero address
- `"Invalid module"` - Module address is invalid

### State Errors
- `"Module reentrancy detected"` - Reentrancy attempt blocked
- `"Insufficient EntryPoint deposit"` - Not enough funds deposited

## Module-Specific Errors

### SocialRecoveryModule
- `"Invalid guardian"` - Guardian address is invalid
- `"Already guardian"` - Address is already a guardian
- `"Not a guardian"` - Caller is not a registered guardian
- `"Recovery pending"` - Another recovery is in progress
- `"No active recovery"` - No recovery to support/execute
- `"Insufficient approvals"` - Threshold not met
- `"Timelock not expired"` - 48-hour delay not passed
- `"Already executed"` - Recovery already completed

### SessionKeyModule
- `"past expiry"` - Session key has expired
- `"zero key"` - Invalid session key address

### SpendingLimitModule
- `"SpendingLimitExceeded()"` - Transaction exceeds limit
EOF

echo "✅ ABI extraction complete!"
echo "📦 Package ready at: $PACKAGE_DIR"
