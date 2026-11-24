#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="${HOME}/flutter/bin:${HOME}/pg/bin:${PATH}"
export LD_LIBRARY_PATH="${HOME}/pg/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export DATABASE_URL="${DATABASE_URL:-postgres://ubuntu@127.0.0.1:5432/mhbuddy?sslmode=disable}"
export PORT="${PORT:-8080}"
PID="$ROOT/.run/dev.pid"
LOG="$ROOT/.run/dev.log"

start_pg() {
  if [[ ! -x "${HOME}/pg/bin/pg_ctl" ]]; then
    echo "postgres binaries missing at ${HOME}/pg" >&2
    exit 1
  fi
  if ! pg_ctl -D "${HOME}/pgdata" status >/dev/null 2>&1; then
    pg_ctl -D "${HOME}/pgdata" -l "${HOME}/pg.log" start -o "-p 5432 -k /tmp -c listen_addresses=127.0.0.1"
  fi
}

case "${1:-start}" in
  start)
    start_pg
    mkdir -p "$ROOT/.run"
    if [[ -f "$PID" ]] && kill -0 "$(cat "$PID")" 2>/dev/null; then
      echo "already running pid $(cat "$PID")"
    else
      (cd "$ROOT/services/api" && MH_DEV_AUTH=1 PORT="$PORT" DATABASE_URL="$DATABASE_URL" go run ./cmd/mhbuddy) >"$LOG" 2>&1 &
      echo $! >"$PID"
    fi
    for _ in $(seq 1 60); do
      if curl -fsS "http://127.0.0.1:${PORT}/healthz" >/dev/null; then
        echo "preview http://127.0.0.1:${PORT}/"
        echo "encyclopedia http://127.0.0.1:${PORT}/g/world/entries"
        echo "public build http://127.0.0.1:${PORT}/builds/pub-fixture-wilds-1"
        exit 0
      fi
      sleep 0.5
    done
    echo "healthz failed; see $LOG" >&2
    exit 1
    ;;
  stop)
    if [[ -f "$PID" ]]; then
      kill "$(cat "$PID")" 2>/dev/null || true
      rm -f "$PID"
    fi
    echo "stopped"
    ;;
  *)
    echo "usage: tools/dev.sh start|stop" >&2
    exit 2
    ;;
esac
