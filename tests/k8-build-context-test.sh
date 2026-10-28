#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
modules=(
  apps-repo/ai/ceerat-agent-service
  apps-repo/ai/ceerat-agent-gateway
  apps-repo/apps/ceerat-web-ui
  apps-repo/apps/ceerat-admin-ui
  apps-repo/apps/ceerat-customer-ui
  services-repo/services/ceerat-user-service
  contracts-repo/packages/ceerat-contracts
)
for module in "${modules[@]}"; do
  mkdir -p "$test_dir/workspace/$module"
  printf 'module example.com/%s\n\ngo 1.26.2\n' "$module" > "$test_dir/workspace/$module/go.mod"
done
printf 'go 1.26.2\nuse (\n ./originalquran\n ./atscrawler\n)\n' > "$test_dir/workspace/go.work"
touch "$test_dir/workspace/go.work.sum"
make -s -C "$ROOT_DIR" k8-context STACK_ROOT="$test_dir/workspace" K8S_CONTEXT_DIR="$test_dir/context"
if rg -q 'originalquran|atscrawler' "$test_dir/context/go.work"; then
  echo 'FAIL: unrelated host modules leaked into Kubernetes build workspace' >&2
  exit 1
fi
if ! rg -q '^go 1\.26\.2$' "$test_dir/context/go.work"; then
  echo 'FAIL: generated workspace must use the contracts Go version, not the host Go version' >&2
  exit 1
fi
for module in "${modules[@]}"; do
  test -f "$test_dir/context/$module/go.mod"
  (cd "$test_dir/context/$module" && GOWORK="$test_dir/context/go.work" go list -m >/dev/null)
done
echo 'PASS: Kubernetes build workspace resolves all seven CEERAT modules without unrelated host modules'
