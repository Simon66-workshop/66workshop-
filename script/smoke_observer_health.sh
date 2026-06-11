#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASKLIGHT_BIN="$ROOT_DIR/tasklight"
PYTHON_BIN="$(command -v python3)"
STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tasklight-observer-health-XXXXXX")"
MATCH="tasklight-observer-smoke-$(python3 - <<'PY'
import secrets
print(secrets.token_hex(4))
PY
)"

cleanup() {
  if [[ -n "${WATCH_PID:-}" ]]; then
    kill "$WATCH_PID" >/dev/null 2>&1 || true
    wait "$WATCH_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$STATE_DIR"
}

trap cleanup EXIT INT TERM

export TASKLIGHT_STATE_DIR="$STATE_DIR"
export TASKLIGHT_OBSERVER_MATCH="$MATCH"
export TASKLIGHT_OBSERVER_MAX_AGE_SECONDS=10

"$ROOT_DIR/script/check_observer.sh" >"$STATE_DIR/check-before.txt"
grep -q "observer_watch_status=not_running" "$STATE_DIR/check-before.txt"

OBSERVER_WRAPPER="$STATE_DIR/observer-watch.sh"
cat >"$OBSERVER_WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
trap 'kill "\$observer_pid" >/dev/null 2>&1 || true' EXIT HUP INT TERM
bash -lc "export TASKLIGHT_STATE_DIR='$STATE_DIR'; '$PYTHON_BIN' '$ROOT_DIR/cli/tasklight.py' observe-local --watch" "$MATCH" >/dev/null 2>&1 &
observer_pid=\$!
wait "\$observer_pid"
EOF
chmod +x "$OBSERVER_WRAPPER"

bash "$OBSERVER_WRAPPER" >/dev/null 2>&1 &
WATCH_PID="$!"

sleep 0.6
"$ROOT_DIR/script/check_observer.sh" >"$STATE_DIR/check-running.txt"
grep -q "observer_watch_status=running" "$STATE_DIR/check-running.txt"
grep -q "observations_state_status=readable" "$STATE_DIR/check-running.txt"

kill "$WATCH_PID" >/dev/null 2>&1 || true
wait "$WATCH_PID" >/dev/null 2>&1 || true
unset WATCH_PID

sleep 0.6
"$ROOT_DIR/script/check_observer.sh" >"$STATE_DIR/check-after.txt"
grep -q "observer_watch_status=not_running" "$STATE_DIR/check-after.txt"

echo "smoke_observer_health: ok"
