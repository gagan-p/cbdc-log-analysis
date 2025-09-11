# TODOs

- Understand and standardize the caching helper usage across all functional scripts.
  - Review `scripts/helper/cache_utils.sh` and the template at `scripts/helper/cache_template.sh`.
  - Confirm which flags/args should be included in each script’s `ARGS_SIG`.
  - Make a short internal note for each script documenting its `script_id` and outputs.

- Validate behavior with different inputs:
  - Inputs changed → run and create new timestamped outputs under `scripts/output/`.
  - Inputs unchanged, script changed → duplicate previous outputs with a new timestamp.
  - Inputs unchanged, script unchanged → print previous outputs and skip work.

- Consider Make targets for common runs (optional):
  - `make run-report`, `make run-skew`, etc., to streamline manual runs.

- Defer WIP integration:
  - Do not apply the helper/template to scripts under `scripts/wip/` until functionality is final.

