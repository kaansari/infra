const base = process.argv[2];
if (!/^https:\/\/[^/]+$/.test(base || "")) throw new Error("expected an HTTPS gateway origin");

const call = async () => {
  const response = await fetch(`${base}/mcp`, {
    method: "POST",
    headers: {"content-type": "application/json"},
    body: JSON.stringify({jsonrpc: "2.0", id: 1, method: "tools/call", params: {name: "get_current_user", arguments: {}}}),
    signal: AbortSignal.timeout(30000)
  });
  if (!response.ok) throw new Error(`gateway returned HTTP ${response.status}`);
  return (await response.json()).result?.structuredContent;
};

for (let attempt = 1; attempt <= 10; attempt++) {
  const result = await call();
  if (result?.error?.code !== "UNAUTHENTICATED") throw new Error(`attempt ${attempt} did not return UNAUTHENTICATED; wait for the rate window to reset`);
}
const limited = await call();
if (limited?.error?.code !== "RATE_LIMITED") throw new Error("eleventh attempt did not return RATE_LIMITED");
if (!/^req_[a-f0-9]+$/.test(limited?.meta?.request_id || "")) throw new Error("rate-limited response has no safe request ID");
