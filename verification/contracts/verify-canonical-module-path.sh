#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STACK_ROOT="${STACK_ROOT:-${ROOT_DIR}/..}"
OLD_PATH='github.com/kaansari/ceerat-platform/packages/ceerat-contracts'

scan_roots=(
  "${STACK_ROOT}/contracts-repo"
  "${STACK_ROOT}/services-repo"
  "${STACK_ROOT}/apps-repo"
  "${STACK_ROOT}/ceerat-platform-builder-agent"
)

for root in "${scan_roots[@]}"; do
  [[ -d "${root}" ]] || continue
  if rg -n --hidden --glob '!.git/**' --glob '!**/.DS_Store' \
    --glob '!**/module-generation-standard.md' \
    "${OLD_PATH}" "${root}"; then
    echo "stale contracts module path found under ${root}" >&2
    exit 1
  fi
done

# Historical review records intentionally quote the path they identified.
if rg -n --hidden --glob '!.git/**' --glob '!**/.DS_Store' \
  --glob '!requirement/pr/codereview/**' \
  --glob '!requirement/proto-review.md' \
  --glob '!docs/superpowers/plans/**' \
  --glob '!verification/contracts/verify-canonical-module-path.sh' \
  "${OLD_PATH}" "${ROOT_DIR}"; then
  echo "stale contracts module path found in current infra files" >&2
  exit 1
fi

echo "canonical contracts module path verified"
