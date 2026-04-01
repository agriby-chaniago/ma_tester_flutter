#!/usr/bin/env bash
set -euo pipefail

URL="${URL:-http://127.0.0.1:8000/healthz}"
MAX_WAIT_S="${MAX_WAIT_S:-30}"
SLEEP_S="${SLEEP_S:-1}"

elapsed=0
while (( elapsed < MAX_WAIT_S )); do
  if curl -fsS "$URL" >/dev/null 2>&1; then
    echo "[wait_health] healthy: $URL"
    exit 0
  fi
  sleep "$SLEEP_S"
  elapsed=$((elapsed + SLEEP_S))
done

echo "[wait_health] timeout after ${MAX_WAIT_S}s: $URL" >&2
exit 1
