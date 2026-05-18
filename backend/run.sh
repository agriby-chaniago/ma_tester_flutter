#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
RUNTIME_DIR="$BACKEND_DIR/.runtime"
PID_FILE="$RUNTIME_DIR/backend.pid"
LOCK_FILE="$RUNTIME_DIR/backend.lock"
LOG_FILE="${LOG_FILE:-$RUNTIME_DIR/backend.log}"

VENV_DIR="${VENV_DIR:-$BACKEND_DIR/.venv}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
RESTART_DELAY_S="${RESTART_DELAY_S:-2}"
CKPT_PATH="${CKPT_PATH:-$BACKEND_DIR/ckpts_ma/best_state_dict.pt}"
REAL_PIPELINE_MODULE="${REAL_PIPELINE_MODULE:-ma_api.real_impl_notebook_port}"

PYTHON_BIN="$VENV_DIR/bin/python"

_check_deps() {
  if [[ ! -d "$VENV_DIR" ]]; then
    echo "[run] venv not found: $VENV_DIR" >&2; exit 1
  fi
  if [[ ! -x "$PYTHON_BIN" ]]; then
    echo "[run] python not found: $PYTHON_BIN" >&2; exit 1
  fi
  "$PYTHON_BIN" - <<'PY'
import importlib.util, sys
missing = [m for m in ["fastapi","uvicorn"] if importlib.util.find_spec(m) is None]
if missing:
    print("[run] missing packages: " + ", ".join(missing), file=sys.stderr); sys.exit(10)
PY
}

_port_in_use() {
  command -v ss >/dev/null 2>&1 && ss -ltn | awk '{print $4}' | grep -Eq "(^|:)$PORT$"
}

_port_owner() {
  command -v ss >/dev/null 2>&1 && ss -ltnp | grep -E "(:|\[::\]:)$PORT([[:space:]]|$)" || true
}

_kill_pid() {
  local pid="$1"
  kill -0 "$pid" 2>/dev/null || return 0
  pkill -P "$pid" 2>/dev/null || true
  kill "$pid" 2>/dev/null || true
  sleep 1
  pkill -P "$pid" 2>/dev/null || true
  kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
}

_find_port_pids() {
  command -v ss >/dev/null 2>&1 || return 0
  ss -ltnp 2>/dev/null \
    | grep -E "(:|\[::\]:)$PORT([[:space:]]|$)" \
    | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u
}

cmd_start() {
  mkdir -p "$RUNTIME_DIR"

  if [[ -f "$PID_FILE" ]]; then
    old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      echo "[run] already running pid=$old_pid"; exit 0
    fi
    rm -f "$PID_FILE"
  fi

  _check_deps || exit $?

  if _port_in_use; then
    echo "[run] port $PORT already in use:" >&2; _port_owner >&2; exit 3
  fi

  export HOST PORT CKPT_PATH REAL_PIPELINE_MODULE
  nohup bash "$0" _loop > "$LOG_FILE" 2>&1 &
  new_pid=$!
  sleep 1

  if ! kill -0 "$new_pid" 2>/dev/null; then
    echo "[run] failed to start. check log: $LOG_FILE" >&2
    tail -n 30 "$LOG_FILE" 2>/dev/null || true; exit 1
  fi

  echo "$new_pid" > "$PID_FILE"
  echo "[run] started pid=$new_pid"
  echo "[run] log: $LOG_FILE"
}

cmd_stop() {
  local pid=""
  if [[ -f "$PID_FILE" ]]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  fi

  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    _kill_pid "$pid"
    echo "[run] stopped pid=$pid"
  else
    echo "[run] not running (no pid)"
  fi

  rm -f "$PID_FILE" "$LOCK_FILE"

  while IFS= read -r port_pid; do
    [[ -z "$port_pid" ]] && continue
    cmdline="$(ps -p "$port_pid" -o args= 2>/dev/null || true)"
    if [[ "$cmdline" == *"run.py"* ]] || [[ "$cmdline" == *"uvicorn"* ]] || [[ "$cmdline" == *"ma_tester_flutter"* ]]; then
      _kill_pid "$port_pid"
      echo "[run] killed orphan pid=$port_pid"
    fi
  done < <(_find_port_pids)
}

cmd_status() {
  local pid=""
  if [[ -f "$PID_FILE" ]]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  fi

  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    echo "[run] running pid=$pid port=$PORT"
  else
    echo "[run] not running"
  fi
}

cmd_logs() {
  tail -f "${LOG_FILE}"
}

_loop() {
  cd "$BACKEND_DIR"

  if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE"
    flock -n 9 || { echo "[run] another instance running" >&2; exit 2; }
  fi

  while true; do
    "$PYTHON_BIN" run.py &
    child_pid=$!
    wait "$child_pid"
    code=$?

    [[ "$code" -eq 130 || "$code" -eq 143 ]] && break
    [[ "$code" -eq 10 ]] && { echo "[run] dep preflight failed; not restarting" >&2; break; }

    if _port_in_use; then
      echo "[run] port $PORT occupied after exit (code=$code); stopping" >&2; break
    fi

    echo "[run] exited code=$code, restarting in ${RESTART_DELAY_S}s..." >&2
    sleep "$RESTART_DELAY_S"
  done
}

case "${1:-}" in
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  restart) cmd_stop; sleep 1; cmd_start ;;
  status)  cmd_status ;;
  logs)    cmd_logs ;;
  _loop)   _loop ;;
  *)
    echo "usage: $(basename "$0") {start|stop|restart|status|logs}"
    exit 1
    ;;
esac
