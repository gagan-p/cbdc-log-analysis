#!/bin/bash

# extract_failed_5lines.sh - Extract 5 key lines for each failed transaction
# Lines: TxnID, TxnType, First FAILED, Last FAILED, Use RC

echo "======================================================="
echo "FAILED TRANSACTIONS - 5 KEY LINES EXTRACTION"
echo "Generated: $(date)"
echo "======================================================="

# Check if .log files exist
if ! ls *.log >/dev/null 2>&1; then
    echo "ERROR: No .log files found in current directory"
    exit 1
fi

echo "Extracting 5 key lines for each failed transaction..."
echo ""

# Create temporary file
tmpfile=$(mktemp)
failed_count=0

# Process each log file
for logfile in *.log; do
    echo "Processing $logfile..."
    
    # Extract TransactionManager blocks with FAILED patterns
    awk '
    /^<log.*realm="org.jpos.transaction.TransactionManager"/ {
        in_txnmgr_block = 1
        block_content = ""
        has_failed = 0
        
        # Initialize tracking variables
        txn_id = ""
        txn_type = ""
        first_failed = ""
        last_failed = ""
        use_rc = ""
        
        # Extract timestamp from log tag
        match($0, /at="([^"]+)"/, ts_arr)
        timestamp = ts_arr[1]
        
        block_content = $0 "\n"
        next
    }
    
    in_txnmgr_block {
        block_content = block_content $0 "\n"
        
        # Extract TXN_ID
        if (/TXN_ID:/ && txn_id == "") {
            match($0, /TXN_ID: ([^\n\r]+)/, id_arr)
            txn_id = id_arr[1]
        }
        
        # Extract TXNNAME
        if (/TXNNAME:/ && txn_type == "") {
            match($0, /TXNNAME: ([^\n\r]+)/, txn_arr)
            txn_type = txn_arr[1]
        }
        
        # Track FAILED occurrences
        if (/FAILED/ || /\[FAILED\]/ || /result.*FAILURE/) {
            has_failed = 1
            
            # Capture first FAILED occurrence
            if (first_failed == "") {
                first_failed = $0
            }
            
            # Always update last FAILED (will be the final one)
            last_failed = $0
        }
        
        # Extract "Use RC" pattern
        if (/Use RC :/) {
            use_rc = $0
        }
    }
    
    in_txnmgr_block && /<\/log>/ {
        # Process if this block has failed patterns
        if (has_failed && txn_id != "" && txn_type != "") {
            print "=== FAILED TRANSACTION ==="
            print "File: " FILENAME
            print "Timestamp: " timestamp
            print "1. TxnID: " txn_id
            print "2. TxnType: " txn_type
            print "3. First FAILED: " first_failed
            print "4. Last FAILED: " last_failed
            if (use_rc != "") {
                print "5. Use RC: " use_rc
            } else {
                print "5. Use RC: [NOT FOUND]"
            }
            print "==========================="
            print ""
            
            failed_count++
        }
        
        # Reset for next block
        in_txnmgr_block = 0
        block_content = ""
        has_failed = 0
        txn_id = ""
        txn_type = ""
        first_failed = ""
        last_failed = ""
        use_rc = ""
        timestamp = ""
    }
    
    ' "$logfile" >> "$tmpfile"
done

echo ""
echo "======================================================="
echo "RESULTS SUMMARY"
echo "======================================================="

if [ -s "$tmpfile" ]; then
    cat "$tmpfile"
    
    echo ""
    echo "======================================================="
    echo "ANALYSIS COMPLETE"
    echo "======================================================="
    echo "Total failed transactions found: $failed_count"
    
    # Create TSV output for easy analysis
    echo ""
    echo "TSV FORMAT OUTPUT:"
    echo "Timestamp	File	TxnID	TxnType	First_FAILED	Last_FAILED	Use_RC"
    
    awk '
    /^=== FAILED TRANSACTION ===/ { in_failed_block = 1; next }
    /^===========================/ { in_failed_block = 0; next }
    
    in_failed_block && /^File:/ { file = substr($0, 7) }
    in_failed_block && /^Timestamp:/ { timestamp = substr($0, 12) }
    in_failed_block && /^1\. TxnID:/ { txn_id = substr($0, 11) }
    in_failed_block && /^2\. TxnType:/ { txn_type = substr($0, 13) }
    in_failed_block && /^3\. First FAILED:/ { first_failed = substr($0, 18) }
    in_failed_block && /^4\. Last FAILED:/ { last_failed = substr($0, 17) }
    in_failed_block && /^5\. Use RC:/ { 
        use_rc = substr($0, 11)
        
        # Output TSV line
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", timestamp, file, txn_id, txn_type, first_failed, last_failed, use_rc
        
        # Reset variables
        file = ""; timestamp = ""; txn_id = ""; txn_type = ""; first_failed = ""; last_failed = ""; use_rc = ""
    }
    ' "$tmpfile"
    
else
    echo "No failed transactions found in TransactionManager blocks."
    echo ""
    echo "This could mean:"
    echo "1. All transactions completed successfully"
    echo "2. Failures are logged with different patterns"
    echo "3. The search criteria need refinement"
fi

# Save detailed output
cp "$tmpfile" failed_5lines_analysis.txt
echo ""
echo "Detailed analysis saved to: failed_5lines_analysis.txt"

# Cleanup
rm -f "$tmpfile"

echo ""
echo "======================================================="
echo "EXTRACTION COMPLETE - $(date)"
echo "======================================================="