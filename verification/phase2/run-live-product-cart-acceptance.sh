#!/usr/bin/env bash
set -uo pipefail

gateway_url="${CEERAT_GATEWAY_URL:-https://ceerat-agent-gateway.onrender.com}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workspace_root="$(cd "$repo_root/.." && pwd)"
output="${CEERAT_PHASE2_OUTPUT:-$repo_root/.verification/phase2-codex.json}"
tmp_dir="$(mktemp -d)"
results="$tmp_dir/results.tsv"
mkdir -p "$(dirname "$output")"
trap 'rm -rf "$tmp_dir"' EXIT

record() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$results"; }
run_check() {
  local id="$1" evidence="$2"
  shift 2
  if "$@" >"$tmp_dir/$id.out" 2>"$tmp_dir/$id.err"; then
    record "$id" PASS "$evidence"
  else
    record "$id" FAIL "$evidence"
  fi
}

run_check live_public_surface "health, readiness, TLS MCP discovery, exact 16-tool inventory, seven product-domain tools, OAuth scopes, annotations, strict schemas, and public denials" \
  node "$repo_root/verification/phase2/verify-public-surface.mjs" "$gateway_url"
run_check tls "public gateway certificate verifies and negotiates TLS 1.2 or newer" \
  curl --fail --silent --show-error --tlsv1.2 --max-time 30 "$gateway_url/healthz"
run_check gateway_cart_security "strict product/cart schemas, scopes, projection, confirmation binding, replay/expiry, stable errors, redaction, and correlated audit tests" \
  env GOWORK=off GOCACHE=/tmp/ceerat-phase2-go-cache go -C "$workspace_root/apps-repo/ai/ceerat-agent-gateway" test ./internal/gateway ./internal/platform -run 'Test(Product|Cart|Products)' -count=1
run_check service_cart_security "direct private gRPC JWT/RBAC/ownership and PostgreSQL-independent cart handler boundaries" \
  env GOWORK=off GOCACHE=/tmp/ceerat-phase2-go-cache go -C "$workspace_root/services-repo/services/ceerat-user-service" test ./services -run 'Test.*Cart' -count=1
run_check contract_boundary "generated self-cart RPCs, reserved owner selectors, and security maps remain consistent" \
  env GOCACHE=/tmp/ceerat-phase2-go-cache go -C "$workspace_root/contracts-repo/packages/ceerat-contracts" test ./proto/service ./security -count=1
run_check builder_boundaries "contract/service/RBAC drift and active MCP inventory match" \
  bash -c 'cd "$1" && ceerat-builder rbac check --output json && ceerat-builder check drift --output json && ceerat-builder check apps --output json' _ "$workspace_root/ceerat-platform-builder-agent"

if [[ -n "${CEERAT_TEST_DATABASE_URL:-}" ]]; then
  run_check postgres_cart "migration, rollback/reapply, ownership, pricing, idempotency, concurrency, and restart tests use a disposable PostgreSQL schema" \
    env GOWORK=off GOCACHE=/tmp/ceerat-phase2-go-cache CEERAT_TEST_DATABASE_URL="$CEERAT_TEST_DATABASE_URL" go -C "$workspace_root/services-repo/services/ceerat-user-service" test ./services -run 'TestSelfCartPostgres' -count=1
else
  record postgres_cart MANUAL_REQUIRED "set CEERAT_TEST_DATABASE_URL to a disposable PostgreSQL database; the test creates and removes an isolated schema"
fi

if [[ "${CEERAT_PHASE2_RUN_RATE_LIMIT:-false}" == "true" ]]; then
  run_check rate_limit_live "live authentication-failure rate limit exercised from one stable source without credentials" \
    node "$repo_root/verification/phase2/verify-live-rate-limit.mjs" "$gateway_url"
else
  record rate_limit_live MANUAL_REQUIRED "rerun with CEERAT_PHASE2_RUN_RATE_LIMIT=true after the current one-minute source bucket resets"
fi

record authenticated_codex MANUAL_REQUIRED "use disposable User A/B connections and complete the authenticated Codex matrix in verification/phase2/README.md"
record authenticated_chatgpt MANUAL_REQUIRED "complete the ChatGPT catalog/cart mutation and restoration matrix with explicit approvals"
record two_user_isolation_live MANUAL_REQUIRED "prove Users A and B receive distinct carts and cannot supply or consume the other's identifiers/preparations"
record audit_correlation_live MANUAL_REQUIRED "match sanitized MCP request IDs to gateway and private gRPC logs; inspect retention/access and secret/PII redaction"
record migration_deployment_live MANUAL_REQUIRED "record sanitized production preflight, exactly-once migration, constraints/indexes, restart, and disposable rollback-clone evidence"
record logout_regression_live MANUAL_REQUIRED "logout a disposable connection and prove subsequent product/cart access requires reconnection"

node - "$results" "$output" "$gateway_url" <<'NODE'
const fs = require("fs");
const [input, output, gateway] = process.argv.slice(2);
const checks = fs.readFileSync(input, "utf8").trim().split("\n").filter(Boolean).map(line => {
  const [id, status, evidence] = line.split("\t");
  return {id, status, evidence};
});
const counts = checks.reduce((out, check) => ((out[check.status] = (out[check.status] || 0) + 1), out), {});
const result = {
  schema_version: "1.0",
  suite: "ceerat_phase2_product_cart_live_acceptance",
  generated_at: new Date().toISOString(),
  target: new URL(gateway).origin,
  contains_credentials: false,
  overall_status: checks.some(c => c.status === "FAIL") ? "FAIL" : checks.some(c => c.status === "MANUAL_REQUIRED") ? "PARTIAL" : "PASS",
  counts,
  checks
};
fs.writeFileSync(output, JSON.stringify(result, null, 2) + "\n", {mode: 0o600});
process.stdout.write(JSON.stringify(result, null, 2) + "\n");
NODE

if grep -q $'\tFAIL\t' "$results"; then exit 1; fi
