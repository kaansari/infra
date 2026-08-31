#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workspace_root="$(cd "$script_dir/../../.." && pwd)"
build_context="$script_dir/.build-context"

case "$build_context" in
  "$script_dir"/.build-context) ;;
  *) echo "refusing unsafe build-context path: $build_context" >&2; exit 1 ;;
esac

rm -rf "$build_context"
mkdir -p \
  "$build_context/apps-repo/ai" \
  "$build_context/contracts-repo/packages"
rsync -a --exclude .git \
  "$workspace_root/apps-repo/ai/ceerat-agent-gateway" \
  "$build_context/apps-repo/ai/"
rsync -a --exclude .git \
  "$workspace_root/contracts-repo/packages/ceerat-contracts" \
  "$build_context/contracts-repo/packages/"

echo "Prepared minimal gateway build context at $build_context"
