import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

const base = process.argv[2];
if (!/^https:\/\/[^/]+$/.test(base || "")) throw new Error("expected an HTTPS gateway origin");
const expected = [
  "describe_ceerat", "get_authentication_status", "get_current_user", "get_my_customer_profile",
  "prepare_my_customer_profile_update", "update_my_customer_profile", "list_my_agent_connections",
  "revoke_my_agent_connection", "logout_current_connection", "products_list", "products_get",
  "products_cart_get", "products_cart_add_item", "products_cart_update_item",
  "products_cart_remove_item", "products_cart_clear"
];
const productTools = expected.filter(name => name.startsWith("products_"));
const productScopes = ["ceerat.products.read", "ceerat.products.cart.read", "ceerat.products.cart.write"];
const temporary = await fs.mkdtemp(path.join(os.tmpdir(), "ceerat-phase2-public-"));
const request = async (pathname, options = {}) => {
  const response = await fetch(base + pathname, {signal: AbortSignal.timeout(30000), ...options});
  if (!response.ok) throw new Error(`${pathname} returned HTTP ${response.status}`);
  return response.json();
};
try {
  const health = await request("/healthz");
  const ready = await request("/readyz");
  if (health.status !== "ok" || ready.status !== "ready") throw new Error("gateway is not healthy and ready");
  const resource = await request("/.well-known/oauth-protected-resource/mcp");
  if (resource.resource !== `${base}/mcp`) throw new Error("protected resource mismatch");
  for (const scope of productScopes) if (!resource.scopes_supported?.includes(scope)) throw new Error(`missing protected-resource scope ${scope}`);
  const rpc = (id, method, params) => request("/mcp", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({jsonrpc: "2.0", id, method, params})});
  const initialized = await rpc(1, "initialize", {protocolVersion: "2025-06-18", capabilities: {}, clientInfo: {name: "ceerat-phase2-acceptance", version: "1"}});
  if (!initialized.result?.protocolVersion) throw new Error("initialize failed");
  const listed = await rpc(2, "tools/list", {});
  const tools = listed.result?.tools;
  if (!Array.isArray(tools) || tools.map(t => t.name).join("|") !== expected.join("|")) throw new Error("active tool inventory differs from the exact Phase 2 set");
  for (const name of productTools) {
    const tool = tools.find(candidate => candidate.name === name);
    if (tool.domain !== "products" || tool._meta?.["ceerat/domain"] !== "products") throw new Error(`${name} is not grouped in products`);
    if (tool.inputSchema?.additionalProperties !== false) throw new Error(`${name} input schema is open`);
    const scopes = tool.securitySchemes?.[0]?.scopes || [];
    const wanted = name === "products_cart_get" ? "ceerat.products.cart.read" : name.startsWith("products_cart_") ? "ceerat.products.cart.write" : "ceerat.products.read";
    if (!scopes.includes(wanted)) throw new Error(`${name} missing ${wanted}`);
  }
  const describe = await rpc(3, "tools/call", {name: "describe_ceerat", arguments: {}});
  const group = describe.result?.structuredContent?.data?.capability_groups?.find(group => group.domain === "products");
  if (group?.tools?.join("|") !== productTools.join("|")) throw new Error("describe_ceerat product group mismatch");
  const auth = await rpc(4, "tools/call", {name: "products_cart_get", arguments: {}});
  if (auth.result?.structuredContent?.error?.code !== "UNAUTHENTICATED" || !auth.result?._meta?.["mcp/www_authenticate"]) throw new Error("cart authentication challenge missing");
  const invalid = await rpc(5, "tools/call", {name: "products_cart_add_item", arguments: {customer_id: "forbidden", product_id: "p", quantity: 1, idempotency_key: "k", expected_cart_version: 1}});
  if (invalid.result?.structuredContent?.error?.code !== "INVALID_ARGUMENT") throw new Error("identity selector was not rejected before authentication");
  const pagination = await rpc(6, "tools/call", {name: "products_list", arguments: {page_size: 51}});
  if (pagination.result?.structuredContent?.error?.code !== "INVALID_ARGUMENT") throw new Error("oversized page was not rejected before authentication");
  await fs.writeFile(path.join(temporary, "passed"), "redacted\n", {mode: 0o600});
} finally {
  await fs.rm(temporary, {recursive: true, force: true});
}
