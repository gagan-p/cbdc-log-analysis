#!/bin/bash

# extract_real_failures.sh - Extract 5 key lines for actual transaction processing failures
# Focus on real transaction failures, not historical data in responses

echo "======================================================="
echo "REAL TRANSACTION PROCESSING FAILURES - 5 KEY LINES"
echo "Generated: $(date)"
echo "======================================================="

# Check if .log files exist
if ! ls *.log >/dev/null 2>&1; then
    echo "ERROR: No .log files found in current directory"
    exit 1
fi

echo "Extracting real transaction processing failures..."
echo ""

# Create temporary file
tmpfile=$(mktemp)
failed_count=0

# Process each log file
for logfile in *.log; do
    echo "Processing $logfile..."
    
    # Extract TransactionManager blocks with actual processing failures
    awk '
    /^<log.*realm="org.jpos.transaction.TransactionManager"/ {
        in_txnmgr_block = 1
        block_content = ""
        has_real_failure = 0
        
        # Initialize tracking variables
        txn_id = ""
        txn_type = ""
        first_failed = ""
        last_failed = ""
        use_rc = ""
        
        # Extract timestamp from log tag
        match($0, /at="([^"]+)"/, ts_arr)
        timestamp = ts_arr[1]
        
        # Check if this is an abort block (indicates real failure)
        is_abort = 0
        if (/<abort>/) is_abort = 1
        
        block_content = $0 "\n"
        next
    }
    
    in_txnmgr_block {
        block_content = block_content $0 "\n"
        
        # Check for abort indicator
        if (/<abort>/) is_abort = 1
        
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
        
        # Track actual processing failures (not XML responses)
        # Look for patterns that indicate real failures
        if ((/\[FAILED\]/ && !/TxnStatus.*FAILURE/) || 
            (/rule\..*\.error/) || 
            (/ABORTED/) || 
            (/result.*FAILURE/ && !/TxnStatus.*FAILURE/) ||
            (/Count check.*FAILED/) ||
            (/validation.*failed/i)) {
            
            has_real_failure = 1
            
            # Capture first real failure occurrence
            if (first_failed == "") {
                first_failed = $0
            }
            
            # Always update last failure (will be the final one)
            last_failed = $0
        }
        
        # Extract "Use RC" pattern for failures
        if (/Use RC :/ && !/Use RC : 00/) {
            use_rc = $0
        }
        
        # Also capture error RC patterns
        if (/RC : [^0]/ && !/RC : 00/) {
            if (use_rc == "") use_rc = $0
        }
    }
    
    in_txnmgr_block && /<\/log>/ {
        # Process if this block has real failures OR is an abort block
        if ((has_real_failure || is_abort) && txn_id != "" && txn_type != "") {
            print "=== REAL TRANSACTION FAILURE ==="
            print "File: " FILENAME
            print "Timestamp: " timestamp
            print "Block Type: " (is_abort ? "ABORT" : "COMMIT")
            print "1. TxnID: " txn_id
            print "2. TxnType: " txn_type
            
            if (first_failed != "") {
                print "3. First FAILED: " first_failed
            } else {
                print "3. First FAILED: [ABORT - Check transaction log for details]"
            }
            
            if (last_failed != "") {
                print "4. Last FAILED: " last_failed
            } else {
                print "4. Last FAILED: [ABORT - Check transaction log for details]"
            }
            
            if (use_rc != "") {
                print "5. Use RC: " use_rc
            } else {
                print "5. Use RC: [NOT FOUND - Check for error codes in log]"
            }
            print "================================="
            print ""
            
            failed_count++
        }
        
        # Reset for next block
        in_txnmgr_block = 0
        block_content = ""
        has_real_failure = 0
        is_abort = 0
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
    echo "Total real transaction processing failures found: $failed_count"
    
    # Create TSV output for easy analysis
    echo ""
    echo "TSV FORMAT OUTPUT:"
    echo "Timestamp	File	Block_Type	TxnID	TxnType	First_FAILED	Last_FAILED	Use_RC"
    
    awk '
    /^=== REAL TRANSACTION FAILURE ===/ { in_failed_block = 1; next }
    /^=================================/ { in_failed_block = 0; next }
    
    in_failed_block && /^File:/ { file = substr($0, 7) }
    in_failed_block && /^Timestamp:/ { timestamp = substr($0, 12) }
    in_failed_block && /^Block Type:/ { block_type = substr($0, 13) }
    in_failed_block && /^1\. TxnID:/ { txn_id = substr($0, 11) }
    in_failed_block && /^2\. TxnType:/ { txn_type = substr($0, 13) }
    in_failed_block && /^3\. First FAILED:/ { first_failed = substr($0, 18) }
    in_failed_block && /^4\. Last FAILED:/ { last_failed = substr($0, 17) }
    in_failed_block && /^5\. Use RC:/ { 
        use_rc = substr($0, 11)
        
        # Output TSV line
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", timestamp, file, block_type, txn_id, txn_type, first_failed, last_failed, use_rc
        
        # Reset variables
        file = ""; timestamp = ""; block_type = ""; txn_id = ""; txn_type = ""; first_failed = ""; last_failed = ""; use_rc = ""
    }
    ' "$tmpfile"
    
else
    echo "No real transaction processing failures found."
    echo ""
    echo "This means all TransactionManager blocks completed successfully"
    echo "(COMMIT blocks without processing errors)"
fi

# Save detailed output
cp "$tmpfile" real_failures_analysis.txt
echo ""
echo "Detailed analysis saved to: real_failures_analysis.txt"

# Cleanup
rm -f "$tmpfile"

echo ""
echo "======================================================="
echo "EXTRACTION COMPLETE - $(date)"
echo "======================================================="