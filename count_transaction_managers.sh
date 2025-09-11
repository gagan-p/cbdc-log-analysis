#!/bin/bash

# Prefer GNU awk if available (macOS compatibility)
if command -v gawk >/dev/null 2>&1; then AWK="gawk"; else AWK="awk"; fi

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

echo "=== TransactionManager Instance Analysis ==="
echo "Logs directory will be requested interactively"
echo ""

# Files are now in "$@" from the prompt validation above

# Count unique session pool configurations across all log files
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
echo "Based on session pool analysis, the system appears to have:"
echo "- Pool sizes indicate separate TransactionManager instances"
echo "- Each pool size represents a distinct TransactionManager configuration"
