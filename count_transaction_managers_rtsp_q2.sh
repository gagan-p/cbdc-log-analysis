#!/bin/bash

# Prefer GNU awk if available (macOS compatibility)
if command -v gawk >/dev/null 2>&1; then AWK="gawk"; else AWK="awk"; fi

echo "=== TransactionManager Instance Analysis (rtsp_q2) ==="
echo ""

# Prompt for logs directory containing rtsp_q2-*.log
read -r -p "Enter path to rtsp_q2 logs directory [rtsp_logs]: " LOGDIR
LOGDIR=${LOGDIR:-rtsp_logs}

if [ ! -d "$LOGDIR" ]; then
  echo "ERROR: Directory not found: $LOGDIR" >&2
  exit 1
fi

# Expand matching logs
set -- "$LOGDIR"/rtsp_q2-*.log
if [ "$1" = "$LOGDIR/rtsp_q2-*.log" ] || [ $# -eq 0 ]; then
  echo "ERROR: No rtsp_q2-*.log files found in: $LOGDIR" >&2
  exit 1
fi

echo "Logs directory: $LOGDIR"
echo "Files matched: $#"
echo ""

echo "Unique session pool configurations:"
grep "active-sessions=" -- "$@" | sed 's/.*active-sessions=\([0-9]*\/[0-9]*\).*/\1/' | sort | uniq -c

echo ""
echo "=== Transaction Type to Session Pool Mapping (all matched files) ==="

"$AWK" '
/<log.*TransactionManager.*at=/ {
  in_tx=1; txn_type=""; sessions=""; next
}
in_tx && /Processing TXNNAME:/ {
  if (match($0, /Processing TXNNAME: ([^,]+)/, arr)) txn_type=arr[1]
}
in_tx && /active-sessions=/ {
  if (match($0, /active-sessions=([0-9]+)\/([0-9]+)/, sess)) {
    sessions=sess[2]
  }
}
in_tx && /<\/log>/ {
  if (txn_type && sessions) {
    if (index(pools[sessions], txn_type) == 0) {
      if (pools[sessions] == "") pools[sessions] = txn_type; else pools[sessions] = pools[sessions] " " txn_type
    }
  }
  in_tx=0
}
END {
  for (pool in pools) {
    print "Pool " pool ": " pools[pool]
  }
}
' -- "$@"

echo ""
echo "=== Summary ==="
echo "- Pool sizes indicate separate TransactionManager instances"
echo "- Each pool size likely represents a distinct TransactionManager configuration"

exit 0

