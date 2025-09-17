#!/bin/bash

# Simple deployment script for Vaultum contracts
# Uses forge create to deploy each contract directly

PRIVATE_KEY="0xf5b89a53dcda4c102dd7022528e774b14f729541d54e9e1b724db25299d733d4"
RPC_URL="https://ethereum-sepolia-rpc.publicnode.com"
DEPLOYER="0xa1cdCE5b32474E4f353b747DDb37F39b82447548"

echo "========================================="
echo "Deploying Vaultum Contracts to Sepolia"
echo "========================================="
echo "Deployer: $DEPLOYER"
echo ""

# Deploy SmartAccount
echo "Deploying SmartAccount..."
SMART_ACCOUNT=$(forge create src/SmartAccount.sol:SmartAccount \
  --constructor-args $DEPLOYER \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL \
  --json | jq -r '.deployedTo')

if [ -z "$SMART_ACCOUNT" ]; then
  echo "Failed to deploy SmartAccount"
  exit 1
fi
echo "SmartAccount deployed to: $SMART_ACCOUNT"

# Deploy SocialRecoveryModule  
echo ""
echo "Deploying SocialRecoveryModule..."
RECOVERY_MODULE=$(forge create src/modules/SocialRecoveryModule.sol:SocialRecoveryModule \
  --constructor-args $SMART_ACCOUNT \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL \
  --json | jq -r '.deployedTo')
  
echo "SocialRecoveryModule deployed to: $RECOVERY_MODULE"

# Deploy SessionKeyValidator
echo ""
echo "Deploying SessionKeyValidator..."
SESSION_VALIDATOR=$(forge create src/validators/SessionKeyValidator.sol:SessionKeyValidator \
  --constructor-args $SMART_ACCOUNT \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL \
  --json | jq -r '.deployedTo')
  
echo "SessionKeyValidator deployed to: $SESSION_VALIDATOR"

# Deploy SessionKeyModule
echo ""
echo "Deploying SessionKeyModule..."
SESSION_MODULE=$(forge create src/modules/SessionKeyModule.sol:SessionKeyModule \
  --constructor-args $SMART_ACCOUNT $SESSION_VALIDATOR \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL \
  --json | jq -r '.deployedTo')
  
echo "SessionKeyModule deployed to: $SESSION_MODULE"

# Deploy SpendingLimitModule
echo ""
echo "Deploying SpendingLimitModule..."
SPENDING_MODULE=$(forge create src/modules/SpendingLimitModule.sol:SpendingLimitModule \
  --constructor-args $SMART_ACCOUNT \
  --private-key $PRIVATE_KEY \
  --rpc-url $RPC_URL \
  --json | jq -r '.deployedTo')
  
echo "SpendingLimitModule deployed to: $SPENDING_MODULE"

echo ""
echo "========================================="
echo "DEPLOYMENT COMPLETE!"
echo "========================================="
echo "SmartAccount:          $SMART_ACCOUNT"
echo "SocialRecoveryModule:  $RECOVERY_MODULE"
echo "SessionKeyModule:      $SESSION_MODULE"
echo "SessionKeyValidator:   $SESSION_VALIDATOR"
echo "SpendingLimitModule:   $SPENDING_MODULE"
echo "========================================="
echo ""
echo "View on Etherscan:"
echo "https://sepolia.etherscan.io/address/$SMART_ACCOUNT"
