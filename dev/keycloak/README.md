# Local Keycloak for the CEERAT agent gateway

This configuration is development-only and does not modify Kubernetes.

```bash
export CEERAT_KEYCLOAK_ADMIN_PASSWORD='<local-only password>'
docker compose -f docker-compose.keycloak.yml up
```

The realm separates hosted and native clients:

- `ceerat-mcp-chatgpt` accepts only
  `https://chatgpt.com/connector_platform_oauth_redirect`;
- `ceerat-mcp-codex-dev` accepts only dynamic `127.0.0.1` and `localhost`
  loopback callbacks required by the native CLI;
- `ceerat-mcp-dev` remains temporarily enabled as a rollback client and must
  not receive new integrations;
- `ceerat-gateway-revoker` is a confidential service-only client used by the
  gateway to delete one identified Keycloak user/offline session. It has only
  the `realm-management/manage-users` client role and cannot use browser or
  password OAuth flows.

Both clients require authorization code + PKCE `S256` and disable implicit,
password, and service-account grants. ChatGPT is confidential and its generated
secret must be stored only in ChatGPT's protected app configuration; Codex is
public and uses no client secret. `offline_access` is explicit and optional. Access
tokens last 10 minutes; refresh-token rotation is enabled with zero permitted
reuse. Offline sessions idle after 30 days and have a 60-day maximum. The realm
also declares the administrator-managed `ceerat_user_id` attribute so Keycloak
26 retains it for the token mapper.

Phase 1-B also defines Google federation and verified native email. Supply
`CEERAT_GOOGLE_CLIENT_ID`, `CEERAT_GOOGLE_CLIENT_SECRET`, and the
`CEERAT_SMTP_*` values before importing a new realm. Register this callback:

```text
https://<keycloak-host>/realms/ceerat/broker/google/endpoint
```

Existing realms are not changed by startup import. Use the idempotent live-realm
procedure in `deploy/render/README.md` rather than assuming a redeploy updated
PostgreSQL-backed realm state.

The Render pilot uses Brevo authenticated SMTP on
`smtp-relay.brevo.com:2525`, with STARTTLS enabled and implicit SSL disabled.
The SMTP key exists only in `CEERAT_SMTP_PASSWORD`; it is not an email-account
password and must not be committed.

Phase 1-B no longer requires manually setting `ceerat_user_id`; the gateway's
authenticated identity exchange creates or resolves the CEERAT account. Never
use production users, passwords, clients, or databases with this local realm.

The realm file intentionally does not contain users or reusable credentials.

## Start with the CEERAT stack

From `infra`:

```bash
make start-stack
./status.sh
```

`start-stack.sh` builds and starts the gateway on `127.0.0.1:8090`. If Docker
is available, it also starts the `ceerat-keycloak` container on port `8080`. If
no admin password is supplied, it generates one in
`../.run/keycloak-admin-password` with mode `0600`.

If a Colima user has a stale Docker Desktop `credsStore` setting and the
`docker-credential-desktop` helper is unavailable, the lifecycle scripts keep
the selected Docker daemon endpoint and use an isolated credential-free Docker
configuration for these public development images. Private registry settings
and credentials are never copied into that fallback configuration.

Useful endpoints:

```text
MCP:        http://localhost:8090/mcp
metadata:   http://localhost:8090/.well-known/oauth-protected-resource/mcp
Keycloak:   http://localhost:8080
realm:      http://localhost:8080/realms/ceerat
gateway log: ../logs/agent-gateway.log
```

## Human test

First verify the public MCP surface:

```bash
curl -sS http://localhost:8090/.well-known/oauth-protected-resource/mcp

curl -sS -X POST http://localhost:8090/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"human-test","version":"1"}}}'

curl -sS -X POST http://localhost:8090/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
```

A protected call without a token must return HTTP `401` and a
`WWW-Authenticate` header:

```bash
curl -i -X POST http://localhost:8090/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_current_user","arguments":{}}}'
```

For an authenticated test:

1. Create a synthetic CEERAT customer through the existing customer
   registration UI and record its CEERAT user ID.
2. Sign in to the local Keycloak admin console as `admin`. Create a synthetic
   Keycloak user, give it a password, and set its `ceerat_user_id` attribute to
   that CEERAT user ID. Never use a production customer.
3. Use an OAuth-capable MCP client or API client with authorization code + PKCE:

   ```text
   client_id:     ceerat-mcp-codex-dev
   authorize URL: http://localhost:8080/realms/ceerat/protocol/openid-connect/auth
   token URL:     http://localhost:8080/realms/ceerat/protocol/openid-connect/token
   MCP URL:       http://localhost:8090/mcp
   ```

4. After browser login and consent, call `get_current_user`,
   `get_my_customer_profile`, prepare/update a low-risk field, list connections,
   and finally call `logout_current_connection` with `confirmed: true`.
5. Confirm that another protected call with the same token returns
   `GRANT_REVOKED`. Inspect the sanitized audit trail with:

   ```bash
   ./logs.sh gateway
   ```

You can also paste a valid development access token into this direct test:

```bash
export CEERAT_TEST_ACCESS_TOKEN='<short-lived synthetic-user token>'
curl -sS -X POST http://localhost:8090/mcp \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${CEERAT_TEST_ACCESS_TOKEN}" \
  -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_my_customer_profile","arguments":{}}}'
unset CEERAT_TEST_ACCESS_TOKEN
```

Do not paste the token into chat, commit it, put it in `.env`, or retain it in
shell history on a shared machine.

## Phase 2 product/cart consent test

The local realm offers `ceerat.products.read`,
`ceerat.products.cart.read`, and `ceerat.products.cart.write` as optional
scopes only to the dedicated ChatGPT and Codex MCP clients. Start an
authorization-code + PKCE login that requests `openid` and the scopes being
tested. Confirm the consent screen separately describes catalog viewing, cart
viewing, and cart modification.

After exchange, inspect only decoded `scope` claim names: requested and granted
scopes must be present, omitted scopes absent, and `ceerat.products.admin`
rejected. Never print or persist the token. These scopes do not grant cart
ownership or authority over prices, inventory, checkout, or administration;
the owning gRPC service makes those decisions.
