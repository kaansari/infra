# Public ChatGPT Developer Mode deployment

This deployment exposes only the MCP gateway through Caddy HTTPS. The CEERAT
gRPC service and database remain private. Kubernetes is not used.

## Prerequisites

- A public DNS name whose A/AAAA record points to the deployment host.
- Ports 80 and 443 reachable so Caddy can obtain and renew TLS certificates.
- A private network route from the gateway to `ceerat-user-service`.
- A production OAuth/OIDC provider that supports authorization code + PKCE
  (`S256`), discovery, and either ChatGPT CIMD, DCR, or a predefined public
  client.
- The OAuth access-token audience must be the exact MCP resource URL.

Do not expose the gRPC service, PostgreSQL, Keycloak admin interface, or a
development-mode identity provider to the internet.

## OAuth configuration

Configure the provider with:

- resource/audience: `https://YOUR_MCP_DOMAIN/mcp`
- scopes: `openid profile email ceerat.profile.read ceerat.profile.write ceerat.connections.read ceerat.connections.revoke`
- PKCE method: `S256`
- ChatGPT stable redirect URI, when using a predefined client:
  `https://chatgpt.com/connector_platform_oauth_redirect`
- access-token claim `ceerat_user_id`, mapped to an existing CEERAT customer
- access-token client claim `azp` (or set `CEERAT_CLIENT_ID_CLAIM`)

For ChatGPT CIMD or DCR, configure the provider according to its supported MCP
client-registration mechanism. Do not enable password or client-credentials
grants for end-user ChatGPT access.

## Deploy

```bash
cd infra/deploy/chatgpt
cp public.env.example public.env
# edit public.env with real public values
./prepare-build-context.sh
docker compose --env-file public.env up -d --build
./smoke-test.sh https://YOUR_MCP_DOMAIN
```

The gateway refuses to start in production if the resource or issuer uses HTTP
or loopback, if the MCP path is not `/mcp`, or if the audience differs from the
resource URL.

## Connect ChatGPT

Enable Developer Mode in ChatGPT, add a plugin connection, and enter
`https://YOUR_MCP_DOMAIN/mcp`. Confirm the tool catalog, then invoke
`get_current_user` to trigger OAuth linking. The public `describe_ceerat` tool
does not require linking.

`tools/list` can also be checked directly:

```bash
curl -sS -X POST https://YOUR_MCP_DOMAIN/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```
