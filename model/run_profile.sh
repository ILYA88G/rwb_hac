#!/usr/bin/env bash
set -euo pipefail

# Определяем расположение model и корня проекта.
MODEL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname -- "$MODEL_DIR")"

# Здесь находится существующий docker-compose.yml.
cd "$PROJECT_DIR"

# Передаём SQL из model в PostgreSQL внутри контейнера.
docker compose exec -T postgres \
    psql \
    -X \
    -U hack \
    -d marketplace \
    -v ON_ERROR_STOP=1 \
    --single-transaction \
    -f - \
    < "$MODEL_DIR/sql/00_profile.sql"
