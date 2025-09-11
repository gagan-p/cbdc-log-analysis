#!/bin/bash

# Prefer GNU awk if available (macOS compatibility)
if command -v gawk >/dev/null 2>&1; then AWK="gawk"; else AWK="awk"; fi

# Logs directory is chosen interactively at runtime (no flags/env required)
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

echo "=== In-Transit Queue Depth Analysis ==="
echo "Generated: $(date)"
echo ""

echo "=== Raw Data Extraction ==="
echo "Extracting in-transit values from all log files..."

# Extract all in-transit values with file references
echo "Sample in-transit entries with file references (from $LOGDIR):"
find "$LOGDIR" -type f -name "rtsp_q2-*.log" -exec grep -n "in-transit=" {} \; | head -10

echo ""
echo "=== Statistical Analysis ==="

# Create temporary file with all in-transit values
temp_file=$(mktemp)
find "$LOGDIR" -type f -name "rtsp_q2-*.log" -exec grep "in-transit=" {} \; | sed 's/.*in-transit=\([0-9]*\)\/\([0-9]*\).*/\1/' > "$temp_file"

total_count=$(wc -l < "$temp_file")
echo "Total in-transit measurements: $total_count"

# Calculate statistics
min_val=$(sort -n "$temp_file" | head -1)
max_val=$(sort -nr "$temp_file" | head -1)
avg_val=$("$AWK" '{sum+=$1} END {printf "%.1f", sum/NR}' "$temp_file")

# Calculate median
median_val=$(sort -n "$temp_file" | "$AWK" -v c="$total_count" 'NR==int(c/2)+1{print}')

# Calculate 90th percentile
percentile_90=$(sort -n "$temp_file" | "$AWK" -v c="$total_count" 'NR==int(c*0.9){print}')

echo "Min: $min_val"
echo "Average: $avg_val" 
echo "Median: $median_val"
echo "90th percentile: $percentile_90"
echo "Max: $max_val"

echo ""
echo "=== Peak Value Evidence ==="
echo "Finding exact file and line for maximum in-transit value ($max_val):"
find "$LOGDIR" -type f -name "rtsp_q2-*.log" -exec grep -n "in-transit=$max_val/" {} \; | head -5

echo ""
echo "=== High Queue Depth Examples ==="
echo "In-transit values above 300:"
find "$LOGDIR" -type f -name "rtsp_q2-*.log" -exec grep -n "in-transit=" {} \; | sed 's/\(.*\)in-transit=\([0-9]*\)\/\([0-9]*\)\(.*\)/\2 \1in-transit=\2\/\3\4/' | "$AWK" '$1 >= 300 {print}' | head -10

echo ""
echo "=== Normal vs Saturated Pool Comparison ==="
echo "In-transit when pools are saturated (1000/1000, 1500/1500, 2500/2500):"
find "$LOGDIR" -type f -name "rtsp_q2-*.log" -exec grep -n "in-transit=" {} \; | grep -E "(1000/1000|1500/1500|2500/2500)" | sed 's/.*in-transit=\([0-9]*\)\/\([0-9]*\).*active-sessions=\([0-9]*\/[0-9]*\).*/\1 \3/' | head -10

echo ""
echo "=== Distribution Analysis ==="
echo "In-transit value ranges:"
"$AWK" '
{
  if ($1 == 0) zero++
  else if ($1 <= 50) low++  
  else if ($1 <= 100) medium++
  else if ($1 <= 200) high++
  else if ($1 <= 300) very_high++
  else extreme++
}
END {
  total = zero + low + medium + high + very_high + extreme
  printf "0: %d (%.1f%%)\n", zero, zero/total*100
  printf "1-50: %d (%.1f%%)\n", low, low/total*100  
  printf "51-100: %d (%.1f%%)\n", medium, medium/total*100
  printf "101-200: %d (%.1f%%)\n", high, high/total*100
  printf "201-300: %d (%.1f%%)\n", very_high, very_high/total*100
  printf "300+: %d (%.1f%%)\n", extreme, extreme/total*100
}' "$temp_file"

# Clean up
rm "$temp_file"

echo ""
echo "=== Verification Commands ==="
echo "To verify these results, run:"
echo "1. Extract all in-transit values: find $LOGDIR -type f -name 'rtsp_q2-*.log' -exec grep 'in-transit=' {} \\; | sed 's/.*in-transit=\\([0-9]*\\)\\/\\([0-9]*\\).*/\\1/' | sort -nr"
echo "2. Find peak value location: find $LOGDIR -type f -name 'rtsp_q2-*.log' -exec grep -n 'in-transit=$max_val/' {} \\;"
echo "3. Count total measurements: find $LOGDIR -type f -name 'rtsp_q2-*.log' -exec grep 'in-transit=' {} \\; | wc -l"
