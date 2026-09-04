#!/usr/bin/env bash
set -uo pipefail

gateway_url="${CEERAT_GATEWAY_URL:-https://ceerat-agent-gateway.onrender.com}"
issuer="${CEERAT_OAUTH_ISSUER:-https://ceerat-keycloak.onrender.com/realms/ceerat}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workspace_root="$(cd "$repo_root/.." && pwd)"
output="${CEERAT_PR08_OUTPUT:-$repo_root/.verification/pr08-codex.json}"
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

run_check public_mcp "health, readiness, discovery, OAuth challenge, and tool metadata" \
  "$repo_root/deploy/chatgpt/smoke-test.sh" "$gateway_url"
run_check oauth_policy "exact redirects, S256 PKCE, disabled implicit/password grants, invalid revoker secret" \
  env CEERAT_OAUTH_ISSUER="$issuer" "$repo_root/deploy/render/keycloak/oauth-policy-smoke-test.sh"
run_check tls "public gateway negotiates TLS 1.2 or newer with certificate verification" \
  curl --fail --silent --show-error --tlsv1.2 --max-time 30 "$gateway_url/healthz"
run_check jwt_dimensions "JWT signature, issuer, audience, time, client allowlist, and identity tests" \
  env GOWORK=off GOCACHE=/tmp/ceerat-pr08-go-cache go -C "$workspace_root/apps-repo/ai/ceerat-agent-gateway" test ./internal/auth -count=1
run_check scope_matrix "every protected MCP tool rejects its missing scope before handler work" \
  env GOWORK=off GOCACHE=/tmp/ceerat-pr08-go-cache go -C "$workspace_root/apps-repo/ai/ceerat-agent-gateway" test ./internal/gateway -run 'TestProtectedToolsEnforceScopeBeforeHandlerWork|TestAuthenticationOnlyToolsAdvertiseNoAdditionalScope' -count=1
run_check ownership_static "foreign connection and preparation ownership boundaries" \
  env GOWORK=off GOCACHE=/tmp/ceerat-pr08-go-cache go -C "$workspace_root/apps-repo/ai/ceerat-agent-gateway" test ./internal/gateway -run 'TestCannotRevokeAnotherUsersConnection|TestPreparationIsSingleUseAndIdentityBound|TestProfileConfirmationIsBoundToUserAndClient' -count=1
run_check profile_write_static "expiry, replay, content binding, conflict, and uncertain outcome" \
  env GOWORK=off GOCACHE=/tmp/ceerat-pr08-go-cache go -C "$workspace_root/apps-repo/ai/ceerat-agent-gateway" test ./internal/gateway -run 'TestPreparationExpiresUsingInjectedClock|TestPreparationContentCannotBeSubstituted|TestProfileConfirmationRejectsReplay|TestProfileConfirmationRejectsVersionConflict|TestProfileUpdateFailureReportsUnknownOutcome' -count=1
run_check revocation_static "local block, authorization-server invocation, owner isolation, and uncertain outcome" \
  env GOWORK=off GOCACHE=/tmp/ceerat-pr08-go-cache go -C "$workspace_root/apps-repo/ai/ceerat-agent-gateway" test ./internal/gateway -run 'TestLogoutRevokesCurrentConnection|TestLogoutBlocksLocallyWhenAuthorizationServerIsUnavailable|TestCannotRevokeAnotherUsersConnection' -count=1
run_check identity_static "gateway authentication, verified-email, and provisioning contract tests" \
  env GOWORK=off GOCACHE=/tmp/ceerat-pr08-go-cache go -C "$workspace_root/services-repo/services/ceerat-user-service" test ./user -run TestExchangeExternalIdentityRequiresGatewayAndProvisions -count=1
run_check rate_audit_static "independent/reset/concurrent limits plus audit fields and credential redaction" \
  env GOWORK=off GOCACHE=/tmp/ceerat-pr08-go-cache go -C "$workspace_root/apps-repo/ai/ceerat-agent-gateway" test ./internal/gateway -run 'TestRateLimiter|TestConcurrentRequestsCannotBypassLimit|TestRateLimitedEnvelopeIsActionable|TestAuthenticationFailuresUseTighterSourceBucket|TestAuditEventHasRequiredFieldsAndNoCredentials|TestCentralLogRedaction' -count=1

if [[ "${CEERAT_PR08_RUN_RATE_LIMIT:-false}" == "true" ]]; then
  rate_dir="$tmp_dir/rate"
  mkdir -p "$rate_dir"
  for attempt in 1 2 3 4 5 6 7 8 9 10 11; do
    curl --fail --silent --show-error --max-time 30 -X POST "$gateway_url/mcp" \
      -H 'Content-Type: application/json' \
      --data '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_current_user","arguments":{}}}' \
      >"$rate_dir/$attempt.json" || true
  done
  if rate_evidence="$(node - "$rate_dir" <<'NODE'
const fs = require("fs");
const dir = process.argv[2];
const response = n => JSON.parse(fs.readFileSync(`${dir}/${n}.json`, "utf8")).result?.structuredContent;
const code = n => response(n)?.error?.code;
for (let n = 1; n <= 10; n++) if (code(n) !== "UNAUTHENTICATED") process.exit(1);
if (code(11) !== "RATE_LIMITED") process.exit(1);
const requestID = response(11)?.meta?.request_id;
if (!/^req_[a-f0-9]+$/.test(requestID || "")) process.exit(1);
process.stdout.write(`request_id=${requestID}`);
NODE
  )"; then
    record rate_limit_live PASS "ten unauthenticated attempts allowed; eleventh denied without invoking a tool; $rate_evidence"
  else
    record rate_limit_live FAIL "live source-IP authentication-failure limit did not match the fixed policy"
  fi
else
  record rate_limit_live MANUAL_REQUIRED "rerun with CEERAT_PR08_RUN_RATE_LIMIT=true from one stable source IP"
fi

record authenticated_codex MANUAL_REQUIRED "reconnect CEERAT in Codex; verify auth status, current user, profile, and connections"
record two_user_isolation_live MANUAL_REQUIRED "requires disposable verified User A and User B OAuth connections"
record connection_abc_live MANUAL_REQUIRED "requires three disposable OAuth connections and refresh checks"
record logout_refresh_live MANUAL_REQUIRED "requires disposable connection; revoke then prove refresh cannot restore access"
record email_provisioning_live MANUAL_REQUIRED "requires disposable unverified then verified identity and datastore count evidence"
record profile_write_live MANUAL_REQUIRED "requires disposable profile and explicit confirmation in Codex and ChatGPT"
record audit_log_live MANUAL_REQUIRED "match the live RATE_LIMITED request_id in Render logs and inspect the redacted record"
record chatgpt_acceptance MANUAL_REQUIRED "run the interactive checklist in ChatGPT using disposable users"

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
  suite: "ceerat_phase1_live_security_acceptance",
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
