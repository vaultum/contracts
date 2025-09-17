#!/bin/bash

# EntryPoint Balance Monitor
# Run this script via cron every 5 minutes: */5 * * * * /path/to/monitor-entrypoint.sh

# Load environment
if [ -f .env ]; then
    export $(cat .env | xargs)
fi

# Configuration
ENTRYPOINT="0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789"
SMART_ACCOUNT="0x70C1bf3Fd34d99c627fD3f72d600301D54A9eC77"
RPC_URL="https://ethereum-sepolia-rpc.publicnode.com"
MIN_BALANCE="1000000000000000" # 0.001 ETH in wei
TOPUP_AMOUNT="10000000000000000" # 0.01 ETH in wei
LOG_FILE="entrypoint-monitor.log"
SLACK_WEBHOOK="${SLACK_WEBHOOK_URL}" # Optional: Set in .env for alerts

# Safety limits
MAX_TOPUPS_PER_HOUR=3
MAX_TOPUP_AMOUNT_PER_DAY="100000000000000000" # 0.1 ETH max per day
TOPUP_HISTORY_FILE="topup-history.json"
RPC_RETRY_COUNT=3
RPC_RETRY_DELAY=5 # seconds

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to send Slack alert (optional)
send_alert() {
    if [ ! -z "$SLACK_WEBHOOK" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"⚠️ EntryPoint Alert: $1\"}" \
            "$SLACK_WEBHOOK" 2>/dev/null
    fi
}

# Get current balance with retries
get_balance() {
    local retries=0
    local balance=""
    
    while [ $retries -lt $RPC_RETRY_COUNT ]; do
        balance=$(cast call "$ENTRYPOINT" \
            "balanceOf(address)(uint256)" \
            "$SMART_ACCOUNT" \
            --rpc-url "$RPC_URL" 2>/dev/null)
        
        if [ ! -z "$balance" ]; then
            echo "$balance"
            return 0
        fi
        
        ((retries++))
        log_message "RPC call failed, retry $retries/$RPC_RETRY_COUNT"
        sleep $RPC_RETRY_DELAY
    done
    
    log_message "ERROR: Failed to get balance after $RPC_RETRY_COUNT retries"
    echo "0"
    return 1
}

# Check if we've exceeded rate limits
check_rate_limits() {
    if [ ! -f "$TOPUP_HISTORY_FILE" ]; then
        echo '{"topups": []}' > "$TOPUP_HISTORY_FILE"
    fi
    
    local now=$(date +%s)
    local hour_ago=$((now - 3600))
    local day_ago=$((now - 86400))
    
    # Count topups in last hour
    local hour_count=$(jq --arg since "$hour_ago" \
        '[.topups[] | select(.timestamp > ($since | tonumber))] | length' \
        "$TOPUP_HISTORY_FILE")
    
    # Sum topups in last day
    local day_total=$(jq --arg since "$day_ago" \
        '[.topups[] | select(.timestamp > ($since | tonumber)) | .amount] | add // 0' \
        "$TOPUP_HISTORY_FILE")
    
    if [ "$hour_count" -ge "$MAX_TOPUPS_PER_HOUR" ]; then
        log_message "RATE LIMIT: Already $hour_count topups in last hour (max $MAX_TOPUPS_PER_HOUR)"
        send_alert "Rate limit exceeded: $hour_count topups in last hour"
        return 1
    fi
    
    if [ "$day_total" -ge "$MAX_TOPUP_AMOUNT_PER_DAY" ]; then
        log_message "RATE LIMIT: Already topped up $day_total wei today (max $MAX_TOPUP_AMOUNT_PER_DAY)"
        send_alert "Daily limit exceeded: $day_total wei topped up today"
        return 1
    fi
    
    return 0
}

# Record successful topup
record_topup() {
    local tx_hash="$1"
    local amount="$2"
    local timestamp=$(date +%s)
    
    # Add to history
    jq --arg tx "$tx_hash" --arg amt "$amount" --arg ts "$timestamp" \
        '.topups += [{"tx": $tx, "amount": ($amt | tonumber), "timestamp": ($ts | tonumber)}]' \
        "$TOPUP_HISTORY_FILE" > temp.json && mv temp.json "$TOPUP_HISTORY_FILE"
    
    # Clean old entries (keep last 7 days)
    local week_ago=$((timestamp - 604800))
    jq --arg since "$week_ago" \
        '.topups = [.topups[] | select(.timestamp > ($since | tonumber))]' \
        "$TOPUP_HISTORY_FILE" > temp.json && mv temp.json "$TOPUP_HISTORY_FILE"
}

# Top up EntryPoint deposit with safety checks
topup_deposit() {
    if [ -z "$PRIVATE_KEY" ]; then
        log_message "ERROR: PRIVATE_KEY not set, cannot auto-topup"
        send_alert "PRIVATE_KEY not configured for auto-topup"
        return 1
    fi
    
    # Check rate limits first
    if ! check_rate_limits; then
        log_message "Skipping topup due to rate limits"
        return 1
    fi
    
    log_message "Initiating auto-topup of 0.01 ETH..."
    
    local tx_hash=""
    local retries=0
    
    while [ $retries -lt $RPC_RETRY_COUNT ]; do
        tx_hash=$(cast send "$ENTRYPOINT" \
            "depositTo(address)" "$SMART_ACCOUNT" \
            --value "$TOPUP_AMOUNT" \
            --private-key "$PRIVATE_KEY" \
            --rpc-url "$RPC_URL" \
            --json 2>/dev/null | jq -r '.transactionHash' || echo "")
        
        if [ ! -z "$tx_hash" ]; then
            log_message "✅ Topup successful! TX: $tx_hash"
            send_alert "EntryPoint topped up successfully. TX: $tx_hash"
            record_topup "$tx_hash" "$TOPUP_AMOUNT"
            return 0
        fi
        
        ((retries++))
        log_message "Topup attempt $retries failed, retrying..."
        sleep $RPC_RETRY_DELAY
    done
    
    log_message "❌ Topup failed after $RPC_RETRY_COUNT attempts!"
    send_alert "EntryPoint topup FAILED after $RPC_RETRY_COUNT attempts! Manual intervention required."
    return 1
}

# Main monitoring logic
main() {
    log_message "Starting EntryPoint balance check..."
    
    # Get current balance
    current_balance=$(get_balance)
    
    # Convert to decimal for display
    balance_eth=$(echo "scale=6; $current_balance / 1000000000000000000" | bc 2>/dev/null || echo "0")
    
    log_message "Current EntryPoint balance: $balance_eth ETH"
    
    # Check if balance is below minimum
    if [ "$current_balance" -lt "$MIN_BALANCE" ]; then
        log_message "⚠️  WARNING: Balance below minimum (0.001 ETH)"
        send_alert "EntryPoint balance LOW: $balance_eth ETH"
        
        # Attempt auto-topup
        if topup_deposit; then
            # Verify new balance
            sleep 5
            new_balance=$(get_balance)
            new_balance_eth=$(echo "scale=6; $new_balance / 1000000000000000000" | bc 2>/dev/null || echo "0")
            log_message "New balance after topup: $new_balance_eth ETH"
        fi
    else
        log_message "✅ Balance healthy"
    fi
    
    # Store current status in JSON
    cat > entrypoint-status.json <<EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "entryPoint": "$ENTRYPOINT",
    "smartAccount": "$SMART_ACCOUNT",
    "balance_wei": "$current_balance",
    "balance_eth": "$balance_eth",
    "minimum_wei": "$MIN_BALANCE",
    "healthy": $([ "$current_balance" -ge "$MIN_BALANCE" ] && echo "true" || echo "false")
}
EOF
    
    log_message "Status saved to entrypoint-status.json"
    log_message "Check complete"
    echo ""
}

# Run main function
main
