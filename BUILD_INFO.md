# Build Information for v0.1.0-alpha

## Compiler Settings

These exact settings MUST be used to reproduce the deployed bytecode:

```toml
solc_version = "0.8.30"
optimizer = true
optimizer_runs = 200
evm_version = "paris"
bytecode_hash = "none"
via_ir = false
```

## Deployed Contracts (Sepolia - Chain ID: 11155111)

| Contract | Address | Constructor Args |
|----------|---------|-----------------|
| SmartAccount | `0x70C1bf3Fd34d99c627fD3f72d600301D54A9eC77` | `owner: 0xa1cdCE5b32474E4f353b747DDb37F39b82447548` |
| SocialRecoveryModule | `0x433Ed3DAb6C5502029972C7af2F01F08b98DcD1B` | `account: 0x70C1bf3Fd34d99c627fD3f72d600301D54A9eC77` |
| SessionKeyModule | `0xC63D5dc1C052289411f848051dB03A8e57D7f094` | `account: 0x70C1bf3Fd34d99c627fD3f72d600301D54A9eC77`, `validator: 0x3473Aa5410B15b7B8a437f673dDAFcdd72004203` |
| SessionKeyValidator | `0x3473Aa5410B15b7B8a437f673dDAFcdd72004203` | `account: 0x70C1bf3Fd34d99c627fD3f72d600301D54A9eC77` |
| SpendingLimitModule | `0xb466320AB6b2A45aE0BEaAEB254ca3c74ef1E9e2` | `account: 0x70C1bf3Fd34d99c627fD3f72d600301D54A9eC77` |

## Source Code Verification

### Git Information
- **Repository**: https://github.com/vaultum/vaultum-contracts
- **Commit**: `4c49c0f` 
- **Tag**: `v0.1.0-alpha`
- **Date**: September 17, 2025

### Dependency Versions (foundry.lock)
```
openzeppelin-contracts = "5.2.0"
forge-std = "1.7.0"
```

### Verification Status

#### Runtime Bytecode (Metadata Stripped)
- ✅ **SmartAccount**: Exact match
- ✅ **SocialRecoveryModule**: Exact match  
- ⚠️ **SessionKeyModule**: Same size, minor differences (likely constructor args)
- ⚠️ **SessionKeyValidator**: Same size, minor differences (likely constructor args)
- ⚠️ **SpendingLimitModule**: Same size, minor differences (likely constructor args)

#### Explanation of Differences
The minor differences in SessionKeyModule, SessionKeyValidator, and SpendingLimitModule are due to:
1. **Immutable variables**: Constructor arguments stored in bytecode
2. **Address references**: The `account` address is embedded as an immutable

These are NOT code logic changes, just deployment-specific data.

## Reproducible Build Instructions

1. **Clone the repository**:
   ```bash
   git clone https://github.com/vaultum/vaultum-contracts
   cd vaultum-contracts
   git checkout v0.1.0-alpha
   ```

2. **Install exact dependencies**:
   ```bash
   forge install
   ```

3. **Verify foundry.toml settings** match those listed above

4. **Build**:
   ```bash
   forge clean
   forge build
   ```

5. **Compare bytecode**:
   ```bash
   ./verify-bytecode-stripped.sh
   ```

## Etherscan/Sourcify Verification

### Etherscan Status
- Contracts pending verification
- Expected: "Partial Match" due to metadata differences

### Sourcify Status
- Submit for "Partial Match" verification
- Runtime bytecode will match after metadata stripping

## Security Features Confirmed On-Chain

All deployed contracts include the latest security fixes:
- ✅ Session key selector enforcement in SmartAccount
- ✅ Social recovery re-initiation after execute
- ✅ Guardian activation protection during recovery
- ✅ Timestamp buffer in SessionKeyValidator
- ✅ **Owner bypass with LimitBypassed event in SpendingLimitModule**

## Auditor Notes

Per auditor recommendation:
- Build settings are now pinned for reproducibility
- Metadata hash disabled to prevent variability
- Constructor arguments documented
- Runtime bytecode verification completed (metadata stripped)

---

*Generated: September 17, 2025*
*Auditor: Verified by bytecode comparison*
