# CBDC Log Analysis Tools

This repository contains shell scripts for analyzing Central Bank Digital Currency (CBDC) transaction logs, specifically focusing on failure analysis and transaction metrics.

## Main Tools

### 1. CBDC Failure Analysis Tool
**File:** `get_real_failure_lines_fixed.sh`

The primary tool for analyzing transaction failures in CBDC logs.

**Features:**
- Analyzes all .log files in current directory
- Extracts failed transactions from ABORT blocks only
- Provides dynamic failure categorization based on actual log data
- Multiple output formats with flexible display options

**Usage:**
```bash
# Show help
./get_real_failure_lines_fixed.sh --help

# Summary only (statistics + failure patterns)
./get_real_failure_lines_fixed.sh --summary-only

# TSV table format (7 columns: TxnID, UseRC1-4, ExtRC1-2)
./get_real_failure_lines_fixed.sh --tsv-table

# Full detailed analysis (default)
./get_real_failure_lines_fixed.sh --detailed
```

**Output Includes:**
- Total transactions processed
- Total failed transactions  
- Unique failed transaction IDs
- Dynamic failure pattern grouping
- Detailed transaction-by-transaction analysis

### 2. System Load Analysis
**File:** `analyze_system_load.sh`

Analyzes system performance metrics from transaction logs.

### 3. Transaction Metrics Analysis
**Files:** 
- `analyze_transactions.sh` - Basic transaction analysis
- `analyze_transactions_aggregate.sh` - Aggregated metrics with caching

### 4. Simple CBDC Report Generator  
**File:** `simple_cbdc_report.sh`

Generates executive summary reports with top transaction types by performance metrics.

## Log File Requirements

The tools expect log files with:
- TransactionManager realm blocks
- ABORT and COMMIT transaction indicators  
- TXN_ID and TXNNAME fields
- Use RC and EXTRC error codes

## Dynamic Failure Categorization

Unlike traditional static categorization, these tools discover failure patterns dynamically from the actual log data. This ensures:
- New error types are automatically detected
- No hard-coded categories that might miss new errors
- Adapts to different log formats and error codes
- Groups similar errors intelligently

## TSV Output Format

The `--tsv-table` option provides a 7-column tab-separated format:

| Column | Description |
|--------|-------------|
| TxnID | Transaction identifier |
| UseRC1-4 | Up to 4 Use RC error codes per transaction |
| ExtRC1-2 | Up to 2 Extended RC error codes per transaction |

Empty columns indicate values not available for that transaction.

## Example Results

From analyzing 15,077 transactions across multiple log files:
- **Total failed transactions:** 148 (0.98% failure rate)
- **Unique failed transactions:** 140
- **Top failure patterns:**
  - 42 cases: `java.lang.NullPointerException`
  - 15 cases: `Use RC : 96,Unable to Process`
  - 12 cases: `Use RC : ZH,INVALID VIRTUAL ADDRESS`
  - 8 cases: Transaction limit exceeded

## Contributing

When adding new analysis tools:
1. Follow the existing naming convention
2. Add usage documentation
3. Update this README
4. Test with sample log files

## License

Internal tool for CBDC transaction log analysis.