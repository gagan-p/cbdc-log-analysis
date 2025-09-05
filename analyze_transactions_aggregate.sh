#!/bin/bash

# CBDC Transaction Analysis Script - Aggregated Results
# Analyzes all .log files without file-specific references

echo "======================================================"
echo "CBDC Transaction Analysis - Aggregated Report"
echo "Generated: $(date)"
echo "Directory: $(pwd)"
echo "======================================================"

# Check if log files exist
if ! ls *.log >/dev/null 2>&1; then
    echo "ERROR: No .log files found in current directory"
    exit 1
fi

echo -e "\nLog files found:"
ls -la *.log | wc -l
echo " log files analyzed"

echo -e "\n======================================================"
echo "1. TRANSACTION TYPE FREQUENCY (Sorted by Count - Descending)"
echo "======================================================"

# Extract transaction names without file prefixes
grep "Processing TXNNAME: " *.log | \
awk -F: '{print $NF}' | \
awk -F, '{print $1}' | \
sed 's/.*Processing TXNNAME: //' | \
sort | uniq -c | sort -nr

echo -e "\n======================================================"
echo "2. TRANSACTION SUMMARY STATISTICS"
echo "======================================================"

total_transactions=$(grep "Processing TXNNAME: " *.log | wc -l)
unique_types=$(grep "Processing TXNNAME: " *.log | awk -F: '{print $NF}' | awk -F, '{print $1}' | sed 's/.*Processing TXNNAME: //' | sort | uniq | wc -l)

echo "Total Transactions: $total_transactions"
echo "Unique Transaction Types: $unique_types"

echo -e "\n======================================================"
echo "3. TOP 10 TRANSACTION TYPES"
echo "======================================================"

grep "Processing TXNNAME: " *.log | \
awk -F: '{print $NF}' | \
awk -F, '{print $1}' | \
sed 's/.*Processing TXNNAME: //' | \
sort | uniq -c | sort -nr | head -10 | \
while read count txn; do
    percentage=$(echo "scale=2; $count * 100 / $total_transactions" | bc -l 2>/dev/null || echo "0")
    printf "%-50s %6d (%5.2f%%)\n" "$txn" "$count" "$percentage"
done

echo -e "\n======================================================"
echo "4. TRANSACTION CATEGORIES BREAKDOWN"
echo "======================================================"

echo "Sync Operations:"
grep "Processing TXNNAME: " *.log | \
awk -F: '{print $NF}' | \
awk -F, '{print $1}' | \
sed 's/.*Processing TXNNAME: //' | \
grep -i sync | sort | uniq -c | sort -nr

echo -e "\nPayment Operations:"
grep "Processing TXNNAME: " *.log | \
awk -F: '{print $NF}' | \
awk -F, '{print $1}' | \
sed 's/.*Processing TXNNAME: //' | \
grep -i -E "(pay|credit|debit)" | sort | uniq -c | sort -nr

echo -e "\nAccount/Wallet Operations:"
grep "Processing TXNNAME: " *.log | \
awk -F: '{print $NF}' | \
awk -F, '{print $1}' | \
sed 's/.*Processing TXNNAME: //' | \
grep -i -E "(account|wallet|linked|listkeys)" | sort | uniq -c | sort -nr

echo -e "\nRegistration/KYC Operations:"
grep "Processing TXNNAME: " *.log | \
awk -F: '{print $NF}' | \
awk -F, '{print $1}' | \
sed 's/.*Processing TXNNAME: //' | \
grep -i -E "(reg|kyc|otp|verify)" | sort | uniq -c | sort -nr

echo -e "\n======================================================"
echo "5. API CHANNEL ANALYSIS"
echo "======================================================"

echo "APP Channel Transactions:"
app_count=$(grep "Processing TXNNAME: APP\." *.log | wc -l)
echo "Count: $app_count"

echo -e "\nPSO Channel Transactions:"
pso_count=$(grep "Processing TXNNAME: PSO\." *.log | wc -l)
echo "Count: $pso_count"

echo -e "\nMerchant Operations:"
merchant_count=$(grep "Processing TXNNAME: MerchantPayout\." *.log | wc -l)
echo "Count: $merchant_count"

echo -e "\nBackoffice Operations:"
backoffice_count=$(grep "Processing TXNNAME: BACKOFFICE\." *.log | wc -l)
echo "Count: $backoffice_count"

echo -e "\nSystem Operations (Heartbeat):"
heartbeat_count=$(grep "Processing TXNNAME: Heartbeat" *.log | wc -l)
echo "Count: $heartbeat_count"

echo -e "\n======================================================"
echo "6. SUCCESS/ERROR ANALYSIS PREVIEW"
echo "======================================================"

echo "Total Successful (RC: 0000):"
successful=$(grep -A 10 "Processing TXNNAME: " *.log | grep "RC: 0000" | wc -l)
echo "Count: $successful"

echo -e "\nTotal Errors/Aborts:"
errors=$(grep -A 10 "Processing TXNNAME: " *.log | grep -E "(ABORT|invalid\.request|RC: [^0])" | wc -l)
echo "Count: $errors"

if [ $successful -gt 0 ] && [ $total_transactions -gt 0 ]; then
    success_rate=$(echo "scale=2; $successful * 100 / $total_transactions" | bc -l 2>/dev/null || echo "0")
    echo "Success Rate: ~${success_rate}%"
fi

echo -e "\n======================================================"
echo "Analysis Complete"
echo "======================================================"