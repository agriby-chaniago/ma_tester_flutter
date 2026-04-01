#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
RUNTIME_DIR="$BACKEND_DIR/.runtime"
PID_FILE="$RUNTIME_DIR/backend_safe.pid"
LOG_FILE="${LOG_FILE:-$RUNTIME_DIR/backend_safe.log}"

mkdir -p "$RUNTIME_DIR"

if [[ -f "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    echo "[start_safe] already running with pid=$old_pid"
    exit 0
  fi
fi

nohup "$BACKEND_DIR/run_safe.sh" > "$LOG_FILE" 2>&1 &
new_pid=$!
sleep 1

if ! kill -0 "$new_pid" 2>/dev/null; then
  echo "[start_safe] failed to start backend safely" >&2
  echo "[start_safe] check log: $LOG_FILE" >&2
  tail -n 40 "$LOG_FILE" 2>/dev/null || true
  exit 1
fi

echo "$new_pid" > "$PID_FILE"

echo "[start_safe] started pid=$new_pid"
echo "[start_safe] log: $LOG_FILE"
