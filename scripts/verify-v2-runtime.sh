#!/usr/bin/env bash
set -euo pipefail
RPC_URL="${SEPOLIA_RPC_URL:-https://ethereum-sepolia-rpc.publicnode.com}"

# NEW V2 contract addresses (September 21, 2025 deployment)
pairs=(
  "0xB7747367A657532b744ff4676C3C86866FBA6141 out/SmartAccount.sol/SmartAccount.json"
  "0x80D65Fa661038079e92aE708498d55d35617405D out/SocialRecoveryModule.sol/SocialRecoveryModule.json"
  "0x82D68EE4Bf9a1F3a4174257a94F4E6a2f40eE209 out/SessionKeyValidator.sol/SessionKeyValidator.json"
  "0xF80C03D69c9B264FC30b0D9E3EbC12548C13864f out/SessionKeyModule.sol/SessionKeyModule.json"
  "0xbF23835e96A7afBf29585D39B186B3284eD1111E out/SpendingLimitModule.sol/SpendingLimitModule.json"
)

echo "V2 RUNTIME BYTECODE VERIFICATION (OpenZeppelin v5.2.0)"
echo "========================================================"
printf "%s\n" "Contract                               On-chain(Bytes)  Local(Bytes)    Hash(on)                         Hash(local)" 
for entry in "${pairs[@]}"; do
  set -- $entry
  addr=$1; art=$2

  onchain_hex=$(cast code "$addr" --rpc-url "$RPC_URL" | sed 's/^0x//')
  printf "%s" "$onchain_hex" | xxd -r -p > /tmp/on.bin
  jq -r .deployedBytecode.object "$art" | sed 's/^0x//' | xxd -r -p > /tmp/local.bin

  on_sz=$(wc -c </tmp/on.bin | tr -d ' ')
  lc_sz=$(wc -c </tmp/local.bin | tr -d ' ')
  on_sha=$(shasum -a 256 /tmp/on.bin | awk '{print $1}')
  lc_sha=$(shasum -a 256 /tmp/local.bin | awk '{print $1}')

  printf "%-38s  %-14s  %-13s  %-32s  %-32s\n" "$addr" "$on_sz" "$lc_sz" "$on_sha" "$lc_sha"

done

echo ""
echo "Expected: Perfect size and hash matches (repository-deployment alignment)"
