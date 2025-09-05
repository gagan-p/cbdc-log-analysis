#!/bin/bash

# Analyze system load metrics (TPS, peak, avg, active-sessions) per transaction type
# Correlates TXNNAME with system performance metrics

echo "======================================================"
echo "CBDC System Load Analysis by Transaction Type"
echo "Generated: $(date)"
echo "======================================================"

# Check if log files exist
if ! ls *.log >/dev/null 2>&1; then
    echo "ERROR: No .log files found in current directory"
    exit 1
fi

echo -e "\nAnalyzing system load metrics...\n"

# Create temporary files
tmpfile=$(mktemp)

# Extract transaction data with system metrics
for logfile in *.log; do
    echo "Processing $logfile..."
    
    # Extract TransactionManager entries with TXNNAME and system metrics
    awk '
    /realm="org.jpos.transaction.TransactionManager"/ {
        in_transaction = 1
        next
    }
    
    in_transaction && /Processing TXNNAME:/ {
        # Extract transaction name
        match($0, /Processing TXNNAME: ([^,]+)/, arr)
        txnname = arr[1]
        current_txn = txnname
        next
    }
    
    in_transaction && /tps=/ {
        # Extract system metrics
        match($0, /active-sessions=([0-9]+)\/([0-9]+)/, sessions)
        match($0, /tps=([0-9]+)/, tps)  
        match($0, /peak=([0-9]+)/, peak)
        match($0, /avg=([0-9.]+)/, avg)
        match($0, /elapsed=([0-9]+)ms/, elapsed)
        
        active_sessions = sessions[1]; max_sessions = sessions[2]
        tps_val = tps[1]; peak_val = peak[1]; avg_val = avg[1]; elapsed_val = elapsed[1]
        next
    }
    
    in_transaction && /<\/log>/ {
        # Check for success/failure status
        success_status = ""
        if (match($0, /info.*SUCCESS/)) success_status = "SUCCESS"
        else if (match($0, /info.*FAILED/)) success_status = "FAILED"
        else success_status = "UNKNOWN"
        
        if (current_txn != "" && tps_val != "") {
            printf "%s,%d,%d,%d,%.2f,%d,%d,%s\n", current_txn, active_sessions, max_sessions, tps_val, peak_val, avg_val, elapsed_val, success_status
        }
        
        in_transaction = 0
        current_txn = ""
        tps_val = ""
    }
    ' "$logfile" >> "$tmpfile"
done

echo -e "\nSystem Load by Transaction Type:"
echo "======================================================"
printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "TRANSACTION_TYPE" "COUNT" "AVG_TPS" "AVG_PK" "AVG_RT" "AVG_SE" "AVG_EL" "FAIL%"

# Aggregate system metrics by transaction type
awk -F, '
{
    txn = $1
    active_sessions = $2
    max_sessions = $3  
    tps = $4
    peak = $5
    avg_resp = $6
    elapsed = $7
    status = $8
    
    if (tps > 0) {
        count[txn]++
        total_tps[txn] += tps
        total_peak[txn] += peak
        total_avg[txn] += avg_resp
        total_sessions[txn] += active_sessions
        total_elapsed[txn] += elapsed
        
        if (status == "SUCCESS") success_count[txn]++
        else if (status == "FAILED") failed_count[txn]++
    }
}
END {
    for (txn in count) {
        avg_tps = int(total_tps[txn] / count[txn])
        avg_peak = int(total_peak[txn] / count[txn])
        avg_resp = int(total_avg[txn] / count[txn])
        avg_sessions = int(total_sessions[txn] / count[txn])
        avg_elapsed = int(total_elapsed[txn] / count[txn])
        
        fail_count = failed_count[txn] + 0
        fail_pct = (count[txn] > 0) ? int((fail_count * 100) / count[txn]) : 0
        
        printf "%s\t%d\t%d\t%d\t%d\t%d\t%d\t%d\n", txn, count[txn], avg_tps, avg_peak, avg_resp, avg_sessions, avg_elapsed, fail_pct
    }
}
' "$tmpfile" | sort -k7 -nr

# Cleanup
rm -f "$tmpfile"

echo -e "\nAnalysis complete!"