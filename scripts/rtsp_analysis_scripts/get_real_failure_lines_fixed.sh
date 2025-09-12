#!/bin/bash
# Caching/output integrated via scripts/helper/cache_utils.sh
# For template usage, see scripts/helper/cache_template.sh

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

# Prefer GNU awk if available (macOS compatibility)
if command -v gawk >/dev/null 2>&1; then AWK="gawk"; else AWK="awk"; fi

# Logs directory is chosen interactively at runtime (no flags/env required)

# Always prompt for logs dir (default to existing LOGDIR or rtsp_logs)
while :; do
  read -r -p "Enter path to rtsp_q2 log repo (directory). Files must match rtsp_q2-*.log: " LOGDIR
  if [ -z "$LOGDIR" ]; then
    echo "Path is required."
    continue
  fi
  set -- "$LOGDIR"/rtsp_q2-*.log
  if [ "$1" = "$LOGDIR/rtsp_q2-*.log" ] || [ $# -eq 0 ]; then
    echo "ERROR: No rtsp_q2-*.log files found in $LOGDIR"
    continue
  fi
  break
done

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

# Collect log files
# Files are now in "$@" from the prompt validation above

echo "Counting total transactions and extracting failures..."
echo ""

# Create temporary files
tmpfile=$(mktemp)
total_txns_file=$(mktemp)
abort_count=0
total_txn_count=0

# Process each log file
for logfile in "$@"; do
    echo "Processing $logfile..."
    
    # Extract TransactionManager blocks and count total + failures
    "$AWK" -v abort_count_var="$abort_count" -v total_txn_var="$total_txn_count" '
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
        
        # Extract EXTRC (traditional format)
        if (/EXTRC:/) {
            match($0, /EXTRC: ([^\n\r]+)/, extrc_arr)
            if (extrc_arr[1] != "") {
                if (extrc_line == "") {
                    extrc_line = extrc_arr[1]
                } else {
                    # Multiple EXTRC, append with separator
                    extrc_line = extrc_line "; " extrc_arr[1]
                }
            }
        }
        
        # Extract error codes from XML format and categorize by source
        if (/errCode="[^"]*"/) {
            match($0, /errCode="([^"]*)"/, err_arr)
            if (err_arr[1] != "" && err_arr[1] != "00") {
                # Check if this is from external systems (PSO/CBS/UPI/TOMAS)
                if ((txn_type ~ /^PSO\./) || (/CBS/) || (/UPI/) || (/TOMAS/) || (/orgCode="/) || (/orgStatus="/)) {
                    if (extrc_line == "") {
                        extrc_line = "XML errCode: " err_arr[1]
                    }
                } else {
                    # Internal system error - UseRC
                    if (use_rc_line == "") {
                        use_rc_line = "XML errCode: " err_arr[1]
                    }
                }
            }
        }
        
        # Collect actual failure patterns (key error indicators)
        if ((/java\.lang\.NullPointerException/) ||
            (/Invalid Request Body/) ||
            (/BLException.*invalid/) ||
            (/TARGET_POJO is NULL/) ||
            (/<message>.*<\/message>/ && !/Transaction Successful/) ||
            (/Count check.*FAILED/) ||
            (/Use RC :/ && !/Use RC : 00/) ||
            (/errCode="[^0][^"]+"/) ||  # XML errCode not starting with 0
            (/result="FAILURE"/) ||
            (/respCode="[^0][^"]+"/) ||  # XML respCode not starting with 0
            (/<Resp.*result="FAILURE"/) ||
            (/orgStatus="FAILURE"/)) {
            
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
        
        # Also extract response codes from XML format and categorize by source
        if (/respCode="[^"]*"/) {
            match($0, /respCode="([^"]*)"/, resp_arr)
            if (resp_arr[1] != "" && resp_arr[1] != "00") {
                # Check if this is from external systems (PSO/CBS/UPI/TOMAS)
                if ((txn_type ~ /^PSO\./) || (/CBS/) || (/UPI/) || (/TOMAS/) || (/orgCode="/) || (/orgStatus="/)) {
                    if (extrc_line == "") {
                        extrc_line = "XML respCode: " resp_arr[1]
                    }
                } else {
                    # Internal system error - UseRC
                    if (use_rc_line == "") {
                        use_rc_line = "XML respCode: " resp_arr[1]
                    }
                }
            }
        }
        
        # Extract error codes from JSON format
        if (/"errCode":"[^"]*"/) {
            match($0, /"errCode":"([^"]*)"/, json_err_arr)
            if (json_err_arr[1] != "" && json_err_arr[1] != "00") {
                # Check if this is from external systems (PSO/CBS/UPI/TOMAS)
                if ((txn_type ~ /^PSO\./) || (/CBS/) || (/UPI/) || (/TOMAS/)) {
                    if (extrc_line == "") {
                        extrc_line = "JSON errCode: " json_err_arr[1]
                    }
                } else {
                    # Internal system error (BACKOFFICE, APP internal) - UseRC
                    if (use_rc_line == "") {
                        use_rc_line = "JSON errCode: " json_err_arr[1]
                    }
                }
            }
        }
        
        # Extract RC field (usually from original transaction context)
        if (/^      RC: / || /,rc=/ || /"rc":"/ || /"orgRc":"/) {
            rc_value = ""
            if (match($0, /^      RC: (.+)$/, rc_match)) {
                rc_value = rc_match[1]
            } else if (match($0, /,rc=([^,}]+)/, rc_match)) {
                rc_value = rc_match[1]
            } else if (match($0, /"rc":"([^"]+)"/, rc_match)) {
                rc_value = rc_match[1]
            } else if (match($0, /"orgRc":"([^"]+)"/, rc_match)) {
                rc_value = rc_match[1]
            }
            
            if (rc_value != "" && rc_value != "00" && rc_value != "null" && rc_value != "<null>") {
                # For BACKOFFICE.ResolveStatus, RC usually comes from original external transaction
                if (txn_type ~ /^BACKOFFICE\./) {
                    # Avoid duplicates
                    if (extrc_line == "" || index(extrc_line, rc_value) == 0) {
                        if (extrc_line == "") {
                            extrc_line = "Original RC: " rc_value
                        } else {
                            extrc_line = extrc_line "; Original RC: " rc_value
                        }
                    }
                } else {
                    # For other transaction types, treat as UseRC if internal, ExtRC if external
                    if ((txn_type ~ /^PSO\./) || (/CBS/) || (/UPI/) || (/TOMAS/)) {
                        if (extrc_line == "") {
                            extrc_line = "RC: " rc_value
                        }
                    } else {
                        if (use_rc_line == "") {
                            use_rc_line = "RC: " rc_value
                        }
                    }
                }
            }
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
            
            if (extrc_line != "") {
                print "5. Ext RC: " extrc_line
            } else {
                print "5. Ext RC: [NOT FOUND]"
            }
            
            print "6. Block Type: ABORT"
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
    total_from_file=$("$AWK" '/^<log.*realm="org.jpos.transaction.TransactionManager".*/ { count++ } END { print count+0 }' "$logfile")
    total_txn_count=$((total_txn_count + total_from_file))
    
    # Count abort transactions from this file
    abort_from_file=$("$AWK" 'BEGIN { count = 0 } /<log.*realm="org.jpos.transaction.TransactionManager".*>/ { in_block = 1; has_abort = 0 } in_block && /<abort>/ { has_abort = 1 } in_block && /<\/log>/ { if (has_abort) count++; in_block = 0; has_abort = 0 } END { print count }' "$logfile")
    abort_count=$((abort_count + abort_from_file))
done

echo ""
echo "======================================================="
echo "CBDC TRANSACTION FAILURE ANALYSIS SUMMARY"
echo "======================================================="

# Count unique transaction IDs
unique_txn_count=$("$AWK" '/^1\. TxnID:/ { print substr($0, 11) }' "$tmpfile" | sort -u | wc -l)

# Count transactions with no failure reasons (no UseRC and no ExtRC)
no_failure_reason_count=0
if [ -s "$tmpfile" ]; then
    no_failure_reason_count=$("$AWK" '
    BEGIN { 
        in_block = 0; count = 0
        has_use_rc = 0; has_extrc = 0
    }
    /^=== ABORT TRANSACTION ===/ { 
        in_block = 1; has_use_rc = 0; has_extrc = 0
        next 
    }
    in_block {
        if ($0 ~ /Use RC :/ && $0 !~ /\[NOT FOUND\]/) has_use_rc = 1
        if ($0 ~ /EXTRC:/ && $0 !~ /^[ \t]*$/) has_extrc = 1
    }
    in_block && /^=========================/ { 
        if (has_use_rc == 0 && has_extrc == 0) count++
        in_block = 0 
    }
    END { print count }
    ' "$tmpfile")
fi

echo "Total transactions processed: $total_txn_count"
echo "Total failed transactions: $abort_count"
echo "Unique failed transaction IDs: $unique_txn_count"
echo "Transactions with no failure reasons: $no_failure_reason_count"

# Display based on selected mode
if [ "$DISPLAY_MODE" = "tsv" ]; then
    # TSV Table Format
    echo ""
    echo "TSV TABLE FORMAT:"
    echo "================="
    echo -e "TxnID\tUseRC1\tUseRC2\tUseRC3\tUseRC4\tExtRC1\tExtRC2"
    
    if [ -s "$tmpfile" ]; then
        "$AWK" '
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
            # Look for Use RC patterns in format "4. Use RC: content"
            if ($0 ~ /^4\. Use RC: / && use_rc_count < 4 && $0 !~ /\[NOT FOUND\]/) {
                if (match($0, /^4\. Use RC: (.+)$/, rc_match)) {
                    use_rc_count++
                    use_rc[use_rc_count] = rc_match[1]
                }
            }
            # Look for Ext RC patterns in format "5. Ext RC: content"
            if ($0 ~ /^5\. Ext RC: / && extrc_count < 2 && $0 !~ /\[NOT FOUND\]/) {
                if (match($0, /^5\. Ext RC: (.+)$/, extrc_match)) {
                    extrc_count++
                    extrc[extrc_count] = extrc_match[1]
                }
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
        "$AWK" '
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

# ---------------- Output management with caching ----------------

# Hash helpers
hash_cmd=""
if command -v sha256sum >/dev/null 2>&1; then hash_cmd="sha256sum"; fi
if [ -z "$hash_cmd" ] && command -v shasum >/dev/null 2>&1; then hash_cmd="shasum -a 256"; fi
if [ -z "$hash_cmd" ] && command -v md5sum >/dev/null 2>&1; then hash_cmd="md5sum"; fi

calc_files_hash() {
  # stable ordering by path
  for f in "$@"; do
    printf "%s\n" "$f"
  done | sort | while read -r f; do
    $hash_cmd "$f" 2>/dev/null | awk '{print $1}'
  done | $hash_cmd 2>/dev/null | awk '{print $1}'
}

calc_file_hash() {
  $hash_cmd "$1" 2>/dev/null | awk '{print $1}'
}

meta_dir=".cache"
mkdir -p "$meta_dir"
meta_file="$meta_dir/get_real_failure_lines_fixed.meta"

input_hash="$(calc_files_hash "$@")"
script_path="$0"
script_hash="$(calc_file_hash "$script_path")"
ts="$(date +%Y%m%d_%H%M%S)"

last_input_hash=""
last_script_hash=""
last_abort_file=""
last_tsv_file=""
if [ -f "$meta_file" ]; then
  # shellcheck disable=SC1090
  . "$meta_file"
fi

create_outputs="no"
if [ "$input_hash" != "$last_input_hash" ]; then
  create_outputs="yes"
elif [ "$script_hash" != "$last_script_hash" ]; then
  create_outputs="yes"
else
  create_outputs="no"
fi

if [ "$create_outputs" = "yes" ]; then
  # remove previous outputs for this script (if any) before creating new
  . scripts/helper/cache_utils.sh
  CACHE_LAST_OUTPUTS=""
  if [ -f ".cache/get_real_failure_lines_fixed.meta" ]; then
    # shellcheck disable=SC1090
    . .cache/get_real_failure_lines_fixed.meta
  fi
  for p in $CACHE_LAST_OUTPUTS; do rm -f "$p" 2>/dev/null || true; done
  abort_file="abort_failures_${ts}.txt"
  tsv_file="table_failed_txn_${ts}.txt"

  # Save detailed analysis
  cp "$tmpfile" "$abort_file"
  echo ""
  echo "Detailed analysis saved to: $abort_file"

  # Generate TSV table
  echo "Creating TSV table file: $tsv_file"
  echo ""
  echo -e "TxnID\tUseRC1\tUseRC2\tUseRC3\tUseRC4\tExtRC1\tExtRC2" > "$tsv_file"
  if [ -s "$tmpfile" ]; then
    "$AWK" '
    BEGIN { in_block = 0 }
    /^=== ABORT TRANSACTION ===/ { in_block = 1; txn_id=""; use_rc_count=0; extrc_count=0; for(i=1;i<=4;i++)use_rc[i]=""; for(i=1;i<=2;i++)extrc[i]=""; next }
    in_block && /^1\. TxnID:/ { txn_id = substr($0, 11) }
    in_block {
      if ($0 ~ /^4\. Use RC: / && use_rc_count < 4 && $0 !~ /\[NOT FOUND\]/) {
        if (match($0, /^4\. Use RC: (.+)$/, rc_match)) { use_rc_count++; use_rc[use_rc_count] = rc_match[1] }
      }
      if ($0 ~ /^5\. Ext RC: / && extrc_count < 2 && $0 !~ /\[NOT FOUND\]/) {
        if (match($0, /^5\. Ext RC: (.+)$/, extrc_match)) { extrc_count++; extrc[extrc_count] = extrc_match[1] }
      }
    }
    in_block && /^=========================/ { printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", txn_id, use_rc[1], use_rc[2], use_rc[3], use_rc[4], extrc[1], extrc[2]; in_block = 0 }
    ' "$tmpfile" >> "$tsv_file"
  fi
  echo "TSV table saved to: $tsv_file"

  # Update meta (also track outputs for rotation on next runs)
  {
    echo "last_input_hash='$input_hash'"
    echo "last_script_hash='$script_hash'"
    echo "CACHE_LAST_OUTPUTS='scripts/output/$abort_file scripts/output/$tsv_file'"
  } > "$meta_file"
else
  # Inputs & script unchanged: rotate outputs to new timestamp (no recompute)
  . scripts/helper/cache_utils.sh
  CACHE_LAST_OUTPUTS=""
  if [ -f "$meta_file" ]; then . "$meta_file"; fi
  CACHE_OUT_DIR="scripts/output"; CACHE_TS="$ts"
  cache_duplicate_outputs
  {
    echo "last_input_hash='$input_hash'"
    echo "last_script_hash='$script_hash'"
    echo "CACHE_LAST_OUTPUTS='$CACHE__OUTPUTS'"
  } > "$meta_file"
  echo "Rotated outputs to new timestamp: $CACHE__OUTPUTS"
fi

# Cleanup
rm -f "$tmpfile"

echo ""
echo "======================================================="
echo "ANALYSIS COMPLETE - $(date)"
echo "======================================================="
