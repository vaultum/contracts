# 🔒 ABI Freeze - v0.1.0-alpha

**Status**: FROZEN as of September 15, 2025
**Version**: 0.1.0-alpha
**Audit Target**: These ABIs will be submitted for security audit

## 📋 Frozen Contracts & Features

### 1. SmartAccount.sol
**Core Functions:**
```solidity
function execute(address target, uint256 value, bytes calldata data) external payable
function executeBatch(Call[] calldata calls) external payable
function validateUserOp(UserOperation calldata, bytes32, uint256) external
function isValidSignature(bytes32 hash, bytes calldata signature) external view
function transferOwnership(address newOwner) external
function setRecoveryModule(address module, bool authorized) external
function addModule(address module) external
function removeModule(address module) external
```

**Events:**
```solidity
event Executed(address target, uint256 value, bytes data, bytes result)
event OwnerChanged(address indexed oldOwner, address indexed newOwner)
event ModuleAdded(address indexed module)
event ModuleRemoved(address indexed module)
event RecoveryModuleSet(address indexed module, bool authorized)
```

**Revert Reasons:**
- `"not allowed"` - Caller not authorized
- `"zero owner"` - Invalid owner address
- `"Module reentrancy detected"` - Reentrancy protection
- `"Insufficient EntryPoint deposit"` - Missing funds

### 2. SocialRecoveryModule.sol
**Core Functions:**
```solidity
function addGuardian(address guardian) external
function removeGuardian(address guardian) external  
function initiateRecovery(address newOwner) external
function supportRecovery() external
function executeRecovery() external
function cancelRecovery() external
function getRecoveryRequest() external view returns (address, uint256, uint256, bool)
```

**Events:**
```solidity
event GuardianAdded(address indexed guardian)
event GuardianRemoved(address indexed guardian)
event RecoveryInitiated(address indexed newOwner, address indexed initiator, uint256 nonce)
event RecoveryApproved(address indexed guardian, uint256 nonce)
event RecoveryExecuted(address indexed oldOwner, address indexed newOwner)
event RecoveryCancelled(uint256 nonce)
```

**Revert Reasons:**
- `"Invalid guardian"` - Zero address guardian
- `"Already guardian"` - Duplicate guardian
- `"Not a guardian"` - Unauthorized caller
- `"Recovery pending"` - Existing recovery in progress
- `"Insufficient approvals"` - Threshold not met
- `"Timelock not expired"` - 48-hour delay not passed

### 3. SessionKeyModule.sol
**Core Functions:**
```solidity
function preExecute(address caller, address target, uint256, bytes calldata data) external returns (bool)
function postExecute(address, address, uint256, bytes calldata, bytes calldata) external returns (bool)
```

**Integration with SessionKeyValidator:**
```solidity
function grant(address key, uint64 expiry) external
function revoke(address key) external
function allowSelector(address key, bytes4 sel, bool allowed) external
```

**Events:**
```solidity
event SessionGranted(address indexed key, uint64 expiry)
event SessionRevoked(address indexed key)
event SelectorAllowed(address indexed key, bytes4 indexed sel, bool allowed)
```

### 4. SpendingLimitModule.sol
**Core Functions:**
```solidity
function setLimit(address token, uint256 cap) external
function preExecute(address caller, address target, uint256 value, bytes calldata data) external returns (bool)
```

**Events:**
```solidity
event LimitSet(address indexed token, uint256 cap)
event LimitExceeded(address indexed token, uint256 amount, uint256 limit)
```

## 🔐 Security Properties

### Invariants
1. Only owner or EntryPoint can execute transactions
2. Recovery requires guardian threshold + 48-hour timelock
3. Session keys cannot call the account itself
4. Modules cannot re-enter during execution
5. All signatures are ERC-1271 compliant

### Access Control
- `onlyOwner`: transferOwnership
- `onlyEntryPointOrOwner`: execute, addModule, removeModule
- `onlyAccount`: Module management functions
- `onlyGuardian`: Recovery initiation/support

## 📦 NPM Package Structure

```
@vaultum/abi/
├── contracts/
│   ├── SmartAccount.json
│   ├── SocialRecoveryModule.json
│   ├── SessionKeyModule.json
│   ├── SessionKeyValidator.json
│   └── SpendingLimitModule.json
├── docs/
│   ├── events.md
│   └── errors.md
├── types/
│   └── index.d.ts
├── package.json
└── README.md
```

## ⚠️ Breaking Changes After Freeze

Any changes to these ABIs after freeze will require:
1. Version bump to 0.2.0
2. Migration guide
3. Re-audit of changed functions
4. SDK regeneration
5. App updates

## 🎯 Out of Scope for v0.1.0

These features are NOT included in the freeze:
- Weighted voting for guardians
- Emergency freeze functionality
- Guardian rotation requirements
- Paymaster integration
- Cross-chain messaging

## ✅ Checklist Before Publishing

- [ ] All functions have NatSpec comments
- [ ] All events are indexed appropriately
- [ ] All revert reasons are documented
- [ ] Gas costs are measured and acceptable
- [ ] Fuzz tests pass with 10000+ runs
- [ ] Invariant tests pass
- [ ] Test coverage > 95%

---

**Signed off by**: Vaultum Team
**Date**: September 15, 2025
**Commit Hash**: [TO BE ADDED]
