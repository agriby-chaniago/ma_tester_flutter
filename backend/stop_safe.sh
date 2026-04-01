#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
RUNTIME_DIR="$BACKEND_DIR/.runtime"
PID_FILE="$RUNTIME_DIR/backend_safe.pid"
LOCK_FILE="$RUNTIME_DIR/backend_safe.lock"
PORT="${PORT:-8000}"

find_port_pids() {
  if ! command -v ss >/dev/null 2>&1; then
    return 0
  fi

  ss -ltnp 2>/dev/null \
    | grep -E "(^|[[:space:]])LISTEN[[:space:]].*(:|\[::\]:)$PORT([[:space:]]|$)" \
    | grep -oE 'pid=[0-9]+' \
    | cut -d= -f2 \
    | sort -u
}

kill_orphan_backend_on_port() {
  local found=0
  while IFS= read -r port_pid; do
    [[ -z "$port_pid" ]] && continue
    if ! kill -0 "$port_pid" 2>/dev/null; then
      continue
    fi

    cmdline="$(ps -p "$port_pid" -o args= 2>/dev/null || true)"
    if [[ "$cmdline" == *"python run.py"* ]] || [[ "$cmdline" == *"backend/run.py"* ]] || [[ "$cmdline" == *"uvicorn"* ]] || [[ "$cmdline" == *"ma_tester_flutter/backend"* ]]; then
      kill "$port_pid" 2>/dev/null || true
      sleep 1
      if kill -0 "$port_pid" 2>/dev/null; then
        kill -9 "$port_pid" 2>/dev/null || true
      fi
      echo "[stop_safe] killed orphan backend pid=$port_pid on port $PORT"
      found=1
    fi
  done < <(find_port_pids)

  if [[ "$found" -eq 0 ]]; then
    echo "[stop_safe] no orphan backend listener found on port $PORT"
  fi
}

if [[ ! -f "$PID_FILE" ]]; then
  echo "[stop_safe] pid file not found"
  kill_orphan_backend_on_port
  exit 0
fi

pid="$(cat "$PID_FILE" 2>/dev/null || true)"
if [[ -z "$pid" ]]; then
  rm -f "$PID_FILE"
  echo "[stop_safe] empty pid file removed"
  kill_orphan_backend_on_port
  exit 0
fi

if kill -0 "$pid" 2>/dev/null; then
  pkill -P "$pid" 2>/dev/null || true
  kill "$pid" || true
  sleep 1
  pkill -P "$pid" 2>/dev/null || true
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" || true
  fi
  echo "[stop_safe] stopped pid=$pid"
else
  echo "[stop_safe] process not running pid=$pid"
fi

rm -f "$PID_FILE"
rm -f "$LOCK_FILE"
kill_orphan_backend_on_port
