#!/bin/bash

# Direct deployment using cast send

PRIVATE_KEY="0xf5b89a53dcda4c102dd7022528e774b14f729541d54e9e1b724db25299d733d4"
RPC_URL="https://ethereum-sepolia-rpc.publicnode.com"
OWNER="0xa1cdCE5b32474E4f353b747DDb37F39b82447548"

echo "==========================================="
echo "Deploying SmartAccount to Sepolia"
echo "==========================================="

# Get the bytecode and constructor args
BYTECODE=$(cat out/SmartAccount.sol/SmartAccount.json | jq -r '.bytecode.object')
# Constructor args: owner address (padded to 32 bytes)
CONSTRUCTOR_ARGS="000000000000000000000000a1cdCE5b32474E4f353b747DDb37F39b82447548"

# Combine bytecode with constructor args
DEPLOY_DATA="${BYTECODE}${CONSTRUCTOR_ARGS}"

echo "Deploying contract..."
TX_RESULT=$(fcast send --create $DEPLOY_DATA --private-key $PRIVATE_KEY --rpc-url $RPC_URL --json 2>/dev/null)

if [ $? -eq 0 ]; then
    CONTRACT_ADDRESS=$(echo $TX_RESULT | jq -r '.contractAddress')
    TX_HASH=$(echo $TX_RESULT | jq -r '.transactionHash')
    
    echo "✅ SmartAccount deployed!"
    echo "Contract Address: $CONTRACT_ADDRESS"
    echo "Transaction Hash: $TX_HASH"
    echo ""
    echo "View on Etherscan:"
    echo "https://sepolia.etherscan.io/address/$CONTRACT_ADDRESS"
else
    echo "❌ Deployment failed"
    echo $TX_RESULT
fi
