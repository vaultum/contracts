# Vaultum Smart Contracts

ERC-4337 compliant smart account contracts with modular validation and spending controls.

## Overview

Vaultum implements a flexible smart account system that supports:
- ERC-4337 account abstraction
- Pluggable signature validators
- Modular functionality (session keys, spending limits)
- Cross-chain compatibility

## Architecture

### Core Components

- **SmartAccount**: Main account contract implementing ERC-4337
- **ValidatorManager**: Abstract contract for managing signature validators
- **ModuleManager**: System for pluggable modules with pre/post execution hooks

### Modules

- **SessionKeyModule**: Temporary key delegation with function-level permissions
- **SpendingLimitModule**: Per-token daily spending caps
- **SessionKeyValidator**: ERC-4337 signature validator for session keys

## Signature Validators

The SmartAccount uses a hierarchical validation system for ERC-4337 UserOperations:

1. **Owner Signature Priority**: The account owner's ECDSA signature is always checked first. If valid, the operation proceeds immediately.

2. **Pluggable Validators**: If the owner signature fails, the system iterates through registered validators. Any validator returning `true` will approve the operation.

3. **SessionKeyValidator**: The primary validator implementation manages short-lived session keys:
   - Account owners can grant session keys with specific expiry times
   - Keys can be revoked at any time by the owner
   - Session keys sign the same message hash format as the owner

### Missing Funds Handling

During `validateUserOp`, if the EntryPoint requires additional funds (gas payment):
- The account transfers ETH directly to the EntryPoint
- This is a simplified model for development
- **Production Note**: Real deployments should use the EntryPoint deposit system for gas efficiency

## Usage

### Build

```shell
forge build
```

### Test

```shell
forge test -vv
```

### Deploy

```shell
forge script script/Deploy.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY>
```

## Security Considerations

- Session keys should have short expiry times
- Validators are trusted contracts - only add verified implementations
- The spending limit module currently only checks `transfer()` - `transferFrom()` protection is TODO
- Always audit module interactions before mainnet deployment

## Development

### Environment Setup

1. Install Foundry: https://book.getfoundry.sh/getting-started/installation
2. Install dependencies: `forge install`
3. Run tests: `forge test`

### Testing

Tests are organized by component:
- Core account tests: `test/SmartAccount.t.sol`
- Validator tests: `test/validators/`
- Module tests: `test/modules/`

## License

MIT