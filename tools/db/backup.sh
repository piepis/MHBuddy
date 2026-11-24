#!/usr/bin/env bash
# Dump the MH伙伴助手 Postgres database. Does not print the connection string.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export PATH="${HOME}/pg/bin:${PATH}"
export LD_LIBRARY_PATH="${HOME}/pg/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
: "${DATABASE_URL:=postgres://ubuntu@127.0.0.1:5432/mhbuddy?sslmode=disable}"
OUT="${1:-$ROOT/mhbuddy.dump}"
case "$OUT" in
  /*) ;;
  *) OUT="$ROOT/$OUT" ;;
esac
pg_dump --format=custom --no-owner --file "$OUT" "$DATABASE_URL"
echo "wrote $OUT"
