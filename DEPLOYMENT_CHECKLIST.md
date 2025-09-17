# 📋 Vaultum Deployment Checklist

## Pre-Deployment

- [ ] **Environment Setup**
  - [ ] Copy `env.example` to `.env`
  - [ ] Set `PRIVATE_KEY` (use dedicated deployment wallet)
  - [ ] Set `SEPOLIA_RPC_URL` (use Alchemy/Infura for reliability)
  - [ ] Set `ETHERSCAN_API_KEY` for verification
  - [ ] Verify `ENTRYPOINT` address is correct

- [ ] **Security Checks**
  - [ ] Never commit `.env` file
  - [ ] Use burner wallet for testnet
  - [ ] Ensure private key has sufficient ETH (~0.5 ETH for Sepolia)
  - [ ] Review all contract changes since last deployment

- [ ] **Code Preparation**
  - [ ] Run all tests: `forge test`
  - [ ] Check gas reports: `forge test --gas-report`
  - [ ] Run slither if available: `slither .`
  - [ ] Ensure no compiler warnings

## Deployment Process

### 1. Simulation (Dry Run)
```bash
# Always simulate first to catch errors
forge script script/Deploy.s.sol:Deploy --rpc-url sepolia
```

- [ ] Simulation passes without errors
- [ ] Gas estimates are reasonable
- [ ] Contract addresses look correct

### 2. Broadcast (Actual Deployment)
```bash
# Deploy and verify on Etherscan
forge script script/Deploy.s.sol:Deploy --rpc-url sepolia --broadcast --verify --slow
```

- [ ] Transactions are broadcasting
- [ ] All contracts deployed successfully
- [ ] Configuration transactions completed
- [ ] Etherscan verification submitted

### 3. Verification
```bash
# Check deployed contracts
cast call <SMART_ACCOUNT> "owner()(address)" --rpc-url sepolia
cast call <SMART_ACCOUNT> "getModules()(address[])" --rpc-url sepolia
```

- [ ] Owner is set correctly
- [ ] All modules are registered
- [ ] EntryPoint is configured
- [ ] Recovery module is authorized

## Post-Deployment

- [ ] **Documentation**
  - [ ] Update `deployments/latest.json`
  - [ ] Document gas costs
  - [ ] Note any issues or deviations
  - [ ] Update README with new addresses

- [ ] **Testing**
  - [ ] Test basic account functions
  - [ ] Test module interactions
  - [ ] Test recovery initiation
  - [ ] Test session key creation

- [ ] **Integration**
  - [ ] Update API with new addresses
  - [ ] Update SDKs with new ABIs
  - [ ] Update frontend configuration
  - [ ] Run integration tests

- [ ] **Monitoring**
  - [ ] Set up event monitoring
  - [ ] Configure alerts for critical functions
  - [ ] Monitor gas usage patterns

## Rollback Plan

If deployment fails or issues are discovered:

1. **Do NOT panic** - testnet deployments are for learning
2. **Document the issue** in deployment notes
3. **Fix the problem** in the code
4. **Increment version** if needed
5. **Re-run checklist** from the beginning

## Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| "Insufficient funds" | Add more ETH to deployment wallet |
| "Nonce too low" | Wait for pending transactions or use `--resume` |
| "Contract size too large" | Optimize contract or split functionality |
| "Simulation failed" | Check constructor arguments and dependencies |
| "Verification failed" | Ensure correct compiler version and optimization settings |

## Emergency Contacts

- **Foundry Discord**: https://discord.gg/foundry
- **Ethereum Stack Exchange**: https://ethereum.stackexchange.com
- **Team Chat**: [Your preferred communication channel]

---

**Remember**: Take your time, double-check everything, and document as you go!
