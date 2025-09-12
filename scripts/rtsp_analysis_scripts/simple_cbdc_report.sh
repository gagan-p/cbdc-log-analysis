#!/bin/bash
# Caching/output integrated via scripts/helper/cache_utils.sh
# For template usage, see scripts/helper/cache_template.sh

# Prefer GNU awk if available (macOS compatibility)
if command -v gawk >/dev/null 2>&1; then AWK="gawk"; else AWK="awk"; fi

# Logs directory is chosen interactively at runtime (no flags/env required)

# CBDC Transaction Log Analysis Report
# - Reads all *.log in current directory
# - No caching, hashing, or temp files
# - Includes APP and PSO transactions
# - Pretty output with:
#   - Summary (total transactions analyzed)
#   - Top 10 transactions (by Avg Duration, descending) across APP+PSO
#   - Comprehensive table sorted by Transaction Type (TXNTYPE)
# - Options:
#   --compact            Output fewer columns for the comprehensive table
#   --raw                Output raw per-transaction rows (no grouping)
#   --filter APP|PSO     Limit to a channel (also --app / --pso)
#   --top-only           Show only a Top-N ranking and exit (no comprehensive table)
#   --top N              Number of rows for Top ranking (default: 20)
#   --top-by METRIC      Ranking metric: total_ms|avg_dur|count|tps_avg|tps_max|peak_avg|peak_max|avg_metric_avg|elapsed_avg|elapsed_max (default: avg_dur)

COMPACT=""
RAW=""
FILTER=""
TOP_ONLY=""
TOP_N=20
TOP_METRIC="avg_dur"
# Usage helper
print_usage() {
  cat <<'EOF'
CBDC Transaction Analysis Report

Usage:
  sh simple_cbdc_report.sh [--app|--pso|--filter APP|PSO] [--compact] [--raw]
                            [--top-only] [--top N] [--top-by METRIC]

Options:
  --app | --pso                 Shortcut to set --filter APP or --filter PSO
  --filter APP|PSO              Limit to a channel
  --compact                     Show compact columns for the comprehensive table
  --raw                         Show raw per-transaction rows (no grouping)
  --top-only                    Show only a Top-N ranking and exit (no full table)
  --top N                       Number of rows in Top ranking (default 20)
  --top-by METRIC               Metric for Top ranking (default avg_dur). One of:
                                total_ms|avg_dur|count|tps_avg|tps_max|
                                peak_avg|peak_max|avg_metric_avg|elapsed_avg|elapsed_max
  --help, -h                    Show this help

Examples:
  # APP-only, Top 20 by Total Ms
  sh simple_cbdc_report.sh --app --top-only --top 20 --top-by total_ms

  # PSO-only, pretty full report, compact comprehensive table
  sh simple_cbdc_report.sh --pso --compact

  # Raw ungrouped rows for APP
  sh simple_cbdc_report.sh --raw --app
EOF
}

# Pre-scan args for help
for arg in "$@"; do
  if [ "$arg" = "--help" ] || [ "$arg" = "-h" ] || [ "$arg" = "help" ] || [ "$arg" = "usage" ]; then
    print_usage
    exit 0
  fi
done
# Parse simple flags: --compact, --raw, --filter APP|PSO (also --app/--pso shortcuts)
while [ $# -gt 0 ]; do
  case "$1" in
    --compact)
      COMPACT=1 ;;
    --raw)
      RAW=1 ;;
    --app)
      FILTER="APP" ;;
    --pso)
      FILTER="PSO" ;;
    --top-only)
      TOP_ONLY=1 ;;
    --top)
      shift; TOP_N="$1" ;;
    --top=*)
      TOP_N="$(printf %s "$1" | sed 's/^--top=//')" ;;
    --top-by)
      shift; TOP_METRIC="$(printf %s "$1" | tr '[:upper:]' '[:lower:]')" ;;
    --top-by=*)
      TOP_METRIC="$(printf %s "$1" | sed 's/^--top-by=//' | tr '[:upper:]' '[:lower:]')" ;;
    --filter=*)
      FILTER="$(printf %s "$1" | sed 's/^--filter=//;s/\(.*\)/\U\1/')" ;;
    --filter)
      shift
      FILTER="$(printf %s "$1" | tr '[:lower:]' '[:upper:]')" ;;
    --)
      shift; break ;;
    *)
      break ;;
  esac
  shift
done

# Always prompt for logs dir (no defaults)
while :; do
  read -r -p "Enter path to rtsp_q2 log repo (directory). Files must match rtsp_q2-*.log: " LOGDIR
  if [ -z "$LOGDIR" ]; then
    echo "Path is required."
    continue
  fi
  set -- "$LOGDIR"/rtsp_q2-*.log
  if [ "$1" = "$LOGDIR/rtsp_q2-*.log" ] || [ $# -eq 0 ]; then
    echo "ERROR: No rtsp_q2-*.log files found in $LOGDIR" >&2
    continue
  fi
  break
done

# Caching: prepare status and maybe short-circuit
. scripts/helper/cache_utils.sh
ARGS_SIG="FILTER=$FILTER;TOP_ONLY=$TOP_ONLY;TOP_N=$TOP_N;TOP_BY=$TOP_METRIC;COMPACT=$COMPACT;RAW=$RAW"
cache_prepare "simple_cbdc_report" "$0" "$ARGS_SIG" "$@"

if [ "$CACHE_STATUS" = "noop" ]; then
  echo "No changes detected (inputs and script unchanged). Skipping run."
  echo "Previous outputs: $CACHE_LAST_OUTPUTS"
  exit 0
elif [ "$CACHE_STATUS" = "duplicate" ]; then
  echo "Inputs unchanged; script changed. Duplicating previous outputs with new timestamp."
  cache_duplicate_outputs
  cache_save_meta
  echo "New outputs: $CACHE__OUTPUTS"
  exit 0
fi

# Capture output to a timestamped file under scripts/output while also printing
OUT_FILE="$CACHE_OUT_DIR/simple_cbdc_report_${CACHE_TS}.txt"
cache_register_output "$OUT_FILE"
exec > >(tee "$OUT_FILE") 2>&1
echo "======================================================"
echo "CBDC Transaction Analysis Report"
echo "Generated: $(date)"
echo "======================================================"
echo "Options:"
echo "- --compact: show compact columns (Transaction Type, TxnName, Total Ms, Avg Duration, TPS(min/avg/max), Peak_TPS(min/avg/max), Avg_TPS(min/avg/max))"
echo "- --raw: show raw per-transaction rows (no grouping)"
echo "- --filter APP|PSO (or --app/--pso): limit to a channel"
echo "- --top-only: show only a Top-N ranking and exit"
echo "- --top N: number of rows for Top (default 20)"
echo "- --top-by METRIC: metric for Top (total_ms|avg_dur|count|tps_avg|tps_max|peak_avg|peak_max|avg_metric_avg|elapsed_avg|elapsed_max)"
echo ""
echo "Quick Examples:"
echo "- sh simple_cbdc_report.sh --app --top-only --top 10 --top-by total_ms"
echo "- sh simple_cbdc_report.sh --pso --compact"

# Check for log files (POSIX sh)
# Files are now in "$@" from the prompt validation above

echo ""
echo "Processing $# log files..."
echo ""

# Stage 0: Extract per-transaction records from all logs (pipe-delimited)
# Fields: txn_type|processing_pattern|tps|peak|avg|elapsed_ms|active|max_sessions|in_transit|max_transit|status
records=$(cat -- "$@" 2>/dev/null | tr -d '\r' | "$AWK" '
  /<log[^"]*realm="org\.jpos\.transaction\.TransactionManager"/ {
    in_tx=1
    processing_pattern=""; txn_type=""; txn_id=""
    tps=""; peak=""; avgv=""; elapsed=""
    active=""; maxs=""; intrans=""; maxtrans=""
    status="UNKNOWN"
    next
  }

  in_tx && /Processing TXNNAME:/ {
    if (match($0, /Processing TXNNAME: ([^,]+, [^,]+, [^,]+)/, arr)) {
      processing_pattern=arr[1]
      split(processing_pattern, parts, ", ")
      txn_type=parts[1]
    } else if (match($0, /Processing TXNNAME: ([^,]+)/, arr2)) {
      processing_pattern=arr2[1]
      txn_type=arr2[1]
    }
    next
  }

  in_tx && /active-sessions=/ {
    if (match($0, /active-sessions=([0-9]+)\/([0-9]+)/, sa)) { active=sa[1]+0; maxs=sa[2]+0 }
    if (match($0, /tps=([0-9]+)/, ta)) { tps=ta[1]+0 }
    if (match($0, /peak=([0-9]+)/, pa)) { peak=pa[1]+0 }
    if (match($0, /avg=([0-9.]+)/, aa)) { avgv=aa[1]+0 }
    if (match($0, /elapsed=([0-9]+)ms/, ea)) { elapsed=ea[1]+0 }
    if (match($0, /in-transit=([0-9]+)\/([0-9]+)/, ia)) { intrans=ia[1]+0; maxtrans=ia[2]+0 }
    next
  }

  in_tx {
    if (status=="UNKNOWN") {
      if ($0 ~ /SUCCESS/) status="SUCCESS"
      else if ($0 ~ /FAILED/) status="FAILED"
    }
  }

  in_tx && /<\/log>/ {
    if (txn_type != "") {
      printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n",
        txn_type, processing_pattern, tps, peak, avgv, elapsed, active, maxs, intrans, maxtrans, status
    }
    in_tx=0
    next
  }
')

# Count complete <log>...</log> blocks processed under TransactionManager realm
COMPLETE_BLOCKS=$(cat -- "$@" 2>/dev/null | tr -d '\r' | "$AWK" '
  /<log[^"]*realm="org\.jpos\.transaction\.TransactionManager"/ { in_tx=1; next }
  in_tx && /<\/log>/ { blocks++; in_tx=0; next }
  END { print (blocks+0) }
')

# Raw mode: print records without grouping and exit
if [ -n "$RAW" ]; then
  RAW_FILTERED=$(printf "%s\n" "$records" | "$AWK" -F'|' -v filter="$FILTER" '
    filter=="" { print; next }
    filter=="APP" && $1 ~ /^APP\./ { print; next }
    filter=="PSO" && $1 ~ /^PSO\./ { print; next }
  ')
  RAW_TOTAL=$(printf "%s\n" "$RAW_FILTERED" | sed -n '/./p' | wc -l | awk '{print $1}')
  echo "=================================================================================================="
  echo "==============================================================================="
  if [ "$FILTER" = "APP" ]; then
    echo "RAW TRANSACTIONS - APP"
  elif [ "$FILTER" = "PSO" ]; then
    echo "RAW TRANSACTIONS - PSO"
  else
    echo "RAW TRANSACTIONS - APP + PSO"
  fi
  echo "=================================================================================================="
  echo "==============================================================================="
  echo ""
  echo "Help: run 'sh simple_cbdc_report.sh help' for usage"
  echo "Summary: Total transactions analyzed: ${RAW_TOTAL:-0}"
  echo "Summary: Total complete <log> blocks processed: ${COMPLETE_BLOCKS:-0}"
  # Proxy for unique transaction ids/types using grouped pass
  UNIQUE_TXN_TYPES=$(printf "%s\n" "$records" | "$AWK" -F'|' -v filter="$FILTER" '
    filter=="" { t[$1]=1; next }
    filter=="APP" && $1 ~ /^APP\./ { t[$1]=1; next }
    filter=="PSO" && $1 ~ /^PSO\./ { t[$1]=1; next }
    END { print length(t)+0 }
  ')
  echo "Summary: Total unique transaction ids processed: ${UNIQUE_TXN_TYPES:-0}"
  echo ""
  printf "Transaction Type\tTxnName\tTPS\tPeak\tAvg\tElapsed_ms\tActive_Sessions\tMax_Sessions\tIn_Transit\tMax_Transit\tStatus\n"
  printf "%s\n" "$RAW_FILTERED" | tr '|' '\t'
  echo ""
  exit 0
fi

# Stage 1: Aggregate APP and PSO transactions
summary=$(printf "%s\n" "$records" | "$AWK" -F'|' -v compact="$COMPACT" -v filter="$FILTER" -v top_only="$TOP_ONLY" -v top_n="$TOP_N" -v top_metric="$TOP_METRIC" '
  {
    txn=$1; pat=$2; tps=$3+0; peak=$4+0; avgv=$5+0; el=$6+0; act=$7+0; maxs=$8+0; tr=$9+0; maxtr=$10+0; st=$11
    if (txn == "") next
    if (filter=="APP" && txn !~ /^APP\./) next
    if (filter=="PSO" && txn !~ /^PSO\./) next

    cnt[txn]++
    grand_total++
    if (name[txn] == "") name[txn]=pat

    total_ms[txn]+=el

    tps_sum[txn]+=tps
    if (tps_min[txn]=="" || tps < tps_min[txn]) tps_min[txn]=tps
    if (tps_max[txn]=="" || tps > tps_max[txn]) tps_max[txn]=tps

    peak_sum[txn]+=peak
    if (peak_min[txn]=="" || peak < peak_min[txn]) peak_min[txn]=peak
    if (peak_max[txn]=="" || peak > peak_max[txn]) peak_max[txn]=peak

    avg_sum[txn]+=avgv
    if (avg_min[txn]=="" || avgv < avg_min[txn]) avg_min[txn]=avgv
    if (avg_max[txn]=="" || avgv > avg_max[txn]) avg_max[txn]=avgv

    elapsed_sum[txn]+=el
    if (elapsed_min[txn]=="" || el < elapsed_min[txn]) elapsed_min[txn]=el
    if (elapsed_max[txn]=="" || el > elapsed_max[txn]) elapsed_max[txn]=el

    if (st=="SUCCESS") succ[txn]++
    else if (st=="FAILED") fail[txn]++
  }

  END {
    # Summary lines
    printf "=== TOTAL_TXN === %d\n", (grand_total+0)

    # (Top will be prepared during table generation below)

    # Comprehensive table rows (sorted by TXNTYPE)
    n2 = asorti(cnt, stx)
    printf "=== UNIQUE_TXN_TYPES === %d\n", (n2+0)
    printf "=== ADDITIONAL DETAILED DATA ===\n"
    for (i = 1; i <= n2; i++) {
      t = stx[i]
      c=cnt[t]
      tms=total_ms[t]+0
      avgdur=int((c>0)? tms/c : 0)
      tpsavg=int((c>0)? tps_sum[t]/c : 0)
      peakavg=int((c>0)? peak_sum[t]/c : 0)
      avgmin = (avg_min[t] == "" ? 0 : avg_min[t])
      avgavg = (c > 0 ? avg_sum[t]/c : 0)
      avgmax = (avg_max[t] == "" ? 0 : avg_max[t])
      tpsmin = (tps_min[t] == "" ? 0 : tps_min[t])
      tpsmax = (tps_max[t] == "" ? 0 : tps_max[t])
      peakmin = (peak_min[t] == "" ? 0 : peak_min[t])
      peakmax = (peak_max[t] == "" ? 0 : peak_max[t])
      elmin=elapsed_min[t]+0; elavg=int((c>0)? elapsed_sum[t]/c : 0); elmax=elapsed_max[t]+0

      tpsrange = tpsmin "/" tpsavg "/" tpsmax
      peakrange = peakmin "/" peakavg "/" peakmax
      avgrange = sprintf("%.0f/%.0f/%.0f", avgmin, avgavg, avgmax)
      elrange = elmin "/" elavg "/" elmax

      if (compact) {
        # Compact fields: Transaction Type, TxnName, Total Ms, Avg Duration, TPS, Peak, Avg_TPS
        printf "%s\t%s\t%d\t%d\t%s\t%s\t%s\n", t, name[t], tms, avgdur, tpsrange, peakrange, avgrange
      } else {
        # Full fields
        printf "%s\t%s\t%d\t%d\t%d\t%s\t%s\t%s\t%s\n", t, name[t], c, tms, avgdur, tpsrange, peakrange, avgrange, elrange
      }

      # Prepare candidates for Top ranking (based on requested metric)
      {
        metric_val=avgdur
        if (top_metric=="total_ms") metric_val=tms
        else if (top_metric=="avg_dur") metric_val=avgdur
        else if (top_metric=="count") metric_val=c
        else if (top_metric=="tps_avg") metric_val=tpsavg
        else if (top_metric=="tps_max") metric_val=tpsmax
        else if (top_metric=="peak_avg") metric_val=peakavg
        else if (top_metric=="peak_max") metric_val=peakmax
        else if (top_metric=="avg_metric_avg") metric_val=avgavg
        else if (top_metric=="elapsed_avg") metric_val=elavg
        else if (top_metric=="elapsed_max") metric_val=elmax

        key = sprintf("%012d-%s", (999999999999 - metric_val), t)
        top_map[key] = t "\t" name[t] "\t" metric_val "\t" c "\t" tms "\t" avgdur "\t" tpsrange "\t" peakrange "\t" avgrange "\t" elrange
      }
    }

    # Emit the Top-N block (always), consumers can choose what to print
    printf "=== TOP_ONLY === %s %d\n", top_metric, top_n
    n3 = asorti(top_map, ord)
    printed2=0
    for (i=1; i<=n3 && printed2<top_n; i++) {
      print top_map[ord[i]]
      printed2++
    }
  }
')

# Pull sections
TOTAL_TXN=$(printf "%s\n" "$summary" | sed -n 's/^=== TOTAL_TXN === \([0-9][0-9]*\)$/\1/p')
UNIQUE_TXN_TYPES=$(printf "%s\n" "$summary" | sed -n 's/^=== UNIQUE_TXN_TYPES === \([0-9][0-9]*\)$/\1/p')

if [ -n "$TOP_ONLY" ]; then
  metric_upper=$(printf "%s" "$TOP_METRIC" | tr '[:lower:]' '[:upper:]')
  echo "=================================================================================================="
  echo "==============================================================================="
  echo "Top ${TOP_N} by ${metric_upper} (descending)"
  echo "=================================================================================================="
  echo "==============================================================================="
  echo ""
  echo "Help: run 'sh simple_cbdc_report.sh help' for usage"
  echo "Totals: Complete <log> blocks processed: ${COMPLETE_BLOCKS:-0}"
  echo "Totals: Transactions analyzed: ${TOTAL_TXN:-0}"
  echo "Totals: Unique transaction ids processed: ${UNIQUE_TXN_TYPES:-0}"
  echo ""
  printf "Transaction Type\tTxnName\t%s\tCount\tTotal Ms\tAvg Duration\tTPS (min/avg/max)\tPeak_TPS (min/avg/max)\tAvg_TPS (min/avg/max)\tElapsed_ms (min/avg/max)\n" "$metric_upper"
  printf "%s\n" "$summary" | sed -n '/^=== TOP_ONLY ===/,$p' | sed -n '2,1000p'
  echo ""
  exit 0
fi

echo "=================================================================================================="
echo "==============================================================================="
if [ "$FILTER" = "APP" ]; then
  echo "COMPREHENSIVE SYSTEM METRICS - APP"
elif [ "$FILTER" = "PSO" ]; then
  echo "COMPREHENSIVE SYSTEM METRICS - PSO"
else
  echo "COMPREHENSIVE SYSTEM METRICS - APP + PSO"
fi
echo "=================================================================================================="
echo "==============================================================================="
echo ""
echo "Help: run 'sh simple_cbdc_report.sh help' for usage"
if [ "$FILTER" = "APP" ]; then
  echo "Summary: Total APP transactions analyzed: ${TOTAL_TXN:-0}"
elif [ "$FILTER" = "PSO" ]; then
  echo "Summary: Total PSO transactions analyzed: ${TOTAL_TXN:-0}"
else
  echo "Summary: Total transactions analyzed: ${TOTAL_TXN:-0}"
fi
echo "Summary: Total complete <log> blocks processed: ${COMPLETE_BLOCKS:-0}"
echo "Summary: Total unique transaction ids processed: ${UNIQUE_TXN_TYPES:-0}"
echo ""

if [ -z "$COMPACT" ]; then
  metric_upper=$(printf "%s" "$TOP_METRIC" | tr '[:lower:]' '[:upper:]')
  echo "Top ${TOP_N} by ${metric_upper} (descending)"
  printf "Transaction Type\tTxnName\tCount\tTotal Ms\tAvg Duration\n"
  printf "%s\n" "$summary" | sed -n '/^=== TOP_ONLY ===/,$p' | sed -n '2,$p' | head -n "$TOP_N"
  echo ""
fi

if [ -n "$COMPACT" ]; then
  # Compact header
  printf "Transaction Type\tTxnName\tTotal Ms\tAvg Duration\tTPS (min/avg/max)\tPeak_TPS (min/avg/max)\tAvg_TPS (min/avg/max)\n"
else
  # Full header
  printf "Transaction Type\tTxnName\tCount\tTotal Ms\tAvg Duration\tTPS (min/avg/max)\tPeak_TPS (min/avg/max)\tAvg_TPS (min/avg/max)\tElapsed_ms (min/avg/max)\n"
fi

# Print comprehensive rows
printf "%s\n" "$summary" | sed -n '0,/^=== ADDITIONAL DETAILED DATA ===/d;p'

echo ""
echo "Saved report: $OUT_FILE"
cache_save_meta
exit 0
