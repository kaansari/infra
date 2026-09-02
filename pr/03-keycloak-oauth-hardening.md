# PR 03: Keycloak OAuth and OIDC hardening

Repository: `infra`

Depends on: PR 01

Status: **implemented in source; live realm reconciliation and two-client smoke
tests pending**.

## Objective

Make the live realm configuration auditable and separate hosted ChatGPT OAuth
from local Codex development callbacks.

## Changes

- Create separate public clients:
  - `ceerat-mcp-chatgpt`: exact hosted ChatGPT callback only.
  - `ceerat-mcp-codex-dev`: loopback callbacks only, development use only.
- Require Authorization Code flow and PKCE `S256`; disable implicit and direct
  password grants.
- Do not allow arbitrary web origins or public HTTPS redirect wildcards.
- Treat a dynamic loopback port as the only documented exception needed by a
  native CLI. Limit it to `127.0.0.1`/`localhost`, a public client, and PKCE
  S256; never place that redirect on the ChatGPT client.
- Keep `email`, `profile`, CEERAT scopes, audience, and `offline_access`
  assignments explicit.
- Enforce verified email for protected CEERAT provisioning.
- Configure refresh-token rotation/reuse policy and short access-token lifetime
  with documented values.
- Provision a disabled-by-default `ceerat-gateway-revoker` confidential service
  client for PR 05. Grant only the minimum role proven necessary to revoke one
  mapped user/client session. Keep its generated secret in Render with
  `sync:false`; never place it in the realm export or Git.
- Provide an idempotent live-realm reconciliation procedure. Startup import is
  not considered sufficient because existing realms are stored in PostgreSQL.
- Replace stale InMotion/Gmail SMTP documentation with the current Brevo
  STARTTLS configuration while keeping the SMTP key in Render only.

## Tests

- ChatGPT callback succeeds and an unregistered HTTPS callback fails.
- Codex loopback login succeeds with PKCE S256.
- `plain`/missing PKCE, implicit flow, and password grant fail.
- Unverified email cannot complete protected provisioning; verified email can.
- Refresh rotation behavior is captured with redacted evidence.
- The revoker client cannot list or mutate unrelated realm configuration and is
  not usable through public OAuth flows.

## Non-goals

No Google social login and no gateway revocation implementation in this PR.

## Builder-agent and documentation gate

- Run the shared builder workflow plus `ceerat-builder evidence request
  "public MCP OAuth PKCE redirects refresh rotation verified email Keycloak"
  --output json`.
- Validate external OAuth termination, public-client boundaries, exact hosted
  redirects, the restricted native-loopback exception, secret storage, and
  least-privilege revoker-client design against the public-AI security profile.
- Update the Keycloak README, Render runbook, realm reconciliation procedure,
  Phase 1-B deployment documentation, and configuration examples in this PR.
- After both clients pass live validation, update the reusable OAuth rules in
  the builder architecture and security standards before PR 04.

## Rollback

Keep the existing client enabled until both new clients pass smoke tests. Move
one consumer at a time, then disable—not delete—the legacy client for a defined
rollback window.
