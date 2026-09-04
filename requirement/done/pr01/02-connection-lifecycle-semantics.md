# PR 02: Connection lifecycle semantics

Repository: `apps-repo`

Depends on: PR 01

Status: **completed and live-validated on 2026-09-02** (`apps-repo` commit
`7049b95`).

## Objective

Stop presenting an expired access token as an expired authorization or as an
ordinary active connection. Make the current connection identifiable.

## Response design

Retain legacy `status` only if needed and `expires_at` for one compatibility window, but add
truthful fields:

```json
{
  "id": "...",
  "client_id": "ceerat-mcp-dev",
  "authorization_status": "active",
  "access_token_status": "expired",
  "is_current": false,
  "created_at": "...",
  "last_used_at": "...",
  "access_token_expires_at": "...",
  "scopes": []
}
```

`authorization_status` is `active` or `revoked`. `access_token_status` is
`valid` or `expired`. It must not claim that a refresh-token family is active
unless CEERAT has verified that state with the authorization server.

## Changes

- Add persisted `created_at` and `last_used_at` handling to both PostgreSQL and
  in-memory stores.
- Compute access-token state against an injected clock.
- Set `is_current` by matching the authenticated connection identifier; never
  accept it from tool arguments.
- Update a connection's `last_used_at` on authenticated use without creating a
  duplicate record.
- Document legacy-field deprecation rather than silently changing semantics.

## Tests

- Valid, expired, revoked, and revoked-plus-expired combinations.
- Exactly one listed connection is current for the calling token.
- Repeated/concurrent tracking is idempotent.
- PostgreSQL migration is additive and safe on an existing table.
- A user can list only their own connections.

## Non-goals

This PR does not revoke Keycloak sessions or claim refresh-token-family
revocation.

## Builder-agent and documentation gate

- Run the shared builder workflow plus `ceerat-builder evidence request
  "agent connection lifecycle current access token expiry revocation" --output
  json`.
- Validate that access-token state, authorization state, ownership, and current
  connection identity are derived server-side and never supplied by the model.
- Update the gateway README, tool response examples, database migration notes,
  and app-surface inventory in this PR.
- After live validation, update reusable connection-state terminology in the
  builder architecture, AI-tool standard, and public-AI security profile before
  PR 03.

## Acceptance

Expired access credentials are never returned as simply `active`, and the live
Codex connection is clearly marked `is_current:true`.

## Validation evidence

- Gateway unit tests, race detector, `go vet`, and build passed.
- The additive PostgreSQL migration deployed without preventing gateway
  readiness.
- Public MCP discovery and invalid-token OAuth challenges passed.
- A live Codex call returned exactly one `is_current:true` connection.
- Active/expired and revoked/expired records returned independent
  `authorization_status` and `access_token_status` values.
- The first post-deploy OAuth attempt timed out while the free Keycloak service
  was cold. After the realm and OIDC endpoints became responsive, the existing
  saved credential completed the authenticated call; no credential was deleted.
- Authorization-server session revocation remains intentionally deferred to PR
  05.
