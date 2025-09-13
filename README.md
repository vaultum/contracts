# Vaultum Smart Contracts

![Tests](https://github.com/vaultum/contracts/workflows/Smart%20Contract%20Tests/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

## 🔐 Overview

Vaultum smart contracts implement ERC-4337 Account Abstraction with modular security features. Built with Foundry and designed for maximum security and flexibility.

## ✨ Features

- **ERC-4337 Account Abstraction** - Full AA wallet implementation
- **Modular Security Architecture** - Plug-and-play security modules
- **Session Keys** - Temporary keys with granular permissions
- **Spending Limits** - Daily/weekly/monthly transaction limits
- **Social Recovery** - Recover access through trusted guardians
- **Multi-signature Support** - Require multiple approvals for transactions
- **Upgradeable** - Safe upgrade patterns with proper access control

## 📦 Installation

### Using Foundry

```bash
forge install vaultum/contracts
```

### Using npm

```bash
npm install @vaultum/contracts
```

## 🚀 Quick Start

### Deploy a Smart Account

```solidity
import "@vaultum/contracts/SmartAccount.sol";

// Deploy a new smart account
SmartAccount account = new SmartAccount(
    entryPoint,
    owner,
    initialModules
);
```

### Add Security Modules

```solidity
// Add session key validator
account.addValidator(sessionKeyValidator);

// Add spending limit module
account.addModule(spendingLimitModule);

// Add social recovery
account.addModule(socialRecoveryModule);
```

## 🏗️ Architecture

```
contracts/
├── SmartAccount.sol         # Main account implementation
├── interfaces/
│   ├── IAccount.sol        # ERC-4337 account interface
│   └── IEntryPoint.sol     # EntryPoint interface
├── modules/
│   ├── ModuleManager.sol   # Module management logic
│   ├── SessionKeyModule.sol
│   ├── SpendingLimitModule.sol
│   └── SocialRecoveryModule.sol
└── validators/
    ├── SessionKeyValidator.sol
    └── ValidatorManager.sol
```

## 🧪 Testing

Run the test suite:

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test testSessionKey

# Gas report
forge test --gas-report
```

## 🔍 Security

### Audits

- Audit reports available in `/audits` directory
- Bug bounty program: [vaultum.app/security](https://vaultum.app/security)

### Best Practices

1. Always use the latest version
2. Test thoroughly on testnets first
3. Use hardware wallets for owner keys
4. Implement proper access controls
5. Monitor transactions regularly

## 📊 Gas Optimization

Our contracts are optimized for gas efficiency:

| Operation | Gas Cost |
|-----------|----------|
| Deploy Account | ~500,000 |
| Add Module | ~50,000 |
| Execute Transaction | ~80,000 |
| Validate UserOp | ~35,000 |

## 🛠️ Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 18+

### Setup

```bash
# Clone the repository
git clone https://github.com/vaultum/contracts
cd contracts

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test
```

### Deployment

```bash
# Deploy to local network
forge script script/Deploy.s.sol --rpc-url http://localhost:8545

# Deploy to testnet
forge script script/Deploy.s.sol --rpc-url $TESTNET_RPC --broadcast

# Verify on Etherscan
forge verify-contract $CONTRACT_ADDRESS SmartAccount --chain-id 1
```

## 📚 Documentation

- [Technical Documentation](https://docs.vaultum.app/contracts)
- [Integration Guide](https://docs.vaultum.app/integration)
- [Security Best Practices](https://docs.vaultum.app/security)

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Process

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- [Website](https://vaultum.app)
- [Documentation](https://docs.vaultum.app)
- [Twitter](https://twitter.com/vaultumapp)
- [Discord](https://discord.gg/vaultum)

## ⚠️ Disclaimer

These contracts are provided as-is. While we strive for security and correctness, please use at your own risk. Always audit and test thoroughly before mainnet deployment.

---

Built with ❤️ by the Vaultum team