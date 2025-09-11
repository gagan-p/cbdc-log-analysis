#!/bin/bash

# Prefer GNU awk if available (macOS compatibility)
if command -v gawk >/dev/null 2>&1; then AWK="gawk"; else AWK="awk"; fi
# Prefer GNU date (gdate) if available for -d parsing
if command -v gdate >/dev/null 2>&1; then DATE_BIN="gdate"; else DATE_BIN="date"; fi

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

# Caching: include threshold/top/filter/tsv/all in signature
. scripts/helper/cache_utils.sh
ARGS_SIG="THRESH=$THRESHOLD_S;TOP=$TOP_N;FILTER=$FILTER;TSV=$TSV;ALL=$ALL"
cache_prepare "find_skew" "$0" "$ARGS_SIG" "$@"

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

OUT_FILE="$CACHE_OUT_DIR/find_skew_${CACHE_TS}.txt"
cache_register_output "$OUT_FILE"
exec > >(tee "$OUT_FILE") 2>&1

# Find client-server timestamp skew in CBDC logs
# - Scans *.log for TransactionManager <log ... at="..."> and client <Head ... ts="...">
# - Computes skew_ms = client_ts_ms - server_at_ms per transaction block
# - Outputs top-N by absolute skew, with filter and threshold options
#
# Options:
#   --top N           Number of rows to show (default: 20)
#   --threshold S     Minimum absolute skew in seconds to include (default: 0)
#   --filter APP|PSO  Limit to a channel prefix (also --app / --pso shortcuts)
#   --tsv             Output TSV (no headers decoration)
#   --all             Print all rows (ignores --top)
#   --help|-h         Show usage
#
# Usage examples:
#   sh find_skew.sh                         # top 20 skewed transactions across APP+PSO
#   sh find_skew.sh --app --threshold 60    # APP only, skew >= 60s
#   sh find_skew.sh --pso --top 50 --tsv    # PSO only, top 50, TSV output
#   sh find_skew.sh --all --filter APP      # All APP rows without top limit

set -e

TOP_N=20
THRESHOLD_S=0
FILTER=""
TSV=""
ALL=""

print_usage() {
  cat <<'EOF'
CBDC Skew Finder

Finds client-server timestamp skew within TransactionManager log blocks.

Usage:
  sh find_skew.sh [--app|--pso|--filter APP|PSO] [--threshold SECONDS] [--top N] [--all] [--tsv]

Options:
  --app | --pso            Shortcut to set --filter APP or --filter PSO
  --filter APP|PSO         Limit to a channel
  --threshold SECONDS      Minimum absolute skew (in seconds) to include (default 0)
  --top N                  Show top N rows by absolute skew (default 20)
  --all                    Show all rows (overrides --top)
  --tsv                    Output TSV only
  --help, -h               Show this help

Examples:
  sh find_skew.sh --app --threshold 60 --top 50
  sh find_skew.sh --pso --all --tsv
EOF
}

# Quick help if requested anywhere in args
for arg in "$@"; do
  if [ "$arg" = "--help" ] || [ "$arg" = "-h" ] || [ "$arg" = "help" ] || [ "$arg" = "usage" ]; then
    print_usage
    exit 0
  fi
done

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      print_usage
      exit 0 ;;
    --top)
      shift; TOP_N="$1" ;;
    --top=*)
      TOP_N="${1#*=}" ;;
    --threshold)
      shift; THRESHOLD_S="$1" ;;
    --threshold=*)
      THRESHOLD_S="${1#*=}" ;;
    --filter)
      shift; FILTER="$(printf %s "$1" | tr '[:lower:]' '[:upper:]')" ;;
    --filter=*)
      FILTER="$(printf %s "${1#*=}" | tr '[:lower:]' '[:upper:]')" ;;
    --app)
      FILTER="APP" ;;
    --pso)
      FILTER="PSO" ;;
    --tsv)
      TSV=1 ;;
    --all)
      ALL=1 ;;
    --)
      shift; break ;;
    *)
      break ;;
  esac
  shift
done

# Check logs: files are in "$@" from the prompt validation above

# Count complete <log>...</log> blocks processed under TransactionManager realm (all files)
COMPLETE_BLOCKS=$("$AWK" '
  /<log[^"]*realm="org\.jpos\.transaction\.TransactionManager"/ { in_tx=1; next }
  in_tx && /<\/log>/ { blocks++; in_tx=0; next }
  END { print (blocks+0) }
' "$LOGDIR"/rtsp_q2-*.log)

# Count blocks that contain a client <Head ... ts="..."> timestamp (all files)
CLIENT_TS_BLOCKS=$("$AWK" '
  /<log[^"]*realm="org\.jpos\.transaction\.TransactionManager"/ { in_tx=1; has_ts=0; next }
  in_tx && /<Head / { if (match($0, /ts="([^"]+)"/, a)) has_ts=1 }
  in_tx && /<\/log>/ { if (has_ts) cnt++; in_tx=0; next }
  END { print (cnt+0) }
' "$LOGDIR"/rtsp_q2-*.log)

# Extract (file|server_at|client_ts|txn_type|msg_id|txn_id)
records=$("$AWK" '
  /<log[^>]*realm="org\.jpos\.transaction\.TransactionManager"/ {
    in_block=1; server_at=""; client_ts=""; txn_type=""; msg_id=""; txn_id="";
    if (match($0, /at="([^"]+)"/, a)) server_at=a[1];
    next
  }
  in_block && /Processing TXNNAME:/ {
    if (match($0, /Processing TXNNAME: ([^,]+)/, t)) txn_type=t[1];
  }
  in_block && /<Head / {
    if (match($0, /ts="([^"]+)"/, h)) client_ts=h[1];
    if (match($0, /msgId="([^"]+)"/, m)) msg_id=m[1];
  }
  in_block && /TXN_ID:/ {
    if (match($0, /TXN_ID: ([^\r\n]+)/, x)) txn_id=x[1];
  }
  in_block && /<\/log>/ {
    if (server_at!="" && client_ts!="") {
      printf "%s|%s|%s|%s|%s|%s\n", FILENAME, server_at, client_ts, txn_type, (msg_id==""?txn_id:msg_id), txn_id
    }
    in_block=0
  }
' "$LOGDIR"/rtsp_q2-*.log)

# Function: ISO8601 to epoch ms (best-effort)
to_epoch_ms() {
  ts="$1"
  # Normalize space to 'T'
  ts_norm=$(printf "%s" "$ts" | tr ' ' 'T')
  # Fractional milliseconds (truncate to 3 digits)
  frac_ms=0
  if printf "%s" "$ts_norm" | grep -q '\\.'; then
    frac=$(printf "%s" "$ts_norm" | sed 's/^[^.]*\\.//')
    frac_ms=$(printf "%s" "$frac" | sed 's/[^0-9].*$//' | cut -c1-3)
    [ -z "$frac_ms" ] && frac_ms=0
  fi
  # Remove fractional seconds for parsing
  ts_nf=$(printf "%s" "$ts_norm" | sed 's/\.[0-9][0-9]*//')

  # 1) Prefer GNU date parse (handles offsets)
  if sec=$($DATE_BIN -d "$ts_nf" +%s 2>/dev/null); then
    :
  else
    # 2) BSD date with %z if possible (convert Z to +0000 and remove colon in offset)
    ts_bsd=$(printf "%s" "$ts_nf" | sed 's/Z$/+0000/' | sed 's/\([+-][0-9][0-9]\):\([0-9][0-9]\)$/\1\2/')
    if sec=$(date -j -u -f "%Y-%m-%dT%H:%M:%S%z" "$ts_bsd" +%s 2>/dev/null); then
      :
    else
      # 3) Manual offset handling: parse base and tz, compute UTC
      tz=$(printf "%s" "$ts_nf" | sed -n 's/.*\([+-][0-9][0-9]:[0-9][0-9]\|[+-][0-9][0-9][0-9][0-9]\|[+-][0-9][0-9]\|Z\)$/\1/p')
      base=$(printf "%s" "$ts_nf" | sed 's/\([+-][0-9][0-9]:[0-9][0-9]\|[+-][0-9][0-9][0-9][0-9]\|[+-][0-9][0-9]\|Z\)$//')
      if sec=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$base" +%s 2>/dev/null); then
        off_sec=0
        case "$tz" in
          Z|"") off_sec=0 ;;
          [+|-][0-9][0-9]:[0-9][0-9])
            sign=${tz%${tz#?}}
            h=$(printf "%s" "$tz" | sed 's/^[-+]//;s/:.*$//')
            m=$(printf "%s" "$tz" | sed 's/^.*://')
            off_sec=$((10#$h*3600 + 10#$m*60))
            if [ "$sign" = "+" ]; then sec=$((sec - off_sec)); else sec=$((sec + off_sec)); fi
            ;;
          [+|-][0-9][0-9][0-9][0-9])
            sign=${tz%${tz#?}}
            t=${tz#?}
            h=${t%??}; m=${t#??}
            off_sec=$((10#$h*3600 + 10#$m*60))
            if [ "$sign" = "+" ]; then sec=$((sec - off_sec)); else sec=$((sec + off_sec)); fi
            ;;
          [+|-][0-9][0-9])
            sign=${tz%${tz#?}}
            h=${tz#?}
            off_sec=$((10#$h*3600))
            if [ "$sign" = "+" ]; then sec=$((sec - off_sec)); else sec=$((sec + off_sec)); fi
            ;;
        esac
      else
        sec=0
      fi
    fi
  fi
  frac_val=$(printf "%s" "$frac_ms" | "$AWK" '{print ($0+0)}')
  printf "%d" $(( sec*1000 + frac_val ))
}

# Helper: build rows given a threshold (seconds); respects FILTER
build_rows() {
  thr_s="$1"
  echo "$records" | while IFS='|' read -r file server_at client_ts txn_type msg_id txn_id; do
    # Channel filter
    if [ -n "$FILTER" ]; then
      case "$FILTER" in
        APP) printf "%s" "$txn_type" | grep -q '^APP\.' || continue ;;
        PSO) printf "%s" "$txn_type" | grep -q '^PSO\.' || continue ;;
      esac
    fi
    # Treat both timestamps as UTC (ignore any provided timezone offsets)
    sa_ms=$(to_epoch_ms "$server_at")
    ct_ms=$(to_epoch_ms "$client_ts")
    skew_ms=$(( ct_ms - sa_ms ))
    abs_skew=${skew_ms#-}
    thr_ms=$(( thr_s * 1000 ))
    [ "$abs_skew" -lt "$thr_ms" ] && continue
    printf "%d\t%d\t%s\t%s\t%s\t%s\t%s\n" "$abs_skew" "$skew_ms" "$server_at" "$client_ts" "$txn_type" "${msg_id:-}" "$file"
  done
}

# Build complete and thresholded sets
ROWS_ALL=$(build_rows 0 | sort -nr -k1,1)
ROWS_THR=$(build_rows "$THRESHOLD_S" | sort -nr -k1,1)

# Metrics based on filtered dataset
TOTAL_PROCESSED=$(printf "%s\n" "$ROWS_ALL" | sed -n '/./p' | wc -l | "$AWK" '{print $1}')
SKEW_GT_60=$(printf "%s\n" "$ROWS_ALL" | "$AWK" -F'\t' '{if(($1+0)>60000)c++} END{print c+0}')
PCT_GT_60=$("$AWK" -v a="$SKEW_GT_60" -v b="$TOTAL_PROCESSED" 'BEGIN{ if (b==0) {print "0.00"} else {printf "%.2f", (a*100.0)/b} }')
TOTAL_SKEWED_THR=$(printf "%s\n" "$ROWS_THR" | sed -n '/./p' | wc -l | "$AWK" '{print $1}')
UNIQUE_IDS=$(printf "%s\n" "$ROWS_ALL" | "$AWK" -F'\t' 'length($6)>0 { u[$6]=1 } END { print length(u)+0 }')

# Output
if [ -z "$TSV" ]; then
  echo "======================================================"
  echo "CBDC Skew Report"
  echo "Generated: $(date)"
  echo "Filter: ${FILTER:-ALL}  Threshold: ${THRESHOLD_S}s  Top: ${TOP_N}"
  echo "======================================================"
  echo "Options: --app|--pso|--filter APP|PSO  --threshold SECONDS  --top N  --all  --tsv  --help"
  echo "Examples:"
  echo "- sh find_skew.sh --app --threshold 60 --top 50"
  echo "- sh find_skew.sh --pso --all --tsv"
  echo ""
  echo "Totals:"
  echo "- Blocks with client+server timestamps: ${TOTAL_PROCESSED:-0}"
  echo "- Total complete <log> blocks processed: ${COMPLETE_BLOCKS:-0}"
  echo "- Blocks with client timestamp: ${CLIENT_TS_BLOCKS:-0} (missing: $((COMPLETE_BLOCKS-CLIENT_TS_BLOCKS)))"
  echo "- Total skewed Transactions (threshold=${THRESHOLD_S}s): ${TOTAL_SKEWED_THR:-0}"
  echo "- Total skewed > 60s: ${SKEW_GT_60:-0} (${PCT_GT_60}% of processed)"
  echo "- Total unique Transaction IDs processed: ${UNIQUE_IDS:-0}"
fi

# Header and rows
printf "ABS_SKEW_MS\tSKEW_MS\tSERVER_AT\tCLIENT_TS\tTXN_TYPE\tTXN_ID/MSG_ID\tFILE\n"
if [ -n "$ALL" ]; then
  printf "%s\n" "$ROWS_THR"
else
  printf "%s\n" "$ROWS_THR" | head -n "$TOP_N"
fi

exit 0
