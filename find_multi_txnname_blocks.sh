#!/bin/bash

# Find log blocks with multiple "Processing TXNNAME:" entries
# This helps identify composite transactions or nested calls

echo "======================================================"
echo "Finding Log Blocks with Multiple TXNNAME Entries"
echo "Generated: $(date)"
echo "======================================================"

# Check if log files exist
if ! ls *.log >/dev/null 2>&1; then
    echo "ERROR: No .log files found in current directory"
    exit 1
fi

echo -e "\nAnalyzing all log files for multi-TXNNAME blocks...\n"

# Create temporary files
tmpfile=$(mktemp)
block_file=$(mktemp)

total_blocks=0
multi_txnname_blocks=0

# Process each log file
for logfile in *.log; do
    echo "Processing $logfile..."
    
    # Extract complete log blocks and count TXNNAME in each
    awk '
    /^<log.*TransactionManager/ {
        if (in_log) {
            # Process previous block
            txnname_count = gsub(/Processing TXNNAME:/, "&", log_content)
            if (txnname_count > 1) {
                print "=== MULTI-TXNNAME BLOCK (Count: " txnname_count ") ==="
                print log_content
                print "=== END BLOCK ==="
                print ""
            }
            total_blocks++
            if (txnname_count > 1) multi_blocks++
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
        txnname_count = gsub(/Processing TXNNAME:/, "&", log_content)
        if (txnname_count > 1) {
            print "=== MULTI-TXNNAME BLOCK (Count: " txnname_count ") ==="
            print log_content
            print "=== END BLOCK ==="
            print ""
        }
        total_blocks++
        if (txnname_count > 1) multi_blocks++
        in_log = 0
    }
    
    END {
        print "STATS for " FILENAME ":"
        print "Total blocks: " total_blocks
        print "Multi-TXNNAME blocks: " multi_blocks
        print ""
    }
    ' "$logfile" >> "$tmpfile"
done

echo "======================================================"
echo "SUMMARY ANALYSIS"
echo "======================================================"

# Count total occurrences
echo "Results:"
if [ -s "$tmpfile" ]; then
    # Count multi-TXNNAME blocks
    multi_count=$(grep -c "=== MULTI-TXNNAME BLOCK" "$tmpfile")
    echo "Found $multi_count log blocks with multiple TXNNAME entries"
    
    if [ $multi_count -gt 0 ]; then
        echo -e "\nShowing first 5 multi-TXNNAME blocks:\n"
        head -100 "$tmpfile"
        
        echo -e "\n======================================================"
        echo "UNIQUE TXNNAME PATTERNS IN MULTI-BLOCKS"
        echo "======================================================"
        
        # Extract and analyze the TXNNAME patterns
        grep "Processing TXNNAME:" "$tmpfile" | \
        awk '{
            # Extract the transaction name
            match($0, /Processing TXNNAME: ([^,]+)/, arr)
            print arr[1]
        }' | sort | uniq -c | sort -nr
        
    else
        echo "No multi-TXNNAME blocks found - each log block contains exactly one transaction type"
    fi
else
    echo "No TransactionManager log blocks found in any files"
fi

# Cleanup
rm -f "$tmpfile" "$block_file"

echo -e "\nAnalysis complete!"