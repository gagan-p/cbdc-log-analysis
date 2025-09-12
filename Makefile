.PHONY: help check clean clobber clean-backup list-outputs

help:
	@echo "CBDC Log Analysis - Script Help"
	@echo "Generated: $$(date)"
	@echo ""
	@echo "Scripts (interactive; prompt for rtsp_q2 logs):"
	@echo "- scripts/rtsp_analysis_scripts/get_real_failure_lines_fixed.sh"
	@echo "- scripts/rtsp_analysis_scripts/simple_cbdc_report.sh"
	@echo "- scripts/rtsp_analysis_scripts/find_log_block_by_txnid.sh"
	@echo "- scripts/rtsp_analysis_scripts/find_skew.sh"
	@echo "- scripts/rtsp_analysis_scripts/analyze_queue_depths.sh"
	@echo "- scripts/rtsp_analysis_scripts/count_transaction_managers.sh"
	@echo ""
	@echo "WIP:"
	@echo "- scripts/wip/find_missing_rrn_wip.sh"
	@echo "- scripts/wip/upi_summary_wip.sh"
	@echo ""
	@echo "Outputs are written to scripts/output with timestamps."
	@echo "Use 'make clean' to remove generated outputs and caches."

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

clean:
	@echo "Cleaning generated outputs (no backup)..."
	@bash scripts/helper/cleanup_outputs.sh --no-backup --yes

clean-backup:
	@echo "Backing up and cleaning generated outputs..."
	@bash scripts/helper/cleanup_outputs.sh --backup --yes

list-outputs:
	@bash scripts/helper/cleanup_outputs.sh --list

clobber: clean
	@echo "No additional artifacts to clobber."
