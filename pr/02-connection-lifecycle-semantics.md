# PR 02: Connection lifecycle semantics

Repository: `apps-repo`

Depends on: PR 01

## Objective

Stop presenting an expired access token as an expired authorization or as an
ordinary active connection. Make the current connection identifiable.

## Response design

Retain legacy `status` and `expires_at` for one compatibility window, but add
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

## Acceptance

Expired access credentials are never returned as simply `active`, and the live
Codex connection is clearly marked `is_current:true`.
