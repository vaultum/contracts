#!/bin/bash

echo "====================================="
echo "BYTECODE VERIFICATION (METADATA STRIPPED)"
echo "====================================="
echo ""

# Function to strip metadata from bytecode
strip_metadata() {
    local bytecode="$1"
    # Metadata starts with 0xa264 (cbor) or 0xa165 (cbor) and continues to the end
    # We'll find the last occurrence and strip from there
    
    # Convert to lowercase for consistency
    bytecode=$(echo "$bytecode" | tr '[:upper:]' '[:lower:]')
    
    # Find position of metadata marker (a264 or a165)
    # The metadata is at the end, so we look for the last occurrence
    if [[ "$bytecode" =~ a264 ]]; then
        # Split at the last a264
        runtime="${bytecode%a264*}"
    elif [[ "$bytecode" =~ a165 ]]; then
        # Split at the last a165
        runtime="${bytecode%a165*}"
    else
        # No metadata found, return as-is
        runtime="$bytecode"
    fi
    
    echo "$runtime"
}

# Contract addresses (using arrays for compatibility)
contracts=("SmartAccount" "SocialRecoveryModule" "SessionKeyModule" "SessionKeyValidator" "SpendingLimitModule")
addresses=("0x70C1bf3Fd34d99c627fD3f72d600301D54A9eC77" "0x433Ed3DAb6C5502029972C7af2F01F08b98DcD1B" "0xC63D5dc1C052289411f848051dB03A8e57D7f094" "0x3473Aa5410B15b7B8a437f673dDAFcdd72004203" "0xb466320AB6b2A45aE0BEaAEB254ca3c74ef1E9e2")

echo "Comparing runtime bytecode (metadata stripped)..."
echo ""

# Results tracking
matches=0
mismatches=0

for i in "${!contracts[@]}"; do
    contract="${contracts[$i]}"
    addr="${addresses[$i]}"
    
    echo "Checking $contract..."
    
    # Get deployed bytecode
    deployed=$(cast code "$addr" --rpc-url https://ethereum-sepolia-rpc.publicnode.com 2>/dev/null)
    
    # Get local bytecode
    local_bytecode=$(cat out/$contract.sol/$contract.json | jq -r '.deployedBytecode.object' 2>/dev/null)
    
    if [ -z "$deployed" ] || [ -z "$local_bytecode" ]; then
        echo "  ❌ Failed to fetch bytecode"
        ((mismatches++))
        continue
    fi
    
    # Strip metadata from both
    deployed_runtime=$(strip_metadata "$deployed")
    local_runtime=$(strip_metadata "$local_bytecode")
    
    # Get sizes for comparison
    deployed_size=${#deployed_runtime}
    local_size=${#local_runtime}
    
    echo "  Deployed runtime size: $deployed_size"
    echo "  Local runtime size:    $local_size"
    
    # Compare
    if [ "$deployed_runtime" = "$local_runtime" ]; then
        echo "  ✅ RUNTIME MATCH (metadata stripped)"
        ((matches++))
    else
        # Check if just size differs
        if [ "$deployed_size" = "$local_size" ]; then
            echo "  ⚠️  Same size but different content"
            
            # Sample first 100 chars for comparison
            deployed_sample="${deployed_runtime:0:100}"
            local_sample="${local_runtime:0:100}"
            
            if [ "$deployed_sample" = "$local_sample" ]; then
                echo "  → Beginning matches, likely minor differences"
            else
                echo "  → Significant differences found"
            fi
        else
            echo "  ❌ RUNTIME MISMATCH"
            size_diff=$((deployed_size - local_size))
            echo "  → Size difference: $size_diff bytes"
        fi
        ((mismatches++))
    fi
    echo ""
done

echo "====================================="
echo "SUMMARY"
echo "====================================="
echo "✅ Matches:    $matches"
echo "❌ Mismatches: $mismatches"
echo ""

if [ "$mismatches" -eq 0 ]; then
    echo "🎉 All contracts have matching runtime bytecode!"
    echo "The differences are only in metadata as expected."
else
    echo "⚠️  Some contracts have runtime differences."
    echo "This may indicate actual code changes or different compiler settings."
fi

echo ""
echo "Recording verification results..."

# Save results
cat > bytecode-verification.json <<EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "method": "metadata_stripped_comparison",
    "results": {
        "matches": $matches,
        "mismatches": $mismatches,
        "contracts": {
            "SmartAccount": "${addresses[0]}",
            "SocialRecoveryModule": "${addresses[1]}",
            "SessionKeyModule": "${addresses[2]}",
            "SessionKeyValidator": "${addresses[3]}",
            "SpendingLimitModule": "${addresses[4]}"
        }
    }
}
EOF

echo "Results saved to bytecode-verification.json"
