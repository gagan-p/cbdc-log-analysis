#!/bin/bash
# Caching/output integrated via scripts/helper/cache_utils.sh
# For template usage, see scripts/helper/cache_template.sh

# Prefer GNU awk if available (macOS compatibility)
if command -v gawk >/dev/null 2>&1; then AWK="gawk"; else AWK="awk"; fi

# Logs directory is chosen interactively at runtime (no flags/env required)

# find_log_block_by_txnid.sh - Find complete <log>...</log> block by transaction ID
#
# USAGE: ./find_log_block_by_txnid.sh TXNID [OPTIONS]
#
# OPTIONS:
#   --count-lines    Show total line count of the block
#   --show-lines N   Show N lines at a time (interactive mode)
#   --file-only      Show only which file contains the transaction
#   --all-blocks     Show all blocks containing this TXNID (not just first match)
#   --help           Show this help

if [ $# -eq 0 ] || [ "$1" = "--help" ]; then
    echo "Find complete <log>...</log> block by transaction ID"
    echo
    echo "USAGE: $0 TXNID [OPTIONS]"
    echo
    echo "OPTIONS:"
    echo "  --count-lines    Show total line count of the block"
    echo "  --show-lines N   Show N lines at a time (interactive mode)"
    echo "  --file-only      Show only which file contains the transaction"
    echo "  --all-blocks     Show all blocks containing this TXNID (not just first match)"
    echo "  --help           Show this help"
    echo
    echo "EXAMPLES:"
    echo "  $0 SBICOGHlLa1qcFqSUZr6xZSUyLk2miGxPGR"
    echo "  $0 SBICOGHlLa1qcFqSUZr6xZSUyLk2miGxPGR --count-lines"
    echo "  $0 SBICOGHlLa1qcFqSUZr6xZSUyLk2miGxPGR --show-lines 10"
    echo "  $0 SBICOGHlLa1qcFqSUZr6xZSUyLk2miGxPGR --file-only"
    exit 0
fi

# Parse arguments
TXNID="$1"
shift

COUNT_LINES=""
SHOW_LINES=""
FILE_ONLY=""
ALL_BLOCKS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --count-lines)
            COUNT_LINES="1"
            ;;
        --show-lines)
            SHOW_LINES="$2"
            shift
            ;;
        --file-only)
            FILE_ONLY="1"
            ;;
        --all-blocks)
            ALL_BLOCKS="1"
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

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

# Caching: consider TXNID + options as args signature
. scripts/helper/cache_utils.sh
ARGS_SIG="TXNID=$TXNID;COUNT=$COUNT_LINES;SHOW=$SHOW_LINES;FILE_ONLY=$FILE_ONLY;ALL=$ALL_BLOCKS"
cache_prepare "find_log_block_by_txnid" "$0" "$ARGS_SIG" "$@"

if [ "$CACHE_STATUS" = "rotate" ]; then
    echo "Rotating outputs to new timestamp (no recompute)."
    cache_duplicate_outputs
    cache_save_meta
    echo "New outputs: $CACHE__OUTPUTS"
    exit 0
fi

cache_remove_last_outputs
OUT_FILE="$CACHE_OUT_DIR/find_log_block_by_txnid_${CACHE_TS}.txt"
cache_register_output "$OUT_FILE"
exec > >(tee "$OUT_FILE") 2>&1

echo "======================================================="
echo "SEARCHING FOR TRANSACTION ID: $TXNID"
echo "======================================================="

found_count=0
temp_file=$(mktemp)

# Search through all log files
for logfile in "$@"; do
    echo "Searching in $logfile..."
    
    # Find log blocks containing the TXNID
    "$AWK" -v txnid="$TXNID" -v filename="$logfile" -v all_blocks="$ALL_BLOCKS" '
    /<log[^>]*>/ {
        in_log_block = 1
        block_start_line = NR
        block_content = $0 "\n"
        contains_txnid = 0
        next
    }
    
    in_log_block {
        block_content = block_content $0 "\n"
        if ($0 ~ txnid) {
            contains_txnid = 1
        }
    }
    
    in_log_block && /<\/log>/ {
        if (contains_txnid) {
            block_end_line = NR
            block_line_count = block_end_line - block_start_line + 1
            
            print "FOUND_BLOCK|" filename "|" block_start_line "|" block_end_line "|" block_line_count
            print block_content
            print "END_BLOCK"
            
            if (all_blocks != "1") {
                exit  # Stop after first match unless --all-blocks specified
            }
        }
        in_log_block = 0
        block_content = ""
        contains_txnid = 0
    }
    ' "$logfile" >> "$temp_file"
    
    # Break if we found something and --all-blocks is not set
    if [ -s "$temp_file" ] && [ -z "$ALL_BLOCKS" ]; then
        break
    fi
done

# Process results
if [ ! -s "$temp_file" ]; then
    echo "Transaction ID '$TXNID' not found in any log files."
    rm -f "$temp_file"
    exit 1
fi

# Parse the results
while IFS='|' read -r marker filename start_line end_line line_count; do
    if [ "$marker" = "FOUND_BLOCK" ]; then
        found_count=$((found_count + 1))
        
        echo ""
        echo "======================================================="
        echo "MATCH #$found_count"
        echo "======================================================="
        echo "File: $filename"
        echo "Block lines: $start_line - $end_line"
        echo "Total lines in block: $line_count"
        
        if [ -n "$FILE_ONLY" ]; then
            echo "File containing TXNID: $filename"
            continue
        fi
        
        if [ -n "$COUNT_LINES" ]; then
            echo "Block line count: $line_count"
            continue
        fi
        
        echo ""
        echo "LOG BLOCK CONTENT:"
        echo "=================="
        
        # Read the block content
        block_content=""
        while IFS= read -r line; do
            if [ "$line" = "END_BLOCK" ]; then
                break
            fi
            block_content="$block_content$line"$'\n'
        done
        
        if [ -n "$SHOW_LINES" ]; then
            # Show N lines at a time
            echo "$block_content" | head -n "$SHOW_LINES"
            remaining_lines=$((line_count - SHOW_LINES))
            
            if [ $remaining_lines -gt 0 ]; then
                echo ""
                echo "--- Showing first $SHOW_LINES lines of $line_count total lines ---"
                echo "Remaining lines: $remaining_lines"
                echo "Use 'sed -n \"$((start_line + SHOW_LINES + 1)),$((end_line))p\" $filename' to see more"
            fi
        else
            # Show entire block
            echo "$block_content"
        fi
        
        echo ""
        echo "======================================================="
    fi
done < "$temp_file"

echo ""
echo "Search complete. Found $found_count block(s) containing TXNID: $TXNID"

# Cleanup
rm -f "$temp_file"
echo "Saved output: $OUT_FILE"
cache_prune_previous_outputs
cache_save_meta
