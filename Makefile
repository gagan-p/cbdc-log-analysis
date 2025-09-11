.PHONY: help check

help:
	@echo "CBDC Log Analysis - Script Help"
	@echo "Generated: $$(date)"
	@echo ""
	@echo "--- get_real_failure_lines_fixed.sh ---"
	@bash get_real_failure_lines_fixed.sh --help || true
	@echo ""
	@echo "--- simple_cbdc_report.sh ---"
	@sh simple_cbdc_report.sh --help || true
	@echo ""
	@echo "--- find_log_block_by_txnid.sh ---"
	@bash find_log_block_by_txnid.sh --help || true
	@echo ""
	@echo "--- find_skew.sh ---"
	@sh find_skew.sh --help || true
	@echo ""
	@echo "--- find_missing_rrn_wip.sh ---"
	@sh find_missing_rrn_wip.sh --help || true
	@echo ""
	@echo "--- upi_summary_wip.sh ---"
	@sh upi_summary_wip.sh --help || true
	@echo ""
	@echo "--- analyze_queue_depths.sh ---"
	@echo "Usage: bash analyze_queue_depths.sh    # scans *.log and prints stats"
	@echo ""
	@echo "--- count_transaction_managers.sh ---"
	@echo "Usage: bash count_transaction_managers.sh  # infers TM pools from logs"

check:
	@echo "CBDC Log Analysis - Environment Check"
	@echo "OS: $$(uname -s)  Shell: $$SHELL"
	@echo "------------------------------------------------------------"
	@fail=0; \
	# awk check (prefer GNU awk)
	if awk --version 2>/dev/null | grep -q 'GNU Awk'; then \
	  echo "awk: GNU Awk detected ($$(awk --version 2>/dev/null | head -n1))"; \
	else \
	  if command -v gawk >/dev/null 2>&1; then \
	    echo "awk: BSD/other awk detected; gawk is available at $$(command -v gawk)"; \
	    echo "      Tip: alias awk=gawk for compatibility (macOS: brew install gawk)"; \
	  else \
	    echo "awk: WARN: GNU Awk not found. Install gawk (macOS: brew install gawk)"; \
	    fail=1; \
	  fi; \
	fi; \
	# date check (prefer GNU date for -d parsing)
	if date -u -d '1970-01-01 00:00:00' +%s >/dev/null 2>&1; then \
	  echo "date: GNU date OK ($$(date --version 2>/dev/null | head -n1 || echo 'version unknown'))"; \
	else \
	  if command -v gdate >/dev/null 2>&1; then \
	    echo "date: BSD date detected; gdate available at $$(command -v gdate)"; \
	    echo "      Tip: alias date=gdate for compatibility (macOS: brew install coreutils)"; \
	  else \
	    echo "date: WARN: GNU date not found. Install coreutils (macOS: brew install coreutils)"; \
	    fail=1; \
	  fi; \
	fi; \
	# core tools
	for t in sed grep sort mktemp; do \
	  if command -v $$t >/dev/null 2>&1; then \
	    echo "$$t: OK ($$(command -v $$t))"; \
	  else \
	    echo "$$t: WARN: not found in PATH"; \
	    fail=1; \
	  fi; \
	done; \
	# summary
	if [ $$fail -eq 0 ]; then \
	  echo "------------------------------------------------------------"; \
	  echo "Environment check: PASS"; \
	  exit 0; \
	else \
	  echo "------------------------------------------------------------"; \
	  echo "Environment check: FAIL (see warnings above)"; \
	  exit 1; \
	fi
