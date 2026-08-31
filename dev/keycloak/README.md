# Local Keycloak for the CEERAT agent gateway

This configuration is development-only and does not modify Kubernetes.

```bash
export CEERAT_KEYCLOAK_ADMIN_PASSWORD='<local-only password>'
docker compose -f docker-compose.keycloak.yml up
```

The imported public client requires authorization code + PKCE, disables password
and service-account grants, enables explicit consent, and adds the MCP audience.
Replace the placeholder redirect URI with the exact test-client or temporary
ChatGPT callback before interoperability testing.

For each synthetic Keycloak user, set the `ceerat_user_id` user attribute to the
matching synthetic user ID in `ceerat-user-service`. Never use production users,
passwords, clients, or databases with this realm.

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
   client_id:     ceerat-mcp-dev
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
