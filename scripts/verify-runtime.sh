#!/usr/bin/env bash
set -euo pipefail
RPC_URL="${SEPOLIA_RPC_URL:?set SEPOLIA_RPC_URL}"

# addr  artifact-path
pairs=(
  "0x70C1bf3Fd34d99c627fD3f72d600301D54A9eC77 out/SmartAccount.sol/SmartAccount.json"
  "0x433Ed3DAb6C5502029972C7af2F01F08b98DcD1B out/SocialRecoveryModule.sol/SocialRecoveryModule.json"
  "0x3473Aa5410B15b7B8a437f673dDAFcdd72004203 out/SessionKeyValidator.sol/SessionKeyValidator.json"
  "0xC63D5dc1C052289411f848051dB03A8e57D7f094 out/SessionKeyModule.sol/SessionKeyModule.json"
  "0xb466320AB6b2A45aE0BEaAEB254ca3c74ef1E9e2 out/SpendingLimitModule.sol/SpendingLimitModule.json"
)

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
