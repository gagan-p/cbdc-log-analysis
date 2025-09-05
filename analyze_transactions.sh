#!/bin/bash

# CBDC Transaction Analysis Script
# Analyzes all .log files in the current directory

echo "======================================================"
echo "CBDC Transaction Analysis Report"
echo "Generated: $(date)"
echo "Directory: $(pwd)"
echo "======================================================"

# Check if log files exist
if ! ls *.log >/dev/null 2>&1; then
    echo "ERROR: No .log files found in current directory"
    exit 1
fi

echo -e "\nLog files found:"
ls -la *.log

echo -e "\n======================================================"
echo "1. TRANSACTION TYPE FREQUENCY (Sorted by Count - Descending)"
echo "======================================================"

grep "Processing TXNNAME: " *.log | awk -F, '{print $1}' | sort | uniq -c | sort -nr

echo -e "\n======================================================"
echo "2. TRANSACTION SUMMARY STATISTICS"
echo "======================================================"

total_transactions=$(grep "Processing TXNNAME: " *.log | wc -l)
unique_types=$(grep "Processing TXNNAME: " *.log | awk -F, '{print $1}' | sort | uniq | wc -l)

echo "Total Transactions: $total_transactions"
echo "Unique Transaction Types: $unique_types"

echo -e "\n======================================================"
echo "3. TOP 10 TRANSACTION TYPES"
echo "======================================================"

grep "Processing TXNNAME: " *.log | awk -F, '{print $1}' | sort | uniq -c | sort -nr | head -10 | \
while read count txn; do
    percentage=$(echo "scale=2; $count * 100 / $total_transactions" | bc)
    printf "%-50s %6d (%5.2f%%)\n" "$txn" "$count" "$percentage"
done

echo -e "\n======================================================"
echo "4. TRANSACTION CATEGORIES BREAKDOWN"
echo "======================================================"

echo "Sync Operations:"
grep "Processing TXNNAME: " *.log | awk -F, '{print $1}' | grep -i sync | sort | uniq -c | sort -nr

echo -e "\nPayment Operations:"
grep "Processing TXNNAME: " *.log | awk -F, '{print $1}' | grep -i -E "(pay|credit|debit)" | sort | uniq -c | sort -nr

echo -e "\nAccount/Wallet Operations:"
grep "Processing TXNNAME: " *.log | awk -F, '{print $1}' | grep -i -E "(account|wallet|linked)" | sort | uniq -c | sort -nr

echo -e "\nRegistration/KYC Operations:"
grep "Processing TXNNAME: " *.log | awk -F, '{print $1}' | grep -i -E "(reg|kyc|otp|verify)" | sort | uniq -c | sort -nr

echo -e "\n======================================================"
echo "5. API ENDPOINT ANALYSIS"
echo "======================================================"

echo "APP Channel Transactions:"
app_count=$(grep "Processing TXNNAME: APP\." *.log | wc -l)
echo "Count: $app_count"

echo -e "\nPSO Channel Transactions:"
pso_count=$(grep "Processing TXNNAME: PSO\." *.log | wc -l)
echo "Count: $pso_count"

echo -e "\nOther Transactions:"
other_count=$(grep "Processing TXNNAME: " *.log | grep -v -E "(APP\.|PSO\.)" | wc -l)
echo "Count: $other_count"

echo -e "\n======================================================"
echo "6. SUCCESS/ERROR ANALYSIS PREVIEW"
echo "======================================================"

echo "Total Successful (RC: 0000):"
grep -A 10 "Processing TXNNAME: " *.log | grep "RC: 0000" | wc -l

echo -e "\nTotal Errors/Aborts:"
grep -A 10 "Processing TXNNAME: " *.log | grep -E "(ABORT|invalid\.request|RC: [^0])" | wc -l

echo -e "\n======================================================"
echo "Analysis Complete"
echo "======================================================"