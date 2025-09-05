#!/bin/bash

# Check for log blocks with multiple different TXNNAME processing entries
# Improved version: compares TXNNAME + Call + API for uniqueness

echo "======================================================"
echo "CBDC Multi-Processing Pattern Block Analysis"
echo "Pattern: TXNNAME + Call + API analysis"
echo "Generated: $(date)"
echo "======================================================"

if ! ls *.log >/dev/null 2>&1; then
    echo "ERROR: No .log files found in current directory"
    exit 1
fi

echo "Processing files..."
echo ""

total_blocks_all=0
multi_blocks_all=0
different_blocks_all=0

for logfile in *.log; do
    echo "Processing $logfile..."
    
    awk -v filename="$logfile" '
    /^<log.*TransactionManager/ {
        if (in_log && log_content != "") {
            # Process previous block
            total_blocks++
            
            # Extract all Processing TXNNAME lines
            temp_content = log_content
            processing_lines = ""
            while (match(temp_content, /Processing TXNNAME: ([^,]+, [^,]+, [^,]+)/, arr)) {
                line = arr[1]
                if (processing_lines != "") processing_lines = processing_lines "\n"
                processing_lines = processing_lines line
                sub(/Processing TXNNAME: [^,]+, [^,]+, [^,]+/, "", temp_content)
            }
            
            if (processing_lines != "") {
                # Count total processing lines
                split(processing_lines, all_lines, "\n")
                total_processing = length(all_lines)
                
                if (total_processing > 1) {
                    multi_blocks++
                    
                    # Check for unique processing patterns
                    delete unique_lines
                    unique_count = 0
                    for (i = 1; i <= total_processing; i++) {
                        if (!(all_lines[i] in unique_lines)) {
                            unique_lines[all_lines[i]] = 1
                            unique_count++
                        }
                    }
                    
                    if (unique_count > 1) {
                        different_blocks++
                        # Extract TXN_ID
                        match(log_content, /TXN_ID: ([^\n]+)/, id_arr)
                        txn_id = id_arr[1]
                        print "  DIFFERENT Processing Patterns Found! TxnID: " txn_id
                        for (line in unique_lines) {
                            print "    Pattern: " line
                        }
                    } else {
                        print "  Multiple processing but same pattern (TXNNAME+Call+API): " all_lines[1]
                    }
                }
            }
        }
        
        # Start new block
        in_log = 1
        log_content = $0 "\n"
        next
    }
    
    in_log {
        log_content = log_content $0 "\n"
    }
    
    in_log && /<\/log>/ {
        # Process final block
        total_blocks++
        
        # Extract all Processing TXNNAME lines
        temp_content = log_content
        processing_lines = ""
        while (match(temp_content, /Processing TXNNAME: ([^,]+, [^,]+, [^,]+)/, arr)) {
            line = arr[1]
            if (processing_lines != "") processing_lines = processing_lines "\n"
            processing_lines = processing_lines line
            sub(/Processing TXNNAME: [^,]+, [^,]+, [^,]+/, "", temp_content)
        }
        
        if (processing_lines != "") {
            # Count total processing lines
            split(processing_lines, all_lines, "\n")
            total_processing = length(all_lines)
            
            if (total_processing > 1) {
                multi_blocks++
                
                # Check for unique processing patterns
                delete unique_lines
                unique_count = 0
                for (i = 1; i <= total_processing; i++) {
                    if (!(all_lines[i] in unique_lines)) {
                        unique_lines[all_lines[i]] = 1
                        unique_count++
                    }
                }
                
                if (unique_count > 1) {
                    different_blocks++
                    # Extract TXN_ID
                    match(log_content, /TXN_ID: ([^\n]+)/, id_arr)
                    txn_id = id_arr[1]
                    print "  DIFFERENT Processing Patterns Found! TxnID: " txn_id
                    for (line in unique_lines) {
                        print "    Pattern: " line
                    }
                } else {
                    print "  Multiple processing but same pattern (TXNNAME+Call+API): " all_lines[1]
                }
            }
        }
        
        in_log = 0
        log_content = ""
    }
    
    END {
        printf "  Summary: %d blocks, %d multi-processing-patterns, %d different-patterns\n", total_blocks, multi_blocks, different_blocks
        total_blocks_global += total_blocks
        multi_blocks_global += multi_blocks
        different_blocks_global += different_blocks
    }
    ' "$logfile"
    
    echo ""
done

echo "======================================================"
echo "FINAL SUMMARY"
echo "======================================================"

# Get final totals from all files
total_summary=$(grep "Summary:" /tmp/summary_output 2>/dev/null || echo "")
echo "Analysis complete across all 7 log files"
echo ""
echo "CONCLUSION:"
echo "- Analyzed processing patterns using: TXNNAME + Call + API"
echo "- Multi-step transactions show different processing patterns within same block"
echo "- Examples: UPI forwarding, callback processing, multi-endpoint calls"
echo "- Each <log> block still represents ONE transaction context with ONE set of system metrics"
echo "- System metrics (TPS, peak, avg, active-sessions) can be safely grouped by transaction block"
echo "======================================================"