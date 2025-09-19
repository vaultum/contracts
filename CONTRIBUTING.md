# Contributing to Vaultum Smart Contracts

## 🚀 Welcome Contributors

Thank you for your interest in contributing to Vaultum! This guide will help you get started.

## 📋 Development Process

### Prerequisites
- **Foundry**: Latest version for smart contract development
- **Node.js 18+**: For tooling and scripts
- **Git**: Version control

### Setup
```bash
# Clone the repository
git clone https://github.com/vaultum/contracts.git
cd contracts

# Install dependencies
forge install

# Run tests
forge test

# Run with coverage
forge coverage --report summary
```

## 🛡️ Test Security Policy

### **CRITICAL: Public Repository Safety**

All tests in this public repository must follow strict security guidelines to prevent exposing attack methodologies:

#### **Forbidden in Tests**:
- ❌ **Real private keys**: Never commit actual private keys or mnemonics
- ❌ **Attack recipes**: No step-by-step exploit instructions
- ❌ **Vulnerability terminology**: Avoid "attack", "exploit", "hack", "vulnerability" in test names
- ❌ **Hostile language**: No "attacker", "malicious", "adversary" variables
- ❌ **POC descriptions**: No proof-of-concept attack explanations

#### **Required Patterns**:
- ✅ **Test keys only**: Use `vm.addr()`, `makeAddr()`, or constants like `0xBEEF`
- ✅ **Property focus**: Test what should happen, not how to break it
- ✅ **Neutral naming**: `test_Revert_When_OverDailyCap` not `test_Exploit_DoubleSpend`
- ✅ **Professional tone**: Describe functionality, not vulnerabilities
- ✅ **Behavioral assertions**: Assert correct behavior, not attack prevention

#### **Good vs Bad Examples**:

**❌ BAD**:
```solidity
function test_TOCTOU_DoubleSpendAttack() public {
    // Step 1: Submit two transactions to exploit race condition
    // Step 2: Both pass validation due to timing window
    // This proves the contract is vulnerable to...
}
```

**✅ GOOD**:
```solidity
function test_SpendingCap_EnforcedCorrectly() public {
    // Verify spending caps are properly enforced
    // Second transaction should revert when cap exceeded
}
```

#### **Sanitization Checklist**:
- [ ] No function names containing "attack", "exploit", "hack", "vulnerability", "TOCTOU"
- [ ] No comments describing attack methodologies
- [ ] No step-by-step instructions for breaking contracts
- [ ] No real private keys or sensitive data
- [ ] All variables use neutral names
- [ ] Focus on properties and correct behavior

#### **CI Requirements**:
- **Secret scanning**: All PRs must pass `gitleaks` and `trufflehog` scans
- **Content filtering**: Block files containing forbidden terms
- **Review requirement**: Security team approval for audit-related tests

## 🔄 Pull Request Process

### Before Submitting
1. **Run all tests**: `forge test --summary`
2. **Check coverage**: `forge coverage --report summary`
3. **Security scan**: Ensure no secrets in diff
4. **Sanitization review**: Follow Test Security Policy

### PR Requirements
- **Branch protection**: All changes via pull request
- **Status checks**: Tests must pass, security scans clean
- **Code review**: Required approval from maintainers
- **Commit signing**: All commits must be signed

### Commit Message Format
```
type(scope): brief description

- Bullet point details
- Professional tone only
- No vulnerability or attack references
```

**Types**: `feat`, `fix`, `test`, `docs`, `refactor`, `perf`, `chore`

## 🧪 Testing Guidelines

### Test Structure
```solidity
contract FunctionalityTest is Test {
    // Use neutral, descriptive names
    // Focus on correct behavior
    // Assert properties, not attack prevention
}
```

### Gas Optimization
- **Gas reports**: Run `forge test --gas-report` for performance changes
- **Optimization bounds**: Document gas limits for operations
- **Regression testing**: Ensure changes don't increase gas significantly

### Coverage Requirements
- **Minimum coverage**: 95% for all new code
- **Critical paths**: 100% coverage for security-sensitive functions
- **Edge cases**: Test boundary conditions and error paths

## 🔐 Security Considerations

### Smart Contract Security
- **Reentrancy**: Use `nonReentrant` modifier for external calls
- **Access control**: Proper `onlyOwner`/`onlyAccount` modifiers
- **Input validation**: Validate all external inputs
- **Event logging**: Emit events for all state changes

### Audit Preparation
- **Documentation**: Clear function documentation
- **Test coverage**: Comprehensive test suite
- **Code clarity**: Self-documenting code with clear variable names
- **Security comments**: Explain security-critical decisions

## 📚 Resources

### Documentation
- [Foundry Book](https://book.getfoundry.sh/)
- [ERC-4337 Specification](https://eips.ethereum.org/EIPS/eip-4337)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)

### Security
- [Smart Contract Security Best Practices](https://consensys.github.io/smart-contract-best-practices/)
- [Slither Static Analysis](https://github.com/crytic/slither)

## 🤝 Community

### Getting Help
- **Issues**: Use GitHub issues for bug reports
- **Discussions**: Use GitHub discussions for questions
- **Security**: Email security@vaultum.app for vulnerabilities

### Code of Conduct
- Be respectful and professional
- Focus on constructive feedback
- Help maintain a welcoming environment
- Follow security guidelines strictly

---

**Thank you for contributing to Vaultum!** 🚀

*For security-sensitive contributions, please review the Test Security Policy carefully.*
