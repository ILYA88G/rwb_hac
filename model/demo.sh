#!/usr/bin/env bash
set -euo pipefail
MODEL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
printf '\n1. Checking the supplied data snapshot...\n'
bash "$MODEL_DIR/run.sh" check
printf '\n2. Checking report integrity...\n'
bash "$MODEL_DIR/query.sh" check
printf '\n3. Running all questions...\n'
bash "$MODEL_DIR/query.sh" all
printf '\nPASS: demo checks and report execution completed.\n'
