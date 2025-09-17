# Vaultum Smart Account V1 Scope

## ✅ Included in V1

### Core Security Features
- **Social Recovery Module**
  - Guardian management with 3-day activation delay
  - Multi-signature recovery with configurable threshold
  - 48-hour timelock for recovery execution
  - Recovery can be re-initiated after execution
  - Guardian changes blocked during active recovery

- **Session Keys**
  - Time-bound session key grants
  - Selector-based function allowlists
  - Full ERC-4337 UserOp support with selector validation
  - Revocation support

- **Spending Limits**
  - Per-token daily spending caps (ERC-20)
  - 24-hour rolling windows
  - Automatic window rollover
  - Support for tokens with different decimals

### ERC-4337 Account Abstraction
- Full EntryPoint compatibility
- Signature validation for UserOperations
- Support for multiple validators
- ERC-1271 smart contract signatures

## 📝 Explicitly Out of Scope for V1

### Spending Limits
- **ETH spending caps** - Only ERC-20 tokens supported
- **Owner bypass events** - Owner naturally bypasses all module restrictions

### Session Keys
- **Per-session spending caps** - Deferred to V2
- **Session key scopes/presets** - Deferred to V2

### Nice to Have (V2)
- Configurable guardian activation delay
- Export guardian set and recovery logs as JSON
- ETH spending limit support
- Session key spending limits
- Session key scope presets

## 🔒 Security Model

### Assumptions
- Account must maintain sufficient EntryPoint deposit (`missingFunds == 0`)
- Owner has full control and bypasses all module restrictions
- Modules cannot prevent owner from executing transactions
- Recovery requires both guardian approval AND timelock

### Invariants
- Only one active recovery at a time
- Owner cannot change without guardian approvals + timelock
- Threshold must be within bounds (1 <= threshold <= guardianCount)
- Session keys cannot call restricted functions via UserOps

## 📊 Gas Costs
See `.gas-snapshot` for detailed gas consumption metrics.

## 🚀 Ready for Production
All critical security issues have been addressed:
- ✅ Session key selector bypass (FIXED)
- ✅ Social recovery re-initiation (FIXED)  
- ✅ Guardian activation during recovery (FIXED)

The contract is ready for:
- Testnet deployment
- Security audit
- Production deployment
