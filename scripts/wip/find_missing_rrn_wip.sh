#!/bin/sh

# Prefer GNU awk if available (macOS compatibility)
if command -v gawk >/dev/null 2>&1; then AWK="gawk"; else AWK="awk"; fi

# Logs directory is chosen interactively at runtime (no flags/env required)

# Find UPI transactions that are missing an RRN within TransactionManager blocks
# - Scans *.log for <log realm="org.jpos.transaction.TransactionManager" ...> ... </log>
# - Flags a block as UPI if it contains either the UPI schema URL or common UPI API names
# - Considers RRN present if any case-insensitive key of (txn-rrn|rrn) appears with a non-null value
# - Outputs missing-RRN rows and a summary
#
# Options:
#   --filter APP|PSO   Limit to channel prefix (based on TXNNAME)
#   --top N            Limit output rows (default 50); use --all to show all
#   --tsv              TSV output (no decorated headers)
#   --help|-h|help     Show usage
#   --all              Do not limit rows
#
# Examples:
#   sh find_missing_rrn.sh --filter PSO --top 100
#   sh find_missing_rrn.sh --all --tsv

set -e

FILTER=""
TOP_N=50
TSV=""
ALL=""

print_usage() {
  cat <<'EOF'
Find Missing RRN in UPI Transactions

Scans TransactionManager <log> blocks, identifies UPI-related transactions, and reports blocks
that lack an RRN (txn-rrn/rrn absent or null).

Usage:
  sh find_missing_rrn.sh [--filter APP|PSO] [--top N|--all] [--tsv]

Options:
  --filter APP|PSO   Limit to a channel prefix based on TXNNAME
  --top N            Limit rows (default 50)
  --all              Show all rows (disables --top)
  --tsv              Output TSV only
  --help, -h, help   Show this help

Examples:
  sh find_missing_rrn.sh --filter PSO --top 100
  sh find_missing_rrn.sh --all --tsv
EOF
}

# Early help
for arg in "$@"; do
  case "$arg" in
    --help|-h|help) print_usage; exit 0;;
  esac
done

while [ $# -gt 0 ]; do
  case "$1" in
    --filter)
      shift; FILTER="$(printf %s "$1" | tr '[:lower:]' '[:upper:]')" ;;
    --filter=*)
      FILTER="$(printf %s "${1#*=}" | tr '[:lower:]' '[:upper:]')" ;;
    --top)
      shift; TOP_N="$1" ;;
    --top=*)
      TOP_N="${1#*=}" ;;
    --all)
      ALL=1 ;;
    --tsv)
      TSV=1 ;;
    --help|-h|help)
      print_usage; exit 0 ;;
    --)
      shift; break ;;
    *)
      break ;;
  esac
  shift
done

# Prompt for logs dir if not set
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

# Check logs
set -- "$LOGDIR"/rtsp_q2-*.log
if [ "$1" = "$LOGDIR/rtsp_q2-*.log" ] || [ $# -eq 0 ]; then
  echo "ERROR: No rtsp_q2-*.log files found in $LOGDIR" >&2
  exit 1
fi

# Build rows and summary in one awk pass; print TSV rows for missing RRN, then totals
RESULT=$("$AWK" -v filter="$FILTER" '
  function trimq(s){ gsub(/^"|"$/, "", s); return s }

  /<log[^>]*realm="org\.jpos\.transaction\.TransactionManager"/ {
    in=1; server_at=""; txn_type=""; msg_id=""; txn_id=""; has_upi=0; found_rrn=0; rrn_val="";
    if (match($0, /at="([^"]+)"/, a)) server_at=a[1];
    next
  }
  in && /Processing TXNNAME:/ {
    if (match($0, /Processing TXNNAME: ([^,]+)/, t)) txn_type=t[1]
  }
  in {
    u = toupper($0)
    if (index(u, "UPI/SCHEMA")>0 || u ~ /(REQPAY|RESPPAY|REQSYNC|RESPSYNC|REQTXN|LISTKEYS|LISTACCOUNT|REQAUTHDETAILS)/) has_upi=1
    if (match($0, /msgId="([^"]+)"/, m)) msg_id=m[1]
    if (match($0, /TXN_ID: ([^\r\n]+)/, x)) txn_id=x[1]
    ll = tolower($0)
    # Generic rrn capture (txn-rrn or rrn) allowing formats: key = value, key:value, key=value
    if (match(ll, /(txn-rrn|rrn)[^a-z0-9]*[:=][ \t]*([^,} \t\"]+)/, r)) { found_rrn=1; rrn_val=r[2] }
    # Also capture quoted values like "txn-rrn":"..."
    if (!found_rrn && match(ll, /"(txn-rrn|rrn)"[ \t]*:[ \t]*"([^"]*)"/, r2)) { found_rrn=1; rrn_val=r2[2] }
  }
  in && /<\/log>/ {
    if (has_upi) {
      total_upi++
      # Filter by channel prefix if requested
      if (filter=="APP" && txn_type !~ /^APP\./) { in=0; next }
      if (filter=="PSO" && txn_type !~ /^PSO\./) { in=0; next }

      missing=0
      if (!found_rrn) missing=1
      else {
        v=rrn_val; gsub(/^"|"$/, "", v)
        if (v=="" || v=="null" || v=="nil" || v=="none") missing=1
      }
      if (missing) {
        printf "ROW\t%s\t%s\t%s\t%s\t%s\n", server_at, txn_type, (msg_id==""?"-":msg_id), (txn_id==""?"-":txn_id), FILENAME
        missing_cnt++
      }
    }
    in=0
  }
  END {
    printf "TOTALS\tUPI_BLOCKS\t%d\n", (total_upi+0)
    printf "TOTALS\tMISSING_RRN\t%d\n", (missing_cnt+0)
  }
' "$@")

# Split rows and totals
ROWS=$(printf "%s\n" "$RESULT" | "$AWK" -F"\t" '$1=="ROW" { $1=""; sub(/^\t/ ,""); print }')
UPI_BLOCKS=$(printf "%s\n" "$RESULT" | "$AWK" -F"\t" '$1=="TOTALS" && $2=="UPI_BLOCKS" {print $3}')
MISSING_RRN=$(printf "%s\n" "$RESULT" | "$AWK" -F"\t" '$1=="TOTALS" && $2=="MISSING_RRN" {print $3}')

# Pretty header
if [ -z "$TSV" ]; then
  echo "======================================================"
  echo "Missing RRN Report (UPI)"
  echo "Generated: $(date)"
  echo "Filter: ${FILTER:-ALL}  Top: ${TOP_N}"
  echo "======================================================"
  echo "Examples:"
  echo "- sh find_missing_rrn.sh --filter PSO --top 100"
  echo "- sh find_missing_rrn.sh --all --tsv"
  echo ""
  echo "Totals:"
  echo "- UPI TransactionManager blocks: ${UPI_BLOCKS:-0}"
  echo "- Blocks missing RRN: ${MISSING_RRN:-0}"
  echo ""
  echo "SERVER_AT\tTXN_TYPE\tMSG_ID\tTXN_ID\tFILE"
fi

if [ -n "$ALL" ]; then
  printf "%s\n" "$ROWS"
else
  printf "%s\n" "$ROWS" | head -n "$TOP_N"
fi

exit 0
