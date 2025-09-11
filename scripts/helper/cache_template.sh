#!/bin/bash
# Template include for integrating caching/output behavior into a script.
#
# How to use:
# 1) Your script should already have:
#    - Argument parsing and variables for flags you care about
#    - Interactive prompt that sets LOGDIR and builds the input files list
#      e.g. INPUTS=("$LOGDIR"/rtsp_q2-*.log)
# 2) Source this file after that, then copy the block below and replace
#    <script_id> and <output_base>. Add any flags that affect results to ARGS_SIG.
#
# Note: This template expects Bash (for process substitution/arrays).

. scripts/helper/cache_utils.sh

# Example integration block (copy/paste and edit):
# ------------------------------------------------
# INPUTS=("$LOGDIR"/rtsp_q2-*.log)
# ARGS_SIG="FLAG1=$FLAG1;FLAG2=$FLAG2"   # include only flags that alter results
# cache_prepare "<script_id>" "$0" "$ARGS_SIG" "${INPUTS[@]}"
#
# if [ "$CACHE_STATUS" = "noop" ]; then
#   echo "No changes detected (inputs and script unchanged). Skipping run."
#   echo "Previous outputs: $CACHE_LAST_OUTPUTS"
#   exit 0
# elif [ "$CACHE_STATUS" = "duplicate" ]; then
#   echo "Inputs unchanged; script changed. Duplicating previous outputs with new timestamp."
#   cache_duplicate_outputs
#   cache_save_meta
#   echo "New outputs: $CACHE__OUTPUTS"
#   exit 0
# fi
#
# OUT_FILE="$CACHE_OUT_DIR/<output_base>_${CACHE_TS}.txt"
# cache_register_output "$OUT_FILE"
# exec > >(tee "$OUT_FILE") 2>&1
#
# # --- RUN: your script’s analysis and printing logic here ---
# # echo "Report header..."
# # printf "rows...\n"
# # --- END RUN ---
#
# echo "Saved output: $OUT_FILE"
# cache_save_meta
# ------------------------------------------------

