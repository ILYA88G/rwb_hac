#!/usr/bin/env bash
# Integration check: two atomic builds, source integrity and source-file hashes.
set -euo pipefail
MODEL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$MODEL_DIR/.." && pwd)"
REPORT_DIR="$MODEL_DIR/reports"
mkdir -p -- "$REPORT_DIR"
bash "$MODEL_DIR/run.sh" fingerprint > "$REPORT_DIR/raw_before.txt"
(cd -- "$PROJECT_DIR" && sha256sum data/*.csv) > "$REPORT_DIR/csv_before.sha256"
bash "$MODEL_DIR/run.sh" build > "$REPORT_DIR/build_first.log" 2>&1
bash "$MODEL_DIR/run.sh" check > "$REPORT_DIR/check_first.log" 2>&1
bash "$MODEL_DIR/run.sh" build > "$REPORT_DIR/build_second.log" 2>&1
bash "$MODEL_DIR/run.sh" check > "$REPORT_DIR/check_second.log" 2>&1
bash "$MODEL_DIR/run.sh" fingerprint > "$REPORT_DIR/raw_after.txt"
(cd -- "$PROJECT_DIR" && sha256sum data/*.csv) > "$REPORT_DIR/csv_after.sha256"
diff -u "$REPORT_DIR/raw_before.txt" "$REPORT_DIR/raw_after.txt"
diff -u "$REPORT_DIR/csv_before.sha256" "$REPORT_DIR/csv_after.sha256"
diff -u "$REPORT_DIR/check_first.log" "$REPORT_DIR/check_second.log"
printf 'PASS: both builds and controls; identical reports; raw contents and CSV hashes unchanged.\n'
cat -- "$REPORT_DIR/check_second.log"
