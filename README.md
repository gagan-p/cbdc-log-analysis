# CBDC Log Analysis Tools

This repository contains shell scripts for analyzing Central Bank Digital Currency (CBDC) transaction logs. The tools focus on failure analysis, performance metrics, queue depth, timestamp skew, UPI-specific checks, and quick transaction block lookup.

Scripts are interactive: each run prompts for the path to the rtsp_q2 log repository and requires a valid directory containing files that match `rtsp_q2-*.log`. They rely on standard Unix tooling (awk, sed, grep, date, sort, mktemp).

## Prerequisites

- awk: GNU awk recommended (uses features like `asorti`). On macOS: `brew install gawk`.
- date: GNU date recommended for `-d` parsing. On macOS: `brew install coreutils` and use `gdate` or run in a GNU-compatible environment.
- Standard tools: `sed`, `grep`, `sort`, `mktemp`.

Tip (macOS): you can symlink `gdate` to `date` in a shell alias when running these scripts, or edit scripts to substitute `gdate` if needed.

## Quickstart

- Summary of failures (and generate TSV + details):
  - `bash get_real_failure_lines_fixed.sh --summary-only`

- Top-N performance leaderboard (APP only):
  - `sh simple_cbdc_report.sh --app --top-only --top 20 --top-by total_ms`

- Client-server skew over 60s (top 50):
  - `sh find_skew.sh --threshold 60 --top 50`

- UPI blocks missing RRN (PSO only):
  - `sh find_missing_rrn_wip.sh --filter PSO --top 100`

- UPI summary by unique id (APP):
  - `sh upi_summary_wip.sh --filter APP`

- Inspect a full transaction block by id:
  - `bash find_log_block_by_txnid.sh TXN_OR_MSG_ID --show-lines 20`

- See script usage for all tools:
  - `make help`

- Verify environment/tools (GNU awk/date available):
  - `make check`

## Scripts

### get_real_failure_lines_fixed.sh
Primary failure analysis for TransactionManager blocks. Extracts only ABORTed transactions and discovers actual failure reasons from multiple sources.

- Features: Analyzes `<log realm="org.jpos.transaction.TransactionManager">` blocks; focuses on `<abort>` blocks only; extracts TXN_ID, TXNNAME, failure lines, Use RC, Ext RC; groups failures by first failure pattern; generates TSV table and detailed report.
- Error sources: Traditional fields (`Use RC :`, `EXTRC:`), XML attributes (`errCode=`, `respCode=`, `orgStatus=`), JSON fields (`"errCode"`, `"rc"`, `"orgRc"`), and RC lines.
- Categorization: Internal APP/BACKOFFICE errors → UseRC; External PSO/CBS/UPI/TOMAS errors → ExtRC; BACKOFFICE original external RC preserved under ExtRC.
- Outputs: Console summary; `abort_failures.txt` (detailed per-ABORT block); `table_failed_txn_YYYYMMDD_HHMMSS.txt` (7-column TSV: `TxnID, UseRC1..UseRC4, ExtRC1..ExtRC2`).
- Usage:
  - `./get_real_failure_lines_fixed.sh --help`
  - `./get_real_failure_lines_fixed.sh --summary-only`
  - `./get_real_failure_lines_fixed.sh --tsv-table`
  - `./get_real_failure_lines_fixed.sh --detailed`

### simple_cbdc_report.sh
Generates a comprehensive transaction performance report with APP/PSO filters, a Top-N ranking, and a full table of metrics aggregated by transaction type.

- Metrics: Count, total elapsed ms, average duration, TPS (min/avg/max), Peak TPS (min/avg/max), per-block average metric, elapsed (min/avg/max).
- Modes: Compact table (`--compact`), raw per-block rows (`--raw`), Top-only (`--top-only`) with `--top-by` selector.
- Filters: `--app`, `--pso`, or `--filter APP|PSO`.
- Inputs: Scans TransactionManager blocks; parses `Processing TXNNAME: ...`, `active-sessions`, `tps`, `peak`, `avg`, `elapsed`, `in-transit`.
- Outputs: Printed tables and Top-N ranking; summary totals for complete blocks and unique transaction types.
- Usage examples:
  - `sh simple_cbdc_report.sh --app --top-only --top 20 --top-by total_ms`
  - `sh simple_cbdc_report.sh --pso --compact`
  - `sh simple_cbdc_report.sh --raw --pso`

### find_log_block_by_txnid.sh
Finds complete `<log> ... </log>` blocks containing a given transaction id or token and prints the full block or a preview.

- Options: `--count-lines` (block size only), `--show-lines N` (preview N lines), `--file-only` (which file matches), `--all-blocks` (do not stop at first match).
- Inputs: Searches all `*.log` for the substring; not limited to TransactionManager realm.
- Output: File name, block line range and count, and optionally full block content.
- Usage:
  - `./find_log_block_by_txnid.sh TXNID`
  - `./find_log_block_by_txnid.sh TXNID --show-lines 20`
  - `./find_log_block_by_txnid.sh TXNID --file-only`

### find_skew.sh
Computes client vs server timestamp skew per TransactionManager block using server `at="..."` and client `<Head ... ts="...">`.

- Calculation: `skew_ms = client_ts_ms - server_at_ms` (both treated as UTC; fractional milliseconds supported where present).
- Filters: `--app`, `--pso`, or `--filter APP|PSO`.
- Controls: `--threshold S` (seconds), `--top N`, `--all`, `--tsv`.
- Outputs: Summary totals and a table with columns: `ABS_SKEW_MS, SKEW_MS, SERVER_AT, CLIENT_TS, TXN_TYPE, TXN_ID/MSG_ID, FILE`.
- Usage:
  - `sh find_skew.sh`
  - `sh find_skew.sh --app --threshold 60 --top 50`
  - `sh find_skew.sh --pso --all --tsv`

### find_missing_rrn_wip.sh
Flags UPI TransactionManager blocks missing a Request Reference Number (RRN).

- UPI detection: Presence of UPI schema URL or common UPI API names in block content.
- RRN detection: Case-insensitive keys `txn-rrn` or `rrn` in JSON/kv forms, with non-empty, non-null value.
- Filters: `--filter APP|PSO`.
- Output: Rows (`SERVER_AT, TXN_TYPE, MSG_ID, TXN_ID, FILE`) and totals; `--tsv` for machine parsing; `--top` or `--all` to control row count.
- Usage:
  - `sh find_missing_rrn_wip.sh --filter PSO --top 100`
  - `sh find_missing_rrn_wip.sh --all --tsv`

### upi_summary_wip.sh
Summarizes UPI-related activity by unique transaction id (msgId or TXN_ID).

- Metrics: Total TransactionManager blocks; unique ids; unique ids with UPI leg; unique ids with system failure; UPI-level failures (RC != 0000); RRN present vs missing.
- Filters: `--filter APP|PSO`.
- Output: Human-readable summary or TSV (`--tsv`). Optional per-id lists with `--list`.
- Usage:
  - `sh upi_summary_wip.sh`
  - `sh upi_summary_wip.sh --filter APP --list`

### analyze_queue_depths.sh
Analyzes in-transit queue depth across all logs and reports distribution and peaks.

- Extraction: Greps `in-transit=X/Y` occurrences from all `*.log` files.
- Statistics: Min, median, average, 90th percentile, max; sample evidence lines for peaks and saturated pools.
- Verification: Prints commands to reproduce findings; shows example lines with file and line numbers.
- Usage:
  - `bash analyze_queue_depths.sh`

### count_transaction_managers.sh
Quick helper to infer TransactionManager instances and their pool sizes from logs.

- Unique pools: Lists distinct `active-sessions=current/max` configurations seen across logs.
- Mapping: Associates transaction types with pool max size to hint at distinct TM instances.
- Usage:
  - `bash count_transaction_managers.sh`

## Log File Requirements

The tools expect log files with:
- TransactionManager realm blocks
- ABORT and COMMIT indicators
- TXN_ID and TXNNAME fields
- Error codes in Use RC/EXTRC fields or embedded in XML/JSON (errCode/respCode/rc)

## Dynamic Failure Categorization

Failure analysis is data-driven, discovering patterns directly from logs:
- Automatically detects new error types and formats
- No hard-coded category lists
- Groups similar failures by normalized first-line pattern
- Distinguishes internal vs external sources via txn type and context

## TSV Output Format (failures)

The failure TSV (`--tsv-table` and auto-generated file) uses 7 columns:
- TxnID: Transaction identifier
- UseRC1-4: Up to 4 internal error codes
- ExtRC1-2: Up to 2 external error codes

Empty columns indicate values not found for that transaction.

## Contributing

When adding new analysis tools:
1. Follow the existing naming convention.
2. Add usage documentation and examples.
3. Update this README.
4. Test with representative log files.

## License

Internal tool for CBDC transaction log analysis.
