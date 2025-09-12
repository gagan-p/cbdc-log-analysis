# CBDC Log Analysis: Fresh Output Generation and Update Plan

## Goal

Generate a clean, consistent set of analysis outputs (from the main scripts only), store them in a standard location, and use these fresh outputs to update `key_observation.md` with the most recent findings.

## Standard Output Location

- All functional scripts write to: `scripts/output/`
- File naming: `<script>_YYYYMMDD_HHMMSS.txt` (or multiple files, in the case of failure analysis)
- Caching semantics (powered by `scripts/helper/cache_utils.sh`):
  - Inputs changed → run and generate new timestamped outputs
  - Inputs unchanged, script changed → do not recompute; duplicate previous outputs with a new timestamp
  - Inputs unchanged, script unchanged → skip work; print paths to previous outputs

WIP scripts under `scripts/wip/` are intentionally not wired into this flow until their functionality is finalized.

## Prerequisites

- Logs directory containing files matching `rtsp_q2-*.log`
- GNU-like tools available (checked via `make check`):
  - `gawk` or `awk` with needed features, `gdate` or `date`, plus `sed`, `grep`, `sort`, `mktemp`

## Fresh Start: Confirm No Outputs

From repo root:

1. Clean generated outputs and cache
   - `make clean`
   - Result: `scripts/output/` is removed. No script outputs remain.

2. Manual confirmation (optional)
   - `test ! -d scripts/output && echo "No outputs present."`

## Run Order and Expected Outputs

Each script is interactive and will prompt for the logs directory; enter your path (e.g., `rtsp_logs`). All outputs are written to `scripts/output/` with timestamps.

1) Failure Analysis
   - Script: `scripts/rtsp_analysis_scripts/get_real_failure_lines_fixed.sh`
   - Outputs:
     - `scripts/output/abort_failures_<ts>.txt`
     - `scripts/output/table_failed_txn_<ts>.txt` (TSV: TxnID + UseRC1..4 + ExtRC1..2)

2) Transaction Report (Aggregates)
   - Script: `scripts/rtsp_analysis_scripts/simple_cbdc_report.sh [--app|--pso|--filter APP|PSO] [--top-only] [--top N] [--top-by METRIC] [--compact|--raw]`
   - Output:
     - `scripts/output/simple_cbdc_report_<ts>.txt`

3) Transaction Block Finder
   - Script: `scripts/rtsp_analysis_scripts/find_log_block_by_txnid.sh TXNID [--file-only|--count-lines|--show-lines N|--all-blocks]`
   - Output:
     - `scripts/output/find_log_block_by_txnid_<ts>.txt`

4) Skew Analysis (Client vs Server Timestamp)
   - Script: `scripts/rtsp_analysis_scripts/find_skew.sh [--app|--pso|--filter APP|PSO] [--threshold SECONDS] [--top N] [--all] [--tsv]`
   - Output:
     - `scripts/output/find_skew_<ts>.txt`

5) Queue Depth Analysis
   - Script: `scripts/rtsp_analysis_scripts/analyze_queue_depths.sh`
   - Output:
     - `scripts/output/analyze_queue_depths_<ts>.txt`

6) TransactionManager Pools & Mapping
   - Script: `scripts/rtsp_analysis_scripts/count_transaction_managers.sh`
   - Output:
     - `scripts/output/count_transaction_managers_<ts>.txt`

## Updating `key_observation.md`

1. Run the scripts in the order above to regenerate fresh outputs.
2. Use these outputs to update:
   - Failure coverage and patterns: from `abort_failures_<ts>.txt` and the TSV
   - Aggregate performance and rankings: from `simple_cbdc_report_<ts>.txt`
   - Skew stats and thresholds hit: from `find_skew_<ts>.txt`
   - Queue depth distribution and evidence: from `analyze_queue_depths_<ts>.txt`
   - Pool sizes and txn mapping: from `count_transaction_managers_<ts>.txt`
3. Replace prior inline example commands in `key_observation.md` with the interactive flow and the new output file paths under `scripts/output/`.

## Notes on Re-Runs

- If you re-run without changes to logs or scripts, the helper rotates outputs: duplicates the last outputs with a new timestamp and removes the prior ones (no recompute).
- If you modify a script but keep the same inputs, the helper also rotates outputs: duplicates with a new timestamp and removes the prior ones (no recompute).
- If logs change (new or edited `rtsp_q2-*.log` files), the helper recomputes and emits fresh outputs.

## Housekeeping

- List current outputs: `make list-outputs`
- Clean all generated outputs (no backup): `make clean`
- Backup and clean outputs: `make clean-backup`
- Outputs live only under `scripts/output/`. Backups are stored under `scripts/output_backups/`.
