#!/bin/sh
set -eu

: "${DB_USER:=postgres}"
: "${DB_NAME:=palee_dev}"
: "${DB_RUNTIME_USER:=milos_runtime}"
: "${DB_RUNTIME_PASSWORD:?DB_RUNTIME_PASSWORD is required}"

docker compose exec -T \
  -e POSTGRES_RUNTIME_USER="$DB_RUNTIME_USER" \
  -e POSTGRES_RUNTIME_PASSWORD="$DB_RUNTIME_PASSWORD" \
  postgres sh /docker-entrypoint-initdb.d/010-palee-runtime-role.sh
