#!/bin/bash

set -euo pipefail

OUTPUT_DIR="scripts/output"
BACKUP_DIR="scripts/output_backups"

usage() {
  cat <<EOF
Cleanup utility for analysis outputs

Usage:
  bash scripts/helper/cleanup_outputs.sh [--backup|--no-backup] [--list] [--yes]

Options:
  --backup     Create a compressed backup of scripts/output, then remove it
  --no-backup  Remove scripts/output without creating a backup
  --list       Show current contents of scripts/output (if any) and exit
  --yes        Do not prompt for confirmation
  --help,-h    Show this help

Notes:
  - Outputs are created by analysis scripts under scripts/output
  - Backups are stored under scripts/output_backups as tar.gz archives
EOF
}

MODE=""
ASSUME_YES=""
LIST_ONLY=""

for arg in "$@"; do
  case "$arg" in
    --backup) MODE="backup" ;;
    --no-backup) MODE="delete" ;;
    --list) LIST_ONLY=1 ;;
    --yes) ASSUME_YES=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage; exit 1 ;;
  esac
done

if [ -n "$LIST_ONLY" ]; then
  if [ -d "$OUTPUT_DIR" ]; then
    echo "Listing $OUTPUT_DIR:"; ls -la "$OUTPUT_DIR"
  else
    echo "$OUTPUT_DIR does not exist."
  fi
  exit 0
fi

if [ ! -d "$OUTPUT_DIR" ]; then
  echo "$OUTPUT_DIR does not exist; nothing to clean."
  exit 0
fi

if [ -z "$MODE" ]; then
  echo "Choose cleanup mode:"
  echo "  [b] Backup then delete"
  echo "  [d] Delete without backup"
  read -r -p "Enter choice (b/d): " choice
  case "$choice" in
    b|B) MODE="backup" ;;
    d|D) MODE="delete" ;;
    *) echo "Invalid choice." >&2; exit 1 ;;
  esac
fi

confirm() {
  [ -n "$ASSUME_YES" ] && return 0
  read -r -p "$1 [y/N]: " ans
  case "$ans" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

if [ "$MODE" = "backup" ]; then
  ts=$(date +%Y%m%d_%H%M%S)
  mkdir -p "$BACKUP_DIR"
  archive="$BACKUP_DIR/output_$ts.tar.gz"
  echo "Creating backup archive: $archive"
  tar -czf "$archive" -C scripts output
  echo "Backup created: $archive"
  if confirm "Remove $OUTPUT_DIR after backup?"; then
    rm -rf "$OUTPUT_DIR"
    echo "Removed $OUTPUT_DIR"
  else
    echo "Skipped deletion of $OUTPUT_DIR"
  fi
elif [ "$MODE" = "delete" ]; then
  if confirm "Permanently delete $OUTPUT_DIR without backup?"; then
    rm -rf "$OUTPUT_DIR"
    echo "Removed $OUTPUT_DIR"
  else
    echo "Aborted deletion."
  fi
fi

exit 0

