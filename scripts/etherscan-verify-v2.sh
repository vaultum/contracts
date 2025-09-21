#!/usr/bin/env bash
set -euo pipefail

ETHERSCAN_API_KEY="${ETHERSCAN_API_KEY:?set ETHERSCAN_API_KEY}"

echo "=========================================="
echo "ETHERSCAN VERIFICATION - V2 CONTRACTS"
echo "=========================================="
echo "Compiler: Solidity 0.8.30"
echo "Optimizer: 200 runs, via-ir enabled"
echo "EVM Version: paris"
echo ""

# SmartAccount verification
echo "1. Verifying SmartAccount..."
forge verify-contract \
  --chain sepolia \
  --watch \
  --constructor-args 0x0000000000000000000000008f699654a85f0c2869f599e29e803da3089e06fd \
  0xB7747367A657532b744ff4676C3C86866FBA6141 \
  src/SmartAccount.sol:SmartAccount \
  --compiler-version v0.8.30 \
  --optimizer-runs 200 \
  --via-ir || echo "SmartAccount verification failed"

echo ""

# SocialRecoveryModule verification  
echo "2. Verifying SocialRecoveryModule..."
forge verify-contract \
  --chain sepolia \
  --watch \
  --constructor-args 0x000000000000000000000000b7747367a657532b744ff4676c3c86866fba6141 \
  0x80D65Fa661038079e92aE708498d55d35617405D \
  src/modules/SocialRecoveryModule.sol:SocialRecoveryModule \
  --compiler-version v0.8.30 \
  --optimizer-runs 200 \
  --via-ir || echo "SocialRecoveryModule verification failed"

echo ""

# SessionKeyValidator verification
echo "3. Verifying SessionKeyValidator..."
forge verify-contract \
  --chain sepolia \
  --watch \
  --constructor-args 0x000000000000000000000000b7747367a657532b744ff4676c3c86866fba6141 \
  0x82D68EE4Bf9a1F3a4174257a94F4E6a2f40eE209 \
  src/validators/SessionKeyValidator.sol:SessionKeyValidator \
  --compiler-version v0.8.30 \
  --optimizer-runs 200 \
  --via-ir || echo "SessionKeyValidator verification failed"

echo ""

# SessionKeyModule verification
echo "4. Verifying SessionKeyModule..."
forge verify-contract \
  --chain sepolia \
  --watch \
  --constructor-args 0x000000000000000000000000b7747367a657532b744ff4676c3c86866fba614100000000000000000000000082d68ee4bf9a1f3a4174257a94f4e6a2f40ee209 \
  0xF80C03D69c9B264FC30b0D9E3EbC12548C13864f \
  src/modules/SessionKeyModule.sol:SessionKeyModule \
  --compiler-version v0.8.30 \
  --optimizer-runs 200 \
  --via-ir || echo "SessionKeyModule verification failed"

echo ""

# SpendingLimitModule verification
echo "5. Verifying SpendingLimitModule..."
forge verify-contract \
  --chain sepolia \
  --watch \
  --constructor-args 0x000000000000000000000000b7747367a657532b744ff4676c3c86866fba6141 \
  0xbF23835e96A7afBf29585D39B186B3284eD1111E \
  src/modules/SpendingLimitModule.sol:SpendingLimitModule \
  --compiler-version v0.8.30 \
  --optimizer-runs 200 \
  --via-ir || echo "SpendingLimitModule verification failed"

echo ""
echo "=========================================="
echo "ETHERSCAN VERIFICATION COMPLETE"
echo "=========================================="
echo "Check verification status at:"
echo "https://sepolia.etherscan.io/address/0xB7747367A657532b744ff4676C3C86866FBA6141"
echo "https://sepolia.etherscan.io/address/0x80D65Fa661038079e92aE708498d55d35617405D" 
echo "https://sepolia.etherscan.io/address/0x82D68EE4Bf9a1F3a4174257a94F4E6a2f40eE209"
echo "https://sepolia.etherscan.io/address/0xF80C03D69c9B264FC30b0D9E3EbC12548C13864f"
echo "https://sepolia.etherscan.io/address/0xbF23835e96A7afBf29585D39B186B3284eD1111E"
