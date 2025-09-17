#!/bin/bash

# Professional Vaultum Deployment Script
# Safe, repeatable, and auditable

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if .env exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found!${NC}"
    echo "Please copy env.example to .env and configure it"
    exit 1
fi

# Load environment variables
source .env

# Validate required variables
if [ -z "$SEPOLIA_RPC_URL" ]; then
    echo -e "${RED}Error: SEPOLIA_RPC_URL not set in .env${NC}"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY not set in .env${NC}"
    exit 1
fi

# Display configuration (hide sensitive data)
echo -e "${GREEN}==================================${NC}"
echo -e "${GREEN}Vaultum Deployment Script${NC}"
echo -e "${GREEN}==================================${NC}"
echo "Network: Sepolia"
echo "RPC: ${SEPOLIA_RPC_URL}"
echo "Deployer: $(cast wallet address $PRIVATE_KEY)"
echo ""

# Check deployer balance
BALANCE=$(cast balance $(cast wallet address $PRIVATE_KEY) --rpc-url $SEPOLIA_RPC_URL | cast from-wei)
echo "Deployer Balance: ${BALANCE} ETH"

# Minimum balance check (0.1 ETH for safety)
MIN_BALANCE="0.1"
if (( $(echo "$BALANCE < $MIN_BALANCE" | bc -l) )); then
    echo -e "${RED}Error: Insufficient balance. Need at least ${MIN_BALANCE} ETH${NC}"
    exit 1
fi

echo ""

# Command line argument handling
ACTION=${1:-simulate}

case $ACTION in
    simulate)
        echo -e "${YELLOW}Running SIMULATION (no transactions will be sent)...${NC}"
        echo ""
        forge script script/Deploy.s.sol:Deploy --rpc-url sepolia
        echo ""
        echo -e "${GREEN}Simulation complete!${NC}"
        echo "To deploy for real, run: ./deploy.sh broadcast"
        ;;
        
    broadcast)
        echo -e "${YELLOW}Running ACTUAL DEPLOYMENT...${NC}"
        echo -e "${YELLOW}This will send real transactions!${NC}"
        echo ""
        
        # Confirmation
        read -p "Are you sure you want to deploy? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "Deployment cancelled"
            exit 0
        fi
        
        echo ""
        echo "Deploying..."
        forge script script/Deploy.s.sol:Deploy --rpc-url sepolia --broadcast --slow
        
        echo ""
        echo -e "${GREEN}==================================${NC}"
        echo -e "${GREEN}Deployment Complete!${NC}"
        echo -e "${GREEN}==================================${NC}"
        
        # Show deployment artifacts location
        echo "Deployment saved to: deployments/latest.json"
        echo "Broadcast data in: broadcast/Deploy.s.sol/"
        
        # Optionally verify on Etherscan
        if [ ! -z "$ETHERSCAN_API_KEY" ]; then
            echo ""
            read -p "Verify on Etherscan? (yes/no): " verify
            if [ "$verify" == "yes" ]; then
                echo "Verifying contracts..."
                forge script script/Deploy.s.sol:Deploy --rpc-url sepolia --verify --resume
            fi
        fi
        ;;
        
    verify)
        echo -e "${YELLOW}Verifying existing deployment on Etherscan...${NC}"
        forge script script/Deploy.s.sol:Deploy --rpc-url sepolia --verify --resume
        ;;
        
    *)
        echo "Usage: $0 [simulate|broadcast|verify]"
        echo "  simulate  - Dry run without sending transactions (default)"
        echo "  broadcast - Deploy contracts to Sepolia"
        echo "  verify    - Verify existing deployment on Etherscan"
        exit 1
        ;;
esac
