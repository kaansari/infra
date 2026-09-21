#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/common.sh"

test_dir="$(mktemp -d)"
pid_file="$test_dir/service.pid"
sleep 30 &
managed_pid=$!
printf '%s\n' "$managed_pid" >"$pid_file"

cleanup() {
  kill "$managed_pid" >/dev/null 2>&1 || true
  rm -rf "$test_dir"
}
trap cleanup EXIT

restart_managed_process "test service" "$pid_file"

if kill -0 "$managed_pid" >/dev/null 2>&1; then
  echo "managed process was not stopped" >&2
  exit 1
fi

if [[ -e "$pid_file" ]]; then
  echo "managed PID file was not removed" >&2
  exit 1
fi

echo "start-stack lifecycle test passed"
