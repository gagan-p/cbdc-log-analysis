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
- **Automatic TSV export:** `table_failed_txn_YYYYMMDD_HHMMSS.txt`
- **Detailed analysis file:** `abort_failures.txt`

### 2. System Load Analysis
**File:** `analyze_system_load.sh`

Analyzes system performance metrics from transaction logs.

### 3. Transaction Metrics Analysis
**Files:** 
- `analyze_transactions.sh` - Basic transaction analysis
- `analyze_transactions_aggregate.sh` - Aggregated metrics with caching

### 4. Transaction Block Finder
**File:** `find_log_block_by_txnid.sh`

Finds complete `<log>...</log>` blocks by transaction ID for detailed investigation.

**Usage:**
```bash
# Find all blocks containing a transaction ID
./find_log_block_by_txnid.sh TXNID --all-blocks

# Show only which file contains the transaction
./find_log_block_by_txnid.sh TXNID --file-only

# Show first N lines of the block
./find_log_block_by_txnid.sh TXNID --show-lines 20
```

### 5. Simple CBDC Report Generator  
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

## Key Achievements

### Complete Error Code Coverage
Our enhanced analysis successfully identified error codes for **ALL 148 failed transactions** (100% coverage):
- **0 transactions without error reasons** (previously had 49+ unknown failures)
- **Multi-format error detection:** Traditional patterns, XML-embedded codes, JSON-embedded codes, and original RC fields
- **Smart categorization:** Automatically distinguishes between internal (UseRC) and external (ExtRC) error sources

### Analysis Results
From analyzing 15,077 transactions across 7 log files:
- **Total transactions processed:** 15,077
- **Total failed transactions:** 148 (0.98% failure rate)
- **Unique failed transaction IDs:** 140
- **Error code coverage:** 100% (all failures have identified error codes)

### Automated TSV Export
- **Timestamped files:** `table_failed_txn_YYYYMMDD_HHMMSS.txt`
- **7-column format:** TxnID + 4 UseRC + 2 ExtRC columns
- **Ready for analysis:** Direct import into Excel/databases

### Enhanced Error Detection
The tool now detects errors from multiple sources:
1. **Traditional patterns:** `Use RC :`, `EXTRC:`
2. **XML-embedded:** `errCode="U30"`, `respCode="ZM"`
3. **JSON-embedded:** `"errCode":"96"`
4. **Original context:** `"orgRc":"BT"` from BACKOFFICE transactions

### Smart Categorization Logic
- **PSO/CBS/UPI/TOMAS transactions** → ExtRC (external system errors)
- **BACKOFFICE/APP internal** → UseRC (internal system errors)  
- **BACKOFFICE original errors** → ExtRC (inherited from external transaction timeouts)

## Contributing

When adding new analysis tools:
1. Follow the existing naming convention
2. Add usage documentation
3. Update this README
4. Test with sample log files

## License

Internal tool for CBDC transaction log analysis.