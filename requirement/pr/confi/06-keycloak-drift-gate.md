# Confi PR 06: Keycloak configuration-drift gate

Depends on: OAuth/gRPC PRs 01 and 03A

## Objective

Prevent gateway metadata, OAuth clients, scopes, audience mappers, Google
broker configuration, and deployed Keycloak state from diverging.

## Work

- Maintain a secret-free declarative expected-state inventory.
- Add separate local reconcile/verify and live read-only verify commands with
  unmistakable names and target banners.
- Compare clients, enabled flows, exact redirects, PKCE, token endpoint auth,
  scopes/assignments, API audience mapper, token lifetimes, revocation client,
  Google provider policy, and admin session/MFA requirements.
- Compare gateway protected-resource metadata with Keycloak scope assignments.
- Fail deployment when the gateway advertises an unregistered/unassigned scope
  or Keycloak enables a forbidden grant/redirect.
- Require explicit operator authorization for live reconciliation. Verification
  remains read-only and prints no secrets.

## Acceptance

- Missing preference or future scope is detected before clients encounter it.
- Unknown scope, wildcard redirect, disabled PKCE, wrong audience, and forbidden
  password/implicit grant fixtures fail.
- Local commands cannot resolve Render hosts; live mutation cannot run under a
  local-only command name.
- Drift output is sanitized and machine-readable.

## Out of scope

Storing client secrets in the inventory, automatic live mutation from every
developer run, and provider-specific CEERAT authentication paths.

