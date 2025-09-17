# 🚀 Professional Vaultum Deployment Workflow

## Overview

This document describes our production-ready deployment process, moving from the experimental `cast send --create` approach to a professional, auditable workflow using Foundry scripts.

## Why We Changed

### Previous Approach (Quick but Risky)
```bash
# Raw bytecode deployment
cast send --create <BYTECODE> --private-key ... --rpc-url ...
```

**Problems:**
- ❌ No source verification
- ❌ No deployment artifacts
- ❌ Hard to reproduce
- ❌ No post-deploy configuration
- ❌ Constructor args manually encoded
- ❌ No CI/CD integration

### New Approach (Professional)
```bash
# Scripted deployment with verification
./deploy.sh broadcast
```

**Benefits:**
- ✅ Source verified on Etherscan
- ✅ Deployment artifacts saved
- ✅ Fully reproducible
- ✅ Post-deploy configuration included
- ✅ Type-safe constructor args
- ✅ CI/CD ready

## Workflow Steps

### 1. Environment Setup

```bash
# Copy example and configure
cp env.example .env
# Edit .env with your configuration
```

**Required Variables:**
- `SEPOLIA_RPC_URL` - Use Alchemy/Infura for reliability
- `PRIVATE_KEY` - Dedicated deployment wallet
- `ETHERSCAN_API_KEY` - For verification
- `ENTRYPOINT` - ERC-4337 EntryPoint address

### 2. Pre-flight Checks

```bash
# Run tests
forge test

# Check gas usage
forge test --gas-report

# Build contracts
forge build
```

### 3. Simulation (Always First!)

```bash
./deploy.sh simulate
# or manually:
forge script script/Deploy.s.sol:Deploy --rpc-url sepolia
```

This shows you exactly what will happen without spending gas.

### 4. Deploy

```bash
./deploy.sh broadcast
# or manually:
forge script script/Deploy.s.sol:Deploy --rpc-url sepolia --broadcast --slow
```

The script will:
1. Check your balance
2. Deploy all contracts
3. Configure relationships
4. Save artifacts to `deployments/`
5. Create broadcast logs

### 5. Verification

```bash
./deploy.sh verify
# or manually:
forge script script/Deploy.s.sol:Deploy --rpc-url sepolia --verify --resume
```

### 6. Post-Deployment

Check your deployment:
```bash
# Read deployment artifact
cat deployments/latest.json

# Verify on-chain
cast call <SMART_ACCOUNT> "owner()(address)" --rpc-url sepolia
cast call <SMART_ACCOUNT> "getModules()(address[])" --rpc-url sepolia
```

## File Structure

```
vaultum-contracts/
├── script/
│   ├── Deploy.s.sol          # Main deployment script
│   └── DeployTestnet.s.sol   # Testnet-specific script
├── deployments/
│   ├── latest.json           # Latest deployment
│   └── sepolia-*.json        # Historical deployments
├── broadcast/
│   └── Deploy.s.sol/
│       └── 11155111/         # Sepolia broadcasts
├── .env                      # Local configuration (git ignored)
├── env.example               # Example configuration
├── deploy.sh                 # Deployment wrapper script
└── foundry.toml              # Foundry configuration
```

## Safety Guidelines

### DO ✅
- Always simulate before broadcast
- Use dedicated deployment wallets
- Keep private keys in `.env` only
- Verify contracts on Etherscan
- Document every deployment
- Use hardware wallets for mainnet

### DON'T ❌
- Never commit `.env` files
- Never paste private keys in terminal
- Never skip simulation
- Never rush deployments
- Never reuse nonces manually
- Never deploy directly to mainnet

## CI/CD Integration

For GitHub Actions:
```yaml
- name: Deploy to Sepolia
  run: |
    forge script script/Deploy.s.sol:Deploy \
      --rpc-url sepolia \
      --broadcast \
      --verify
  env:
    PRIVATE_KEY: ${{ secrets.DEPLOY_KEY }}
    ETHERSCAN_API_KEY: ${{ secrets.ETHERSCAN_KEY }}
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "vm.envUint: not found" | Check `.env` file exists and is sourced |
| "insufficient funds" | Add ETH to deployment wallet |
| "nonce too low" | Wait for pending tx or use `--resume` |
| PATH conflicts | Ensure Foundry is in PATH before other tools |
| RPC timeouts | Use reliable RPC (Alchemy/Infura) |

## Advanced Usage

### Deploy Specific Contracts
```solidity
// In Deploy.s.sol, add flags
bool deployRecovery = vm.envOr("DEPLOY_RECOVERY", true);
if (deployRecovery) {
    recoveryModule = new SocialRecoveryModule(address(account));
}
```

### Multi-chain Deployment
```bash
# Deploy to multiple networks
for network in sepolia goerli polygon; do
    forge script script/Deploy.s.sol:Deploy --rpc-url $network --broadcast
done
```

### Gas Optimization
```bash
# Profile gas usage
forge script script/Deploy.s.sol:Deploy --rpc-url sepolia --gas-report
```

## Emergency Procedures

If deployment fails mid-way:
1. Check `broadcast/` for partial deployment
2. Use `--resume` to continue from last successful tx
3. Or manually complete missing steps
4. Document in deployment notes

## Version History

- **v1.0** - Initial cast send approach (learning phase)
- **v2.0** - Professional forge script workflow (current)

---

**Remember**: This workflow prioritizes safety, reproducibility, and auditability over speed. Take your time and follow the checklist!
