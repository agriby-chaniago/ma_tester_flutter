#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
RUNTIME_DIR="$BACKEND_DIR/.runtime"
PID_FILE="$RUNTIME_DIR/backend_safe.pid"
LOCK_FILE="$RUNTIME_DIR/backend_safe.lock"

VENV_DIR="${VENV_DIR:-$BACKEND_DIR/.venv}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
RESTART_DELAY_S="${RESTART_DELAY_S:-2}"

if [[ ! -d "$VENV_DIR" ]]; then
  echo "[run_safe] venv not found: $VENV_DIR" >&2
  echo "[run_safe] set VENV_DIR=/path/to/venv" >&2
  exit 1
fi

PYTHON_BIN="$VENV_DIR/bin/python"
if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "[run_safe] python binary not found or not executable: $PYTHON_BIN" >&2
  exit 1
fi

mkdir -p "$RUNTIME_DIR"

cd "$BACKEND_DIR"

check_python_deps() {
  "$PYTHON_BIN" - <<'PY'
import importlib.util
import sys

required = ["fastapi", "uvicorn"]
missing = [name for name in required if importlib.util.find_spec(name) is None]

if missing:
    print("[run_safe] missing required python packages: " + ", ".join(missing), file=sys.stderr)
    print("[run_safe] install with: ./.venv/bin/python -m pip install -r requirements.txt", file=sys.stderr)
    sys.exit(10)
PY
}

if ! check_python_deps; then
  exit 10
fi

if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    echo "[run_safe] another run_safe instance is already running" >&2
    echo "[run_safe] use ./stop_safe.sh first" >&2
    exit 2
  fi
fi

port_in_use() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltn | awk '{print $4}' | grep -Eq "(^|:)$PORT$"
    return $?
  fi
  return 1
}

print_port_owner() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp | grep -E "(^|[[:space:]])LISTEN[[:space:]].*(:|\[::\]:)$PORT([[:space:]]|$)" || true
  fi
}

echo "[run_safe] backend root: $BACKEND_DIR"
echo "[run_safe] venv: $VENV_DIR"
echo "[run_safe] python: $PYTHON_BIN"
echo "[run_safe] listening on $HOST:$PORT"

CURRENT_CHILD_PID=""

cleanup_child() {
  if [[ -n "$CURRENT_CHILD_PID" ]] && kill -0 "$CURRENT_CHILD_PID" 2>/dev/null; then
    kill "$CURRENT_CHILD_PID" 2>/dev/null || true
    sleep 1
    if kill -0 "$CURRENT_CHILD_PID" 2>/dev/null; then
      kill -9 "$CURRENT_CHILD_PID" 2>/dev/null || true
    fi
  fi
}

trap cleanup_child EXIT INT TERM

if [[ "${SUDO_USER:-}" != "" ]]; then
  echo "[run_safe] warning: running with sudo is not recommended" >&2
  echo "[run_safe] use ./start_safe.sh without sudo" >&2
fi

if port_in_use; then
  echo "[run_safe] port $PORT is already in use; refusing to start" >&2
  print_port_owner >&2
  echo "[run_safe] stop existing server or change PORT" >&2
  exit 3
fi

auto_run() {
  while true; do
    "$PYTHON_BIN" run.py &
    CURRENT_CHILD_PID="$!"
    wait "$CURRENT_CHILD_PID"
    code=$?
    CURRENT_CHILD_PID=""

    if [[ "$code" -eq 130 || "$code" -eq 143 ]]; then
      echo "[run_safe] received termination signal; exiting" >&2
      break
    fi

    if [[ "$code" -eq 10 ]]; then
      echo "[run_safe] dependency preflight failed; exiting without restart" >&2
      break
    fi

    if port_in_use; then
      echo "[run_safe] detected port $PORT occupied after exit (code=$code); stopping loop" >&2
      print_port_owner >&2
      break
    fi

    echo "[run_safe] backend exited (code=$code), restarting in ${RESTART_DELAY_S}s..." >&2
    sleep "$RESTART_DELAY_S"
  done
}

export HOST PORT

auto_run
