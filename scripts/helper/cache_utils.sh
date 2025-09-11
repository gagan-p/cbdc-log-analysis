#!/bin/sh

# Common caching helper for analysis scripts
# Decides whether to run, duplicate prior outputs, or do nothing based on:
# - Input files content hash
# - Script file content hash
# - Arguments signature (string)
#
# Exports:
#   CACHE_STATUS    : run | duplicate | noop
#   CACHE_TS        : timestamp (YYYYMMDD_HHMMSS)
#   CACHE_OUT_DIR   : scripts/output
#   CACHE_META_FILE : scripts/output/.cache/<script_id>.meta
#   CACHE_LAST_OUTPUTS : space-separated list from previous run (if any)
# Functions:
#   cache_prepare <script_id> <script_path> <args_signature> <input_files...>
#   cache_register_output <path>
#   cache_save_meta
#   cache_duplicate_outputs  (creates new timestamped copies of last outputs)

set -e

# pick a hashing command
cache__hash_cmd=""
if command -v sha256sum >/dev/null 2>&1; then cache__hash_cmd="sha256sum"; fi
if [ -z "$cache__hash_cmd" ] && command -v shasum >/dev/null 2>&1; then cache__hash_cmd="shasum -a 256"; fi
if [ -z "$cache__hash_cmd" ] && command -v md5sum >/dev/null 2>&1; then cache__hash_cmd="md5sum"; fi

cache__hash_string() {
  # $1 = string
  printf "%s" "$1" | ${cache__hash_cmd} 2>/dev/null | awk '{print $1}'
}

cache__hash_files() {
  # files in args; stable ordering
  for f in "$@"; do printf "%s\n" "$f"; done | sort | while read -r f; do
    ${cache__hash_cmd} "$f" 2>/dev/null | awk '{print $1}'
  done | ${cache__hash_cmd} 2>/dev/null | awk '{print $1}'
}

# internal accumulators
CACHE__OUTPUTS=""

cache_prepare() {
  script_id="$1"; shift
  script_path="$1"; shift
  args_sig="$1"; shift
  input_files="$@"

  CACHE_OUT_DIR="scripts/output"
  mkdir -p "$CACHE_OUT_DIR/.cache"
  CACHE_META_FILE="$CACHE_OUT_DIR/.cache/${script_id}.meta"

  # hashes
  files_hash="$(cache__hash_files $input_files)"
  args_hash="$(cache__hash_string "$args_sig")"
  script_hash="$( ${cache__hash_cmd} "$script_path" 2>/dev/null | awk '{print $1}' )"
  CACHE_TS="$(date +%Y%m%d_%H%M%S)"

  # load previous meta if present
  CACHE_LAST_OUTPUTS=""
  last_files_hash=""; last_args_hash=""; last_script_hash=""
  if [ -f "$CACHE_META_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CACHE_META_FILE"
  fi

  if [ "$files_hash" != "$last_files_hash" ] || [ -z "$last_files_hash" ]; then
    CACHE_STATUS="run"
  elif [ "$script_hash" != "$last_script_hash" ]; then
    CACHE_STATUS="duplicate"
  else
    CACHE_STATUS="noop"
  fi

  # export for callers
  export CACHE_STATUS CACHE_TS CACHE_OUT_DIR CACHE_META_FILE CACHE_LAST_OUTPUTS
  # keep for save
  export cache__files_hash="$files_hash" cache__args_hash="$args_hash" cache__script_hash="$script_hash" script_id
}

cache_register_output() {
  # $1: path
  if [ -z "$CACHE__OUTPUTS" ]; then CACHE__OUTPUTS="$1"; else CACHE__OUTPUTS="$CACHE__OUTPUTS $1"; fi
}

cache_save_meta() {
  {
    echo "last_files_hash='$cache__files_hash'"
    echo "last_args_hash='$cache__args_hash'"
    echo "last_script_hash='$cache__script_hash'"
    echo "CACHE_LAST_OUTPUTS='$CACHE__OUTPUTS'"
  } > "$CACHE_META_FILE"
}

cache_duplicate_outputs() {
  # duplicate each prior output to a new timestamped file using the same extension
  new_outputs=""
  for p in $CACHE_LAST_OUTPUTS; do
    base="$(basename "$p")"
    ext="${base##*.}"
    stem="${base%.*}"
    # remove any old timestamp and append new one
    new="$CACHE_OUT_DIR/${stem%_*}_$CACHE_TS.${ext}"
    cp -f "$p" "$new" 2>/dev/null || true
    if [ -z "$new_outputs" ]; then new_outputs="$new"; else new_outputs="$new_outputs $new"; fi
  done
  CACHE__OUTPUTS="$new_outputs"
}

