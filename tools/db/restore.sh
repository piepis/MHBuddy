#!/usr/bin/env bash
# Restore a custom-format dump into DATABASE_URL. Does not print the connection string.
set -euo pipefail
export PATH="${HOME}/pg/bin:${PATH}"
export LD_LIBRARY_PATH="${HOME}/pg/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
: "${DATABASE_URL:=postgres://ubuntu@127.0.0.1:5432/mhbuddy?sslmode=disable}"
FILE="${1:-}"
if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "usage: tools/db/restore.sh <dump-file>" >&2
  exit 2
fi
pg_restore --clean --if-exists --no-owner --dbname "$DATABASE_URL" "$FILE"
echo "restored $FILE"
