# Local observability acceptance

Capture JSON logs from a locally built MCP gateway and gRPC user service.
Use synthetic fixture users and request IDs. Keep raw tokens, personal data,
headers, bodies, and database details out of saved artifacts.

The gateway forwards one validated `x-request-id` and `traceparent` with its
original bearer credential. Direct gRPC creates missing or invalid correlation
metadata at the service edge. Service `grpc.request` events are authoritative
for OAuth, identity, scope, RBAC, ownership, and handler outcomes. Gateway
`agent_gateway.tool_call` events describe its own earlier decision.

Run the checker on a combined JSONL file before push:

```sh
python3 verification/oauth-grpc/verify-observability-evidence.py /tmp/ceerat-pr06-local-evidence.jsonl
```

`sample-observability-evidence.jsonl` shows only the expected shape. It is a
synthetic example and does not count as local runtime acceptance. Search an
incident by `request_id`, then confirm `trace_id` and inspect both events.
An MCP success without a matching `grpc.request` means the downstream decision
has not been established.
