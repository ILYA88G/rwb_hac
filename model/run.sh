#!/usr/bin/env bash
set -euo pipefail
MODEL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$MODEL_DIR/.." && pwd)"
case "${1:-build}" in
    build) sql_file="$MODEL_DIR/build.sql" ;;
    check) sql_file="$MODEL_DIR/checks.sql" ;;
    fingerprint) sql_file="$MODEL_DIR/raw_fingerprint.sql" ;;
    *) printf 'Usage: bash model/run.sh [build|check|fingerprint]\n' >&2; exit 2 ;;
esac
cd -- "$PROJECT_DIR"
if ! docker info >/dev/null 2>&1; then
    printf 'Docker is unavailable for this user. Start Docker or run: sudo bash model/run.sh %s\n' "${1:-build}" >&2
    exit 1
fi
if ! docker compose exec -T postgres pg_isready -U hack -d marketplace >/dev/null 2>&1; then
    printf 'The existing postgres service is not ready. This script does not start/reset/load raw.\n' >&2
    exit 1
fi
# Credentials match the educational compose file. No database/source reset.
docker compose exec -T postgres psql -X -U hack -d marketplace \
    -v ON_ERROR_STOP=1 -P pager=off -f - < "$sql_file"
