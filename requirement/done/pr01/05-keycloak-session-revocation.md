# PR 05: Keycloak session-aware revocation

Repository: `apps-repo`

Depends on: PR 02, PR 03, and PR 04

Status: **implemented, deployed, and live-validated for current-connection
logout**.

## Objective

Make connection revocation and logout claims truthful. A locally revoked
connection must not be able to regain CEERAT access through its still-valid
authorization-server session.

## Design gate

Before implementation, prove which Keycloak identifier (`sid`, user session,
or client session) maps one CEERAT connection to one refresh-token family.
Store only the minimum opaque identifier needed for revocation. Do not store
access tokens, refresh tokens, authorization codes, or client passwords.

Keycloak's supported admin API deletes the user/offline session identified by
`sid`; it does not expose a supported operation to delete only one child client
session. Tool descriptions therefore disclose that another CEERAT client
sharing the same browser SSO session may also be signed out.

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
- Use `sid + client_id` as the stable local connection key across access-token
  refreshes while storing `sid` separately for the Keycloak operation.
- Select normal or offline-session deletion from the validated
  `offline_access` scope.

## Tests

- Logout: old access fails and refresh cannot mint usable CEERAT access.
- Revoke B among A/B/C: B fails while A and C continue when they have distinct
  Keycloak `sid` values. Clients sharing B's SSO session are truthfully within
  the documented logout blast radius.
- Repeated revocation succeeds without widening scope.
- Keycloak timeout, denial, and malformed response do not leak internals.
- A user cannot revoke a connection owned by another user.

## Non-goals

No realm-wide/user-wide logout, admin-facing session management, account
deletion, or unsupported Keycloak internal client-session API.

## Builder-agent and documentation gate

- Run the shared workflow plus `ceerat-builder evidence request "Keycloak
  session connection refresh family revoke logout" --output json`.
- Validate the session identifier boundary, least-privilege service identity,
  private credential handling, ownership checks, failure ordering, and truthful
  public guarantees against the public-AI security profile.
- Update gateway architecture, connection-tool documentation, Render deployment
  variables, and the revocation operator runbook in this PR.
- After the A/B/C live revocation test passes, update reusable session and
  revocation rules in the builder architecture/security profile before PR 06.

## Acceptance

Tool descriptions, stored state, and observed Keycloak behavior agree. No test
may label token-family revocation PASS based only on the gateway denylist.

## Local validation evidence

- Gateway captures and requires `sid`; token `jti` remains diagnostic only.
- Local state is revoked before the Keycloak call, so an upstream timeout cannot
  silently restore gateway access.
- Keycloak service-token and exact session-delete requests are covered with
  success, idempotent 404, denial, malformed/unsafe body, and timeout tests.
- Ownership tests prevent one CEERAT user from selecting another user's
  connection or invoking Keycloak for it.
- Upstream uncertainty returns `OUTCOME_UNKNOWN`, `operation_state` of
  `outcome_unknown`, and sanitized recovery information.
- Full gateway unit suite and build pass; realm policy suite passes.

## Live validation evidence

- Keycloak reconciliation enabled `ceerat-gateway-revoker`, assigned only the
  built-in `realm-management/manage-users` role, and set its Render-managed
  secret without printing it.
- The first live attempt safely returned `OUTCOME_UNKNOWN` after local denial
  when Keycloak rejected mismatched service credentials. No false success was
  reported and the error disclosed no secret.
- Coordinated credential rotation restored service-client authentication.
- Confirmed ChatGPT logout returned `authorization_server_session_revoked:
  true`, `revoked: true`, and `operation_state: completed` for
  `ceerat-mcp-chatgpt`.
- The immediately following protected request could not run and ChatGPT
  required reconnection, proving the authorization-server refresh path was no
  longer usable.
- Live A/B/C isolation across three distinct Keycloak session IDs remains a
  broader multi-session acceptance scenario; the public contract already
  discloses that clients sharing one SSO session can be signed out together.
