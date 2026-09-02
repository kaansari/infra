# PR 05: Keycloak session-aware revocation

Repository: `apps-repo`

Depends on: PR 02, PR 03, and PR 04

## Objective

Make connection revocation and logout claims truthful. A locally revoked
connection must not be able to regain CEERAT access through its still-valid
authorization-server session.

## Design gate

Before implementation, prove which Keycloak identifier (`sid`, user session,
or client session) maps one CEERAT connection to one refresh-token family.
Store only the minimum opaque identifier needed for revocation. Do not store
access tokens, refresh tokens, authorization codes, or client passwords.

If Keycloak cannot revoke exactly one family/session with the available
identifier, narrow the public tool description instead of claiming stronger
revocation.

## Changes

- Capture the validated session identifier from the access token and associate
  it with the connection record.
- Add a small authorization-server revocation interface with timeouts and
  sanitized errors.
- Revoke locally first or transactionally record pending revocation so a
  dependency timeout cannot silently restore CEERAT access.
- Use a least-privilege confidential Keycloak service client whose secret is a
  Render secret; document required roles and rotation.
- Make repeated revoke/logout idempotent and represent uncertain upstream
  outcomes explicitly.

## Tests

- Logout: old access fails and refresh cannot mint usable CEERAT access.
- Revoke B among A/B/C: B fails while A and C continue.
- Repeated revocation succeeds without widening scope.
- Keycloak timeout, denial, and malformed response do not leak internals.
- A user cannot revoke a connection owned by another user.

## Non-goals

No global user logout, admin-facing session management, or account deletion.

## Acceptance

Tool descriptions, stored state, and observed Keycloak behavior agree. No test
may label token-family revocation PASS based only on the gateway denylist.
