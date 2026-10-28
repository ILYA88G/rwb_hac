#!/usr/bin/env bash
set -euo pipefail
MODEL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$MODEL_DIR/.." && pwd)"
QUESTION_DIR="$MODEL_DIR/sql/questions"

usage() {
    printf 'Usage: bash model/query.sh [list|all|check|NN_question_name]\n'
    printf 'Example: bash model/query.sh 03_average_check\n'
}
if (( $# > 1 )); then usage >&2; exit 2; fi
shopt -s nullglob
questions=("$QUESTION_DIR"/[0-9][0-9]_*.sql)
case "${1:-help}" in
    help|-h|--help) usage; exit 0 ;;
    list)
        for file in "${questions[@]}"; do
            name="$(basename -- "$file" .sql)"
            printf '%s\n' "$name"
        done
        exit 0
        ;;
    all) files=("${questions[@]}") ;;
    check) files=("$MODEL_DIR/sql/40_report_checks.sql") ;;
    *)
        if [[ ! "$1" =~ ^[0-9]{2}_[a-z0-9_]+$ ]]; then
            printf 'Use a question name from: bash model/query.sh list\n' >&2
            exit 2
        fi
        files=("$QUESTION_DIR/$1.sql")
        ;;
esac
if (( ${#files[@]} == 0 )); then
    printf 'No question files found in %s\n' "$QUESTION_DIR" >&2
    exit 1
fi
for file in "${files[@]}"; do
    name="$(basename -- "$file")"
    if [[ ! "$name" =~ ^[0-9]{2}_[a-z0-9_]+\.sql$ || ! -r "$file" || ! -s "$file" ]]; then
        printf 'Missing, empty or invalid SQL file: %s\n' "$file" >&2
        exit 1
    fi
done
cd -- "$PROJECT_DIR"
# SQL is sent through stdin because model is not mounted in the container.
# Every report runs within a single read-only transaction.
{
    for file in "${files[@]}"; do
        printf '\n\\echo === %s ===\n' "$(basename -- "$file")"
        cat -- "$file"
        printf '\n'
    done
} | docker compose exec -T postgres psql -X -q -U hack -d marketplace \
    -v ON_ERROR_STOP=1 -P pager=off --single-transaction \
    -c "SET TRANSACTION READ ONLY; SET LOCAL statement_timeout = '60s';" -f -
