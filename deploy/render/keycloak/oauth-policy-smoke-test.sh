#!/usr/bin/env bash
set -euo pipefail

issuer="${CEERAT_OAUTH_ISSUER:-https://ceerat-keycloak.onrender.com/realms/ceerat}"
auth="$issuer/protocol/openid-connect/auth"
token="$issuer/protocol/openid-connect/token"
chatgpt_callback="https%3A%2F%2Fchatgpt.com%2Fconnector_platform_oauth_redirect"
codex_callback="http%3A%2F%2F127.0.0.1%3A54321%2Fcallback%2Fceerat-test"
invalid_callback="https%3A%2F%2Fattacker.invalid%2Fcallback"
challenge="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

request_auth() {
  local name="$1" client="$2" redirect="$3" response_type="$4" pkce="$5"
  local url="$auth?client_id=$client&response_type=$response_type&scope=openid&redirect_uri=$redirect&state=test-state"
  if [[ -n "$pkce" ]]; then
    url="$url&code_challenge=$challenge&code_challenge_method=$pkce"
  fi
  curl -sS --max-time 20 -D "$tmp_dir/$name.headers" -o "$tmp_dir/$name.body" "$url"
  if grep -Eqi 'client[[:space:]]+not[[:space:]]+found|unknown[[:space:]]+client' "$tmp_dir/$name.body" "$tmp_dir/$name.headers"; then
    echo "$client is not provisioned in the live realm; run make reconcile-keycloak-live" >&2
    exit 1
  fi
}

request_auth chatgpt-valid ceerat-mcp-chatgpt "$chatgpt_callback" code S256
if grep -Eqi 'invalid_redirect_uri|unsupported_response_type|code_challenge_method' "$tmp_dir/chatgpt-valid.body" "$tmp_dir/chatgpt-valid.headers"; then
  echo "valid ChatGPT authorization request failed" >&2
  exit 1
fi

request_auth codex-valid ceerat-mcp-codex-dev "$codex_callback" code S256
if grep -Eqi 'invalid_redirect_uri|unsupported_response_type|code_challenge_method' "$tmp_dir/codex-valid.body" "$tmp_dir/codex-valid.headers"; then
  echo "valid Codex loopback authorization request failed" >&2
  exit 1
fi

request_auth codex-hosted-redirect ceerat-mcp-codex-dev "$chatgpt_callback" code S256
if ! grep -Eqi 'invalid.*redirect|redirect.*invalid' "$tmp_dir/codex-hosted-redirect.body" "$tmp_dir/codex-hosted-redirect.headers"; then
  echo "Codex client accepted the hosted ChatGPT redirect" >&2
  exit 1
fi

request_auth chatgpt-bad-redirect ceerat-mcp-chatgpt "$invalid_callback" code S256
if ! grep -Eqi 'invalid.*redirect|redirect.*invalid' "$tmp_dir/chatgpt-bad-redirect.body" "$tmp_dir/chatgpt-bad-redirect.headers"; then
  echo "unregistered ChatGPT redirect was not rejected" >&2
  exit 1
fi

request_auth chatgpt-plain ceerat-mcp-chatgpt "$chatgpt_callback" code plain
if ! grep -Eqi 'code_challenge_method|pkce|invalid.request' "$tmp_dir/chatgpt-plain.body" "$tmp_dir/chatgpt-plain.headers"; then
  echo "plain PKCE was not rejected" >&2
  exit 1
fi

request_auth chatgpt-no-pkce ceerat-mcp-chatgpt "$chatgpt_callback" code ""
if ! grep -Eqi 'code_challenge|pkce|invalid.request' "$tmp_dir/chatgpt-no-pkce.body" "$tmp_dir/chatgpt-no-pkce.headers"; then
  echo "missing PKCE was not rejected" >&2
  exit 1
fi

request_auth chatgpt-implicit ceerat-mcp-chatgpt "$chatgpt_callback" token S256
if ! grep -Eqi 'unsupported_response_type|implicit|invalid.request' "$tmp_dir/chatgpt-implicit.body" "$tmp_dir/chatgpt-implicit.headers"; then
  echo "implicit flow was not rejected" >&2
  exit 1
fi

password_response="$(curl -sS --max-time 20 -X POST "$token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'grant_type=password&client_id=ceerat-mcp-chatgpt&username=invalid&password=invalid')"
if ! grep -Eqi 'unauthorized_client|not.allowed|invalid_client' <<<"$password_response"; then
  echo "password grant was not rejected" >&2
  exit 1
fi

revoker_response="$(curl -sS --max-time 20 -X POST "$token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data 'grant_type=client_credentials&client_id=ceerat-gateway-revoker&client_secret=invalid')"
if ! grep -Eqi 'invalid_client|unauthorized_client' <<<"$revoker_response"; then
  echo "revoker client accepted invalid client credentials" >&2
  exit 1
fi

echo "OAuth policy smoke test passed"
