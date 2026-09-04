#!/usr/bin/env bash
set -euo pipefail

base_url="${1:-}"
if [[ ! "$base_url" =~ ^https://[^/]+$ ]]; then
  echo "usage: $0 https://your-public-mcp-host" >&2
  exit 2
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

curl -fsS "$base_url/healthz" >"$tmp_dir/health.json"
curl -fsS "$base_url/readyz" >"$tmp_dir/ready.json"
curl -fsS "$base_url/.well-known/oauth-protected-resource/mcp" >"$tmp_dir/resource.json"
curl -fsS -X POST "$base_url/mcp" -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"chatgpt-public-smoke-test","version":"1"}}}' >"$tmp_dir/initialize.json"
curl -fsS -X POST "$base_url/mcp" -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' >"$tmp_dir/tools.json"
curl -fsS -X POST "$base_url/mcp" -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_my_customer_profile","arguments":{}}}' >"$tmp_dir/auth.json"

node - "$base_url" "$tmp_dir" <<'NODE'
const fs = require("fs");
const [base, dir] = process.argv.slice(2);
const read = name => JSON.parse(fs.readFileSync(`${dir}/${name}.json`, "utf8"));
const health = read("health");
const ready = read("ready");
const resource = read("resource");
const initialize = read("initialize");
const tools = read("tools");
const auth = read("auth");
const fail = message => { throw new Error(message); };
health.status === "ok" || fail("health check failed");
ready.status === "ready" || fail("readiness check failed");
resource.resource === `${base}/mcp` || fail("protected resource URL mismatch");
resource.authorization_servers?.every(v => v.startsWith("https://")) || fail("authorization server is not HTTPS");
initialize.result?.protocolVersion || fail("MCP initialize failed");
const catalog = tools.result?.tools;
Array.isArray(catalog) && catalog.length > 0 || fail("empty tool catalog");
catalog.every(t => Array.isArray(t.securitySchemes) && t.securitySchemes.length > 0) || fail("tool securitySchemes missing");
auth.result?._meta?.["mcp/www_authenticate"] || fail("ChatGPT OAuth trigger metadata missing");
console.log(`PASS: ${catalog.length} tools discovered; public metadata and OAuth trigger are ChatGPT-ready`);
NODE
