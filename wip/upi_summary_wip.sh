#!/bin/sh

# Prefer GNU awk if available (macOS compatibility)
if command -v gawk >/dev/null 2>&1; then AWK="gawk"; else AWK="awk"; fi

# Logs directory is chosen interactively at runtime (no flags/env required)

# UPI Summary across TransactionManager blocks
# Reports:
# - Transactions processed (blocks)
# - Unique Transaction Ids processed (msgId or TXN_ID)
# - Transactions with UPI leg (by unique txn-id)
# - Failed Transactions with UPI leg (system-level fail)
# - Failed at UPI level (RC non-0000 within UPI leg)
# - RRN availability for UPI-linked transactions (by unique txn-id)
#
# Options:
#   --filter APP|PSO     Limit to a channel prefix (based on TXNNAME)
#   --tsv                Output TSV-only summary (key\tvalue)
#   --list               Also print per-id listings by category
#   --help|-h|help       Show usage
#
# Examples:
#   sh upi_summary.sh
#   sh upi_summary.sh --filter PSO

set -e

FILTER=""
TSV=""
LIST=""

print_usage() {
  cat <<'EOF'
UPI Summary Report

Summarizes TransactionManager blocks for UPI-related legs.

Metrics:
  - Transactions processed (blocks)
  - Unique Transaction Ids processed (msgId or TXN_ID)
  - Transactions with UPI leg (unique ids)
  - Failed Transactions with UPI Leg (system-level)
  - Failed at UPI level (RC != 0000 within UPI leg)
  - RRN available / not available (on UPI-linked unique ids)

Usage:
  sh upi_summary.sh [--filter APP|PSO] [--tsv]

Examples:
  sh upi_summary.sh
  sh upi_summary.sh --filter PSO
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
    --tsv)
      TSV=1 ;;
    --list)
      LIST=1 ;;
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

RESULT=$("$AWK" -v filter="$FILTER" -v do_list="$LIST" '
  function mark(map, k){ map[k]=1 }
  function has(map, k){ return (k in map) }
  function count(map,    c,k){ c=0; for(k in map) c++; return c }

  /<log[^>]*realm="org\.jpos\.transaction\.TransactionManager"/ {
    in_block=1; server_at=""; txn_type=""; msg_id=""; txn_id="";
    has_upi=0; sys_failed=0; upi_fail=0; rrn_present=0;
    if (match($0, /at="([^"]+)"/, a)) server_at=a[1]
    next
  }
  in_block && /Processing TXNNAME:/ {
    if (match($0, /Processing TXNNAME: ([^,]+)/, t)) txn_type=t[1]
    next
  }
  in_block {
    U=toupper($0)
    L=tolower($0)
    # Strict UPI leg detection: explicit schema or NPCI UPI class namespace
    if (index(L, "upi/schema")>0 || L ~ /org\.npci\.pso\.schema/) has_upi=1
    if (match($0, /msgId="([^"]+)"/, m)) msg_id=m[1]
    if (match($0, /TXN_ID: ([^\r\n]+)/, x)) txn_id=x[1]
    # RRN present detection
    if (match(L, /"(txn-rrn|rrn)"[ \t]*:[ \t]*"([^"]*)"/, rjson)) {
      if (rjson[2] != "" && rjson[2] != "null" && rjson[2] != "nil" && rjson[2] != "none") rrn_present=1
    }
    if (match(L, /(txn-rrn|rrn)[^a-z0-9]*[:=][ \t]*([^,} \t"]+)/, rkv)) {
      v=rkv[2]; if (v!="" && v!="null" && v!="nil" && v!="none") rrn_present=1
    }
    # UPI level RC detection
    if (U ~ /RC[ :=]*0{2,3}([^0-9]|$)/) upi_success=1
    if (U ~ /RC[ :=]*0*[1-9][0-9]*/) upi_fail=1
    # System failure hints
    if (U ~ /FAILED|ABORT|INVALID\.REQUEST/) sys_failed=1
  }
  in_block && /<\/log>/ {
    total_blocks++
    id = (msg_id!="" ? msg_id : txn_id)
    if (id!="") mark(ids, id)

    # Channel filter (applies to UPI considerations as well)
    if (filter=="APP" && txn_type !~ /^APP\./) { in_block=0; next }
    if (filter=="PSO" && txn_type !~ /^PSO\./) { in_block=0; next }

    if (has_upi) {
      mark(ids_with_upi, id)
      if (sys_failed) mark(ids_upi_sysfail, id)
      if (upi_fail) mark(ids_upi_upifail, id)
      if (rrn_present) mark(ids_upi_rrn_present, id)
    }
    in_block=0
  }
  END {
    upi_ids = count(ids_with_upi)
    rrn_present_ids = count(ids_upi_rrn_present)
    rrn_missing_ids = (upi_ids - rrn_present_ids)
    print "TOTAL_BLOCKS\t" total_blocks
    print "UNIQUE_IDS\t" count(ids)
    print "UPI_UNIQUE_IDS\t" upi_ids
    print "UPI_SYSFAIL_IDS\t" count(ids_upi_sysfail)
    print "UPI_FAIL_IDS\t" count(ids_upi_upifail)
    print "UPI_RRN_PRESENT_IDS\t" rrn_present_ids
    print "UPI_RRN_MISSING_IDS\t" rrn_missing_ids

    if (do_list==1) {
      for (id in ids_with_upi) {
        print "LIST\tUPI_ALL\t" id
      }
      for (id in ids_upi_rrn_present) {
        print "LIST\tUPI_RRN_PRESENT\t" id
      }
      # UPI_RRN_MISSING = ids_with_upi - ids_upi_rrn_present
      for (id in ids_with_upi) {
        if (!(id in ids_upi_rrn_present)) print "LIST\tUPI_RRN_MISSING\t" id
      }
      for (id in ids_upi_sysfail) {
        print "LIST\tUPI_SYSFAIL\t" id
      }
      for (id in ids_upi_upifail) {
        print "LIST\tUPI_UPI_FAIL\t" id
      }
    }
  }
' "$@")

SUMMARY=$(printf "%s\n" "$RESULT" | awk -F"\t" '$1!="LIST" {print}')
LIST_ROWS=$(printf "%s\n" "$RESULT" | awk -F"\t" '$1=="LIST" {print}')

TBLOCKS=$(printf "%s\n" "$SUMMARY" | awk -F"\t" '$1=="TOTAL_BLOCKS"{print $2}')
UIDS=$(printf "%s\n" "$SUMMARY" | awk -F"\t" '$1=="UNIQUE_IDS"{print $2}')
UPI_UIDS=$(printf "%s\n" "$SUMMARY" | awk -F"\t" '$1=="UPI_UNIQUE_IDS"{print $2}')
UPI_SYSFAIL=$(printf "%s\n" "$SUMMARY" | awk -F"\t" '$1=="UPI_SYSFAIL_IDS"{print $2}')
UPI_FAIL=$(printf "%s\n" "$SUMMARY" | awk -F"\t" '$1=="UPI_FAIL_IDS"{print $2}')
RRN_PRESENT=$(printf "%s\n" "$SUMMARY" | awk -F"\t" '$1=="UPI_RRN_PRESENT_IDS"{print $2}')
RRN_MISSING=$(printf "%s\n" "$SUMMARY" | awk -F"\t" '$1=="UPI_RRN_MISSING_IDS"{print $2}')

if [ -n "$TSV" ]; then
  echo "Transactions processed (blocks)\t${TBLOCKS:-0}"
  echo "Unique Transaction Ids processed\t${UIDS:-0}"
  echo "Transactions with UPI leg (unique ids)\t${UPI_UIDS:-0}"
  echo "Failed Transactions with UPI leg (unique ids)\t${UPI_SYSFAIL:-0}"
  echo "Failed at UPI level (unique ids)\t${UPI_FAIL:-0}"
  echo "RRN available for UPI-linked (unique ids)\t${RRN_PRESENT:-0}"
  echo "RRN not available for UPI-linked (unique ids)\t${RRN_MISSING:-0}"
  if [ -n "$LIST" ]; then
    printf "%s\n" "$LIST_ROWS" | awk -F"\t" '{print $2"\t"$3}'
  fi
  exit 0
fi

echo "======================================================"
echo "UPI Summary Report"
echo "Generated: $(date)"
echo "Filter: ${FILTER:-ALL}"
echo "======================================================"
echo "Transactions processed (blocks): ${TBLOCKS:-0}"
echo "Unique Transaction Ids processed: ${UIDS:-0}"
echo "Transactions with UPI leg (unique ids): ${UPI_UIDS:-0}"
echo "Failed Transactions with UPI leg (unique ids): ${UPI_SYSFAIL:-0}"
echo "Failed at UPI level (unique ids): ${UPI_FAIL:-0}"
echo "RRN available for UPI-linked (unique ids): ${RRN_PRESENT:-0}"
echo "RRN not available for UPI-linked (unique ids): ${RRN_MISSING:-0}"

if [ -n "$LIST" ]; then
  echo ""
  echo "--- UPI IDs (all) ---"
  printf "%s\n" "$LIST_ROWS" | awk -F"\t" '$2=="UPI_ALL"{print $3}' | sort | uniq
  echo ""
  echo "--- UPI IDs with RRN present ---"
  printf "%s\n" "$LIST_ROWS" | awk -F"\t" '$2=="UPI_RRN_PRESENT"{print $3}' | sort | uniq
  echo ""
  echo "--- UPI IDs with RRN missing ---"
  printf "%s\n" "$LIST_ROWS" | awk -F"\t" '$2=="UPI_RRN_MISSING"{print $3}' | sort | uniq
  echo ""
  echo "--- UPI IDs with system-level failure ---"
  printf "%s\n" "$LIST_ROWS" | awk -F"\t" '$2=="UPI_SYSFAIL"{print $3}' | sort | uniq
  echo ""
  echo "--- UPI IDs with UPI-level failure (RC != 0000) ---"
  printf "%s\n" "$LIST_ROWS" | awk -F"\t" '$2=="UPI_UPI_FAIL"{print $3}' | sort | uniq
fi

exit 0
