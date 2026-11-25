#!/bin/sh
# Retry while Postgres is still opening its first connection. A running server does not exit.
set -u
pid=""
stop() {
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  exit 0
}
trap stop TERM INT
i=0
while [ "$i" -lt 30 ]; do
  /app/mhbuddy &
  pid=$!
  wait "$pid"
  code=$?
  pid=""
  i=$((i + 1))
  echo "mhbuddy exited ${code}, retry ${i}" >&2
  sleep 2
done
exit 1
