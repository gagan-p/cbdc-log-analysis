#!/bin/bash

# find_failed_txnmanager.sh - Find FAILED patterns within TransactionManager logs
# Searches for FAILED occurrences within TransactionManager realm blocks

echo "======================================================="
echo "FAILED PATTERNS IN TRANSACTION MANAGER LOGS"
echo "Generated: $(date)"
echo "======================================================="

# Check if .log files exist
if ! ls *.log >/dev/null 2>&1; then
    echo "ERROR: No .log files found in current directory"
    exit 1
fi

echo "Searching for FAILED patterns in TransactionManager blocks..."
echo ""

# Create temporary files
tmpfile=$(mktemp)
failed_blocks=$(mktemp)

total_txnmanager_blocks=0
failed_blocks_count=0

# Process each log file
for logfile in *.log; do
    echo "Processing $logfile..."
    
    # Extract TransactionManager blocks and check for FAILED patterns
    awk '
    /^<log.*realm="org.jpos.transaction.TransactionManager"/ {
        in_txnmgr_block = 1
        block_content = $0 "\n"
        has_failed = 0
        txnname = ""
        txn_id = ""
        timestamp = ""
        
        # Extract timestamp from log tag
        match($0, /at="([^"]+)"/, ts_arr)
        timestamp = ts_arr[1]
        next
    }
    
    in_txnmgr_block {
        block_content = block_content $0 "\n"
        
        # Extract TXNNAME
        if (/TXNNAME:/ && txnname == "") {
            match($0, /TXNNAME: ([^\n\r]+)/, txn_arr)
            txnname = txn_arr[1]
        }
        
        # Extract TXN_ID
        if (/TXN_ID:/ && txn_id == "") {
            match($0, /TXN_ID: ([^\n\r]+)/, id_arr)
            txn_id = id_arr[1]
        }
        
        # Check for FAILED pattern
        if (/FAILED/) {
            has_failed = 1
        }
    }
    
    in_txnmgr_block && /<\/log>/ {
        total_blocks++
        
        if (has_failed) {
            failed_blocks++
            print "=== FAILED TRANSACTION BLOCK ==="
            print "File: " FILENAME
            print "Timestamp: " timestamp
            print "TXNNAME: " txnname
            print "TXN_ID: " txn_id
            print "Block Content:"
            print block_content
            print "================================"
            print ""
        }
        
        # Reset for next block
        in_txnmgr_block = 0
        block_content = ""
        has_failed = 0
        txnname = ""
        txn_id = ""
        timestamp = ""
    }
    
    END {
        print "File " FILENAME " processed:"
        print "  Total TransactionManager blocks: " total_blocks
        print "  Blocks with FAILED: " failed_blocks
        print ""
    }
    ' "$logfile" >> "$tmpfile"
done

echo ""
echo "======================================================="
echo "SUMMARY OF FAILED PATTERNS"
echo "======================================================="

# Display results
if [ -s "$tmpfile" ]; then
    cat "$tmpfile"
    
    # Count summary
    failed_count=$(grep -c "=== FAILED TRANSACTION BLOCK ===" "$tmpfile")
    echo "TOTAL FAILED TRANSACTION MANAGER BLOCKS FOUND: $failed_count"
    
    # Extract just the FAILED lines for analysis
    echo ""
    echo "======================================================="
    echo "FAILED PATTERN ANALYSIS"
    echo "======================================================="
    
    echo "All FAILED occurrences in TransactionManager blocks:"
    for logfile in *.log; do
        echo "--- $logfile ---"
        awk '
        /^<log.*realm="org.jpos.transaction.TransactionManager"/,/<\/log>/ {
            if (/FAILED/) {
                print "  Line: " $0
            }
        }
        ' "$logfile"
    done
    
else
    echo "No FAILED patterns found in TransactionManager blocks."
    echo ""
    echo "This suggests either:"
    echo "1. All TransactionManager transactions completed successfully"
    echo "2. FAILED status might be logged differently in this system"
    echo "3. Failures might be indicated by different patterns (e.g., error codes, exceptions)"
fi

# Save detailed output
cp "$tmpfile" failed_txnmanager_analysis.txt
echo ""
echo "Detailed analysis saved to: failed_txnmanager_analysis.txt"

# Cleanup
rm -f "$tmpfile" "$failed_blocks"

echo ""
echo "======================================================="
echo "ANALYSIS COMPLETE - $(date)"
echo "======================================================="