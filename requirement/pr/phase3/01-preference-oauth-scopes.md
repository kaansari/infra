# Phase 3 PR 01: Preference OAuth scopes

Repository: `infra`  
Depends on: frozen Phase 1 OAuth baseline

## Objective

Add least-privilege delegated consent for preference reads and writes without
changing existing profile, product, cart, order, or connection grants:

```text
ceerat.preferences.read
ceerat.preferences.write
```

Definitions use the read scope. Do not add a third definitions scope, shared
platform key, per-user OAuth client, public-token path, or browser handoff.

## Changes

- Add both Keycloak client scopes with truthful consent text describing
  customer-owned saved preferences.
- Assign them as optional scopes to `ceerat-mcp-chatgpt` and
  `ceerat-mcp-codex-dev`; preserve confidential/public client policy already
  established for each host.
- Add both scopes to protected-resource metadata and gateway configuration
  before preference tools are advertised.
- Extend reconciliation and OAuth policy smoke tests. Preserve idempotent client
  reconciliation and secrets exactly; never rotate or print a secret.
- Update OAuth/security/deployment documentation and platform-builder evidence.

## Security and tests

- Existing tokens do not silently gain optional scopes; require fresh consent.
- Read-only tools never require write. Every write/prepare/confirm requires
  write; operation status requires read.
- Test missing scope, only-read, only-write, both, malformed/duplicate scope,
  legacy Phase 1–2 grants, refresh tokens, and revoked grants.
- Verify discovery against the live protected-resource URL and authorization
  server metadata.

## Gates

```text
make reconcile-keycloak-live
deploy/render/keycloak/oauth-policy-smoke-test.sh
ceerat-builder rbac check --output json
ceerat-builder check drift --output json
```

Do not advertise preference tools yet. Record redacted client/scope evidence and
obtain fresh ChatGPT/Codex authorization only when PR 06 is ready for exposure.

## Out of scope

Contracts, service/database code, tools, new OAuth clients, social login, REST,
browser UI, legacy or parallel authentication.

## Implementation record (2026-09-14)

Implemented the two Keycloak client-scope templates, assigned them as optional
scopes to only the canonical ChatGPT and Codex clients in both the declarative
realm and live reconciler, and preserved the confidential ChatGPT secret flow.
The OAuth policy probe now validates both registered scopes and rejects the
unregistered `ceerat.preferences.admin` scope.

The gateway protected-resource metadata advertises both scopes, with an exact
metadata regression test and deployment smoke assertion. No preference tool,
private RPC, RBAC permission, new OAuth client, or default realm scope was
added. Static Keycloak policy tests pass. Live reconciliation, fresh consent,
and live metadata/grant evidence remain operator deployment gates.
