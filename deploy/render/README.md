# Render native Go deployment

This deployment builds and runs the Go binaries directly on Render. No Docker
image or Kubernetes cluster is involved.

## What is deployed

| Render resource | Source repository | Visibility | Purpose |
| --- | --- | --- | --- |
| `ceerat-agent-gateway` | `apps-repo` | Public HTTPS | MCP endpoint used by ChatGPT and other MCP clients |
| `ceerat-user-service` | `services-repo` | Render private network | Private gRPC authentication and user-management service |
| `ceerat-postgres` | Render Postgres | Render private network | Phase 1 CEERAT and Keycloak data |
| `ceerat-keycloak` | `infra` | Public HTTPS | OAuth/OIDC authorization server |

For the cost-conscious Phase 1 deployment, Keycloak and the user service share
one Render PostgreSQL database and the `public` schema. This means they share
credentials, capacity, backups and failure scope, and generic table names can
collide: Keycloak's `user_role_mapping` was observed during the Phase 1 test.

Phase 1-B generates `CEERAT_GATEWAY_WORKLOAD_SECRET` on the private user service
and references that exact value from the gateway. Do not generate independent
values. Google, SMTP, and `CEERAT_KEYCLOAK_REVOKER_CLIENT_SECRET` use
`sync: false`; set them manually on existing services because Render only
prompts for these values during initial Blueprint creation. The revoker secret
belongs to the disabled PR 05 placeholder and must not appear in realm JSON or
documentation.
Use separate schemas and database users, or separate databases, before a
production launch.

Both Go services carry a checked-in `vendor/` directory. Render therefore does
not need access to the separate private contracts repository during a build.

## First deployment

1. Push the changes in `apps-repo`, `services-repo`, and `infra` to their
   respective `main` branches.
2. In Render, choose **New > Blueprint** and connect the `infra` repository.
3. Select `render.yaml` as the Blueprint path if Render does not detect it
   automatically.
4. Confirm that Render can allocate the exact public service names
   `ceerat-agent-gateway` and `ceerat-keycloak`, then create the Blueprint.
   Their generated URLs, OAuth issuer, JWKS endpoint, and token audience are
   already aligned in `render.yaml` and the imported realm.
5. If Render changes either hostname because the requested name is unavailable,
   update `KC_HOSTNAME`, the three `CEERAT_*` gateway URLs, and the realm's MCP
   audience before interoperability testing.

The gateway derives `CEERAT_OAUTH_AUDIENCE` from `CEERAT_MCP_RESOURCE` and
`CEERAT_AUTHORIZATION_SERVER` from `CEERAT_OAUTH_ISSUER`, preventing common
audience/issuer mismatches.

Choose the Render instance and database plans in the dashboard. For a public
ChatGPT test, use plans that remain awake; sleeping services make MCP discovery
and tool calls appear unreliable.

The checked-in Phase 1 defaults minimize development cost: free web instances
for Keycloak and the gateway, the smallest paid private instance for the gRPC
user service, and free PostgreSQL. Free web instances sleep after 15 minutes and
can take about a minute to wake; warm both public URLs before a ChatGPT test.
Free PostgreSQL is limited to 1 GB and expires after 30 days, so upgrade it or
replace it before retaining real users or treating the deployment as durable.

## Fast refresh on push

The Blueprint uses `autoDeployTrigger: commit` for both services:

- pushing `apps-repo/main` rebuilds and redeploys only the gateway;
- pushing `services-repo/main` rebuilds and redeploys only the user service;
- pushing `infra/main` updates Blueprint-managed configuration.

An `infra/main` push also rebuilds Keycloak because its optimized image and
realm import are defined in this repository.

The native build command is deliberately small:

```sh
go build -mod=vendor -trimpath -o bin/<service> .
```

Do not add `go mod download` to Render. Dependencies are vendored, so doing so
would add network latency without improving the build.

Whenever contracts or Go dependencies change, refresh and commit the vendor
directory in each affected module:

```sh
cd apps-repo/ai/ceerat-agent-gateway
GOWORK=off go mod tidy
GOWORK=off go mod vendor

cd services-repo/services/ceerat-user-service
GOWORK=off go mod tidy
GOWORK=off go mod vendor
```

## Human smoke test

Set the deployed gateway URL, then verify discovery:

```sh
export CEERAT_GATEWAY_URL=https://ceerat-agent-gateway.onrender.com

curl -fsS "$CEERAT_GATEWAY_URL/healthz"

curl -fsS "$CEERAT_GATEWAY_URL/.well-known/oauth-protected-resource/mcp"

curl -fsS https://ceerat-keycloak.onrender.com/realms/ceerat/.well-known/openid-configuration

curl -fsS -X POST "$CEERAT_GATEWAY_URL/mcp" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"human-smoke-test","version":"1.0"}}}'

curl -fsS -X POST "$CEERAT_GATEWAY_URL/mcp" \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
```

Then add the public MCP URL to the ChatGPT developer/test integration. Check:

1. ChatGPT can discover the server and list the Phase 1 tools.
2. ChatGPT follows the OAuth challenge and connects an existing CEERAT account.
3. `get_authentication_status` and `get_current_user` return the connected
   identity without accepting credentials as tool arguments.
4. An authenticated customer-profile read succeeds.
5. The prepare/confirm profile-update sequence succeeds.
6. Connection listing and explicit revocation behave as described by the tool
   contracts.
7. Expected failures (missing scope, validation failure, expired/invalid token,
   stale resource version) return structured, actionable errors rather than an
   HTML page or an opaque HTTP 500.

The 2026-08-31 milestone passed these checks from both Codex and ChatGPT. See
`docs/public-agent-phase-1-milestone.md` for evidence, OAuth corrections and
remaining production gates.

Never paste a production password or token into deployment logs or a shared
ChatGPT conversation. Use a disposable test account for the first public test.

## Reconcile the existing Keycloak realm

Keycloak `--import-realm` creates a missing realm but does not overwrite the
existing realm stored in PostgreSQL. After deploying PR 03, run the checked-in
reconciler from an administrative workstation or Render shell that has
Keycloak's `kcadm.sh` available:

```bash
export CEERAT_KEYCLOAK_ADMIN_USERNAME=admin
export CEERAT_KEYCLOAK_ADMIN_PASSWORD='<read from the Render secret>'
export CEERAT_KEYCLOAK_REVOKER_CLIENT_SECRET='<random Render-only secret>'
export KCADM=/opt/keycloak/bin/kcadm.sh

./deploy/render/keycloak/reconcile-live-realm.sh
```

For a local container, copy or mount the reconciliation directory and set
`CEERAT_KEYCLOAK_SERVER=http://127.0.0.1:8080`. The script is idempotent: it
creates or updates the three PR 03 clients and reapplies bounded lifetimes and
verified-email policy. It deliberately leaves `ceerat-mcp-dev` enabled for
rollback.

The revoker client is disabled and receives no realm-management role in PR 03.
PR 05 must first prove whether Keycloak can revoke exactly one mapped client
session and which minimum role/API permits it. Do not grant broad
`realm-admin`, `manage-realm`, or user-listing access as a shortcut.

After reconciliation, configure ChatGPT with client ID
`ceerat-mcp-chatgpt` and token endpoint authentication method `none`. Configure
Codex with `ceerat-mcp-codex-dev`. Move one client at a time. After both smoke
tests pass, disable—but do not delete—`ceerat-mcp-dev` for the rollback window.

Run the static policy tests before deployment:

```bash
ruby deploy/render/keycloak/realm_config_test.rb
bash -n deploy/render/keycloak/reconcile-live-realm.sh
bash -n deploy/render/keycloak/oauth-policy-smoke-test.sh
```

After live reconciliation, run
`deploy/render/keycloak/oauth-policy-smoke-test.sh`. It uses no credentials and
verifies exact ChatGPT redirects plus rejection of bad redirects, missing/plain
PKCE, implicit flow, password grant, and the disabled revoker client.
