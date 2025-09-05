#!/bin/bash

# get_real_failure_lines.sh - Extract actual failure content from ABORT blocks only
#
# USAGE OPTIONS:
# ./get_real_failure_lines_fixed.sh [OPTIONS]
#
# OPTIONS:
#   --summary-only    Show only summary statistics and failure patterns
#   --tsv-table       Show TSV table with TxnID, UseRC, ExtRC, TransactionLeg  
#   --detailed        Show full detailed analysis (default)
#   --help            Show this help message
#
# EXAMPLES:
#   ./get_real_failure_lines_fixed.sh --summary-only
#   ./get_real_failure_lines_fixed.sh --tsv-table
#   ./get_real_failure_lines_fixed.sh --detailed

# Parse command line options
DISPLAY_MODE="detailed"
case "$1" in
    --summary-only)
        DISPLAY_MODE="summary"
        ;;
    --tsv-table)
        DISPLAY_MODE="tsv"
        ;;
    --detailed)
        DISPLAY_MODE="detailed"
        ;;
    --help)
        echo "CBDC Log Analysis - Failure Extraction Tool"
        echo
        echo "USAGE:"
        echo "  $0 [OPTIONS]"
        echo
        echo "OPTIONS:"
        echo "  --summary-only    Show only summary statistics and failure patterns"
        echo "  --tsv-table       Show TSV table with TxnID, UseRC, ExtRC, TransactionLeg"
        echo "  --detailed        Show full detailed analysis (default)"
        echo "  --help            Show this help message"
        echo
        echo "EXAMPLES:"
        echo "  $0 --summary-only"
        echo "  $0 --tsv-table"
        echo "  $0 --detailed"
        exit 0
        ;;
esac

echo "======================================================="
echo "CBDC TRANSACTION FAILURE ANALYSIS"
echo "Display Mode: $DISPLAY_MODE"
echo "Generated: $(date)"
echo "======================================================="

# Check if .log files exist
if ! ls *.log >/dev/null 2>&1; then
    echo "ERROR: No .log files found in current directory"
    exit 1
fi

echo "Counting total transactions and extracting failures..."
echo ""

# Create temporary files
tmpfile=$(mktemp)
total_txns_file=$(mktemp)
abort_count=0
total_txn_count=0

# Process each log file
for logfile in *.log; do
    echo "Processing $logfile..."
    
    # Extract TransactionManager blocks and count total + failures
    awk -v abort_count_var="$abort_count" -v total_txn_var="$total_txn_count" '
    /^<log.*realm="org.jpos.transaction.TransactionManager".*/ {
        in_txnmgr_block = 1
        block_content = ""
        is_abort_block = 0
        total_transactions++
        
        # Initialize tracking variables
        txn_id = ""
        txn_type = ""
        txn_leg = ""
        failure_lines = ""
        use_rc_line = ""
        extrc_line = ""
        
        # Extract timestamp
        match($0, /at="([^"]+)"/, ts_arr)
        timestamp = ts_arr[1]
        
        block_content = $0 "\n"
        next
    }
    
    in_txnmgr_block {
        block_content = block_content $0 "\n"
        
        # Check if this is an ABORT block
        if (/<abort>/) {
            is_abort_block = 1
        }
        
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
        
        # Extract TXN_LEG_TYPE
        if (/TXN_LEG_TYPE:/ && txn_leg == "") {
            match($0, /TXN_LEG_TYPE: ([^\n\r]+)/, leg_arr)
            txn_leg = leg_arr[1]
        }
        
        # Extract EXTRC
        if (/EXTRC:/ && extrc_line == "") {
            match($0, /EXTRC: ([^\n\r]+)/, extrc_arr)
            extrc_line = extrc_arr[1]
        }
        
        # Collect actual failure patterns (key error indicators)
        if ((/java\.lang\.NullPointerException/) ||
            (/Invalid Request Body/) ||
            (/BLException.*invalid/) ||
            (/TARGET_POJO is NULL/) ||
            (/<message>.*<\/message>/ && !/Transaction Successful/) ||
            (/Count check.*FAILED/) ||
            (/Use RC :/ && !/Use RC : 00/)) {
            
            # Add to failure lines collection
            if (failure_lines == "") {
                failure_lines = $0
            } else {
                failure_lines = failure_lines "\n    " $0
            }
        }
        
        # Extract Use RC lines with errors (not success)
        if (/Use RC :/ && !/Use RC : 00/ && !/Use RC : 0,/) {
            use_rc_line = $0
        }
    }
    
    in_txnmgr_block && /<\/log>/ {
        # Only process ABORT blocks
        if (is_abort_block && txn_id != "" && txn_type != "") {
            print "=== ABORT TRANSACTION ===" 
            print "File: " FILENAME
            print "Timestamp: " timestamp
            print "1. TxnID: " txn_id
            print "2. TxnType: " txn_type
            
            if (failure_lines != "") {
                print "3. Failure Lines:"
                print "    " failure_lines
            } else {
                print "3. Failure Lines: [Check full block - may be abort without specific failure text]"
            }
            
            if (use_rc_line != "") {
                print "4. Use RC: " use_rc_line
            } else {
                print "4. Use RC: [NOT FOUND]"
            }
            
            print "5. Block Type: ABORT"
            print "========================="
            print ""
            
            abort_count++
        }
        
        # Reset for next block
        in_txnmgr_block = 0
        is_abort_block = 0
        txn_id = ""
        txn_type = ""
        txn_leg = ""
        failure_lines = ""
        use_rc_line = ""
        extrc_line = ""
        timestamp = ""
    }
    
    ' "$logfile" >> "$tmpfile"
    
    # Count total transactions from this file
    total_from_file=$(awk '/^<log.*realm="org.jpos.transaction.TransactionManager".*/ { count++ } END { print count+0 }' "$logfile")
    total_txn_count=$((total_txn_count + total_from_file))
    
    # Count abort transactions from this file
    abort_from_file=$(awk 'BEGIN { count = 0 } /<log.*realm="org.jpos.transaction.TransactionManager".*>/ { in_block = 1; has_abort = 0 } in_block && /<abort>/ { has_abort = 1 } in_block && /<\/log>/ { if (has_abort) count++; in_block = 0; has_abort = 0 } END { print count }' "$logfile")
    abort_count=$((abort_count + abort_from_file))
done

echo ""
echo "======================================================="
echo "CBDC TRANSACTION FAILURE ANALYSIS SUMMARY"
echo "======================================================="

# Count unique transaction IDs
unique_txn_count=$(awk '/^1\. TxnID:/ { print substr($0, 11) }' "$tmpfile" | sort -u | wc -l)

echo "Total transactions processed: $total_txn_count"
echo "Total failed transactions: $abort_count"
echo "Unique failed transaction IDs: $unique_txn_count"

# Display based on selected mode
if [ "$DISPLAY_MODE" = "tsv" ]; then
    # TSV Table Format
    echo ""
    echo "TSV TABLE FORMAT:"
    echo "================="
    echo -e "TxnID\tUseRC1\tUseRC2\tUseRC3\tUseRC4\tExtRC1\tExtRC2"
    
    if [ -s "$tmpfile" ]; then
        awk '
        BEGIN { 
            in_block = 0
        }
        /^=== ABORT TRANSACTION ===/ { 
            in_block = 1
            txn_id = ""
            use_rc_count = 0
            extrc_count = 0
            for (i = 1; i <= 4; i++) use_rc[i] = ""
            for (i = 1; i <= 2; i++) extrc[i] = ""
            next 
        }
        in_block && /^1\. TxnID:/ { 
            txn_id = substr($0, 11) 
        }
        in_block {
            # Look for Use RC patterns anywhere in the block
            if ($0 ~ /Use RC :/ && use_rc_count < 4) {
                if (match($0, /Use RC : ([^,\n\r]+)/, rc_match)) {
                    use_rc_count++
                    use_rc[use_rc_count] = rc_match[1]
                }
            }
            # Look for EXTRC patterns anywhere in the block
            if ($0 ~ /EXTRC:/ && extrc_count < 2) {
                extrc_count++
                extrc_value = substr($0, match($0, /EXTRC:/) + 6)
                gsub(/^[ \t]+|[ \t]+$/, "", extrc_value)
                extrc[extrc_count] = extrc_value
            }
        }
        in_block && /^=========================/ { 
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", txn_id, use_rc[1], use_rc[2], use_rc[3], use_rc[4], extrc[1], extrc[2]
            in_block = 0 
        }
        ' "$tmpfile"
    fi

elif [ "$DISPLAY_MODE" = "summary" ]; then
    # Summary Only Mode
    echo ""
    echo "FAILURE GROUPING BY FIRST FAILURE PATTERN:"
    echo "==========================================="
    if [ -s "$tmpfile" ]; then
        # Extract first failure line for each transaction and group by pattern
        awk '
        BEGIN { 
            in_block = 0
            txn_id = ""
            first_failure = ""
        }
        /^=== ABORT TRANSACTION ===/ { 
            in_block = 1
            txn_id = ""
            first_failure = ""
            next 
        }
        in_block && /^1\. TxnID:/ { 
            txn_id = substr($0, 11)
        }
        in_block && /^3\. Failure Lines:/ {
            getline
            if ($0 !~ /\[Check full block/) {
                # Get the first actual failure line (remove leading spaces)
                first_failure = $0
                gsub(/^    /, "", first_failure)
                
                # Clean up common variable parts to group similar patterns
                gsub(/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}/, "TIMESTAMP", first_failure)
                gsub(/[0-9]+\/[0-9]+ :/, "COUNT/LIMIT :", first_failure)
                gsub(/TXN_ID: [^,]+/, "TXN_ID: <ID>", first_failure)
                gsub(/"[^"]*"/, "<VALUE>", first_failure)
                
                if (first_failure != "" && txn_id != "") {
                    failure_groups[first_failure]++
                }
            }
        }
        in_block && /^=========================/ { 
            in_block = 0 
        }
        END {
            for (pattern in failure_groups) {
                printf "%3d  %s\n", failure_groups[pattern], pattern
            }
        }
        ' "$tmpfile" | sort -nr
    else
        echo "No failure patterns found."
    fi

else
    # Detailed Mode (default)
    echo ""
    echo "FAILURE GROUPING BY FIRST FAILURE PATTERN:"
    echo "==========================================="
    if [ -s "$tmpfile" ]; then
        # Extract first failure line for each transaction and group by pattern
        awk '
        BEGIN { 
            in_block = 0
            txn_id = ""
            first_failure = ""
        }
        /^=== ABORT TRANSACTION ===/ { 
            in_block = 1
            txn_id = ""
            first_failure = ""
            next 
        }
        in_block && /^1\. TxnID:/ { 
            txn_id = substr($0, 11)
        }
        in_block && /^3\. Failure Lines:/ {
            getline
            if ($0 !~ /\[Check full block/) {
                # Get the first actual failure line (remove leading spaces)
                first_failure = $0
                gsub(/^    /, "", first_failure)
                
                # Clean up common variable parts to group similar patterns
                gsub(/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}/, "TIMESTAMP", first_failure)
                gsub(/[0-9]+\/[0-9]+ :/, "COUNT/LIMIT :", first_failure)
                gsub(/TXN_ID: [^,]+/, "TXN_ID: <ID>", first_failure)
                gsub(/"[^"]*"/, "<VALUE>", first_failure)
                
                if (first_failure != "" && txn_id != "") {
                    failure_groups[first_failure]++
                }
            }
        }
        in_block && /^=========================/ { 
            in_block = 0 
        }
        END {
            for (pattern in failure_groups) {
                printf "%3d  %s\n", failure_groups[pattern], pattern
            }
        }
        ' "$tmpfile" | sort -nr
    else
        echo "No failure patterns found."
    fi

    echo ""
    echo "======================================================="
    echo "DETAILED TRANSACTION FAILURE ANALYSIS"
    echo "======================================================="

    if [ -s "$tmpfile" ]; then
        cat "$tmpfile"
    else
        echo "No ABORT (failed) transactions found."
        echo "This means all TransactionManager transactions completed successfully."
    fi
fi

# Save output
cp "$tmpfile" abort_failures.txt
echo ""
echo "Detailed analysis saved to: abort_failures.txt"

# Cleanup
rm -f "$tmpfile"

echo ""
echo "======================================================="
echo "ANALYSIS COMPLETE - $(date)"
echo "======================================================="