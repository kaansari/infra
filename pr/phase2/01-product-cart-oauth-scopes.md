# Phase 2 PR 01: Product and cart OAuth scopes

Repository: `infra`  
Depends on: Phase 1 release acceptance  
Risk: OAuth configuration only; no tools become callable in this PR

Status: deployed and credential-free live policy verified; interactive grant
checks remain the final acceptance gate

## Objective

Add least-privilege Keycloak scopes and consent descriptions for:

```text
ceerat.products.read
ceerat.products.cart.read
ceerat.products.cart.write
```

Assign them as optional scopes to the dedicated ChatGPT and Codex clients. Do
not add them to the legacy rollback client by default and do not make them realm
default scopes.

## Changes

- Update checked-in realm/client configuration and idempotent live reconciler.
- Add concise human consent text distinguishing catalog reads, cart reads, and
  cart modification.
- Preserve confidential ChatGPT and public Codex client authentication modes,
  exact redirects, PKCE `S256`, and existing Phase 1 scopes.
- Extend static and credential-free live OAuth policy tests.
- Audit scope request/grant/denial by server request ID and client ID without
  recording tokens, authorization codes, credentials, or raw claim payloads.
- Document rollout and rollback without exposing either client secret.

## Builder/security gate

Run the common workflow in [README](README.md), plus:

```bash
ceerat-builder app-impact ceerat-agent-gateway --output json
ceerat-builder patterns grpc-security --output json
```

Verify scopes grant categories of action only; they do not grant ownership,
price control, inventory control, checkout, or administrative product access.

## Acceptance

- Keycloak config tests prove exact scope definitions and optional assignment.
- Existing Phase 1 consent and refresh behavior remain unchanged.
- A token lacking the new scope will later be rejected by the matching tool.
- Reconciliation is idempotent and preserves the ChatGPT client secret.
- `make test-keycloak-config`, builder checks, and platform verification pass.

Rollback removes optional assignments before definitions and never deletes the
existing Phase 1 clients.

## Integration test

After reconciliation in a disposable/local realm, obtain tokens with each new
scope for both dedicated client types and inspect only decoded non-secret claim
names. Prove omitted scope, unregistered scope, wrong client, and invalid PKCE
fail. Run the credential-free live policy probe after deployment; never persist
authorization codes, access/refresh tokens, or client secrets.

## Implementation record

- Added all three consent-bearing client-scope definitions to the import realm
  and idempotent live reconciler.
- The reconciler explicitly attaches each optional scope through Keycloak's
  client-scope assignment endpoint; updating an existing client representation
  alone is not treated as proof that the live assignment was applied.
- Assigned them as optional scopes only to `ceerat-mcp-chatgpt` and
  `ceerat-mcp-codex-dev`; realm defaults and `ceerat-mcp-dev` are unchanged.
- Preserved confidential ChatGPT/public Codex OAuth modes, exact redirects,
  PKCE, Phase 1 scopes, offline access, and secret-preserving reconciliation.
- Enabled bounded Keycloak authentication/consent event auditing and extended
  the credential-free probe for registered and unknown product scopes.
- Added static checks for exact scope definitions, consent, optional assignment,
  rollback-client isolation, event policy, and reconciliation order.

Do not mark this PR accepted until reconciliation and the post-deployment OAuth
policy probe pass, followed by a synthetic-user consent/token claim check for
each dedicated client.

Local validation on 2026-09-03:

```text
make test-keycloak-config: PASS (12 tests, 112 assertions)
builder context/app-impact/gRPC-security/RBAC/drift/apps: PASS
make verify-platform: PASS
JSON parsing, shell syntax, and git diff checks: PASS
```

Live validation on 2026-09-04:

```text
live scope definition reconciliation: PASS
explicit optional assignment to ceerat-mcp-chatgpt: PASS
explicit optional assignment to ceerat-mcp-codex-dev: PASS
ChatGPT confidential-client secret preservation: PASS
credential-free OAuth policy smoke test: PASS
```

Interactive consent and decoded scope-claim checks remain pending. No product
or cart tools are exposed by this PR.

The first ChatGPT check exposed a cross-repository integration gap: the live
gateway still advertised only its Phase 1 scope set, so ChatGPT retained its
old grant. A bounded companion change in `apps-repo` now publishes the complete
Phase 1 + Phase 2 set from RFC 9728 protected-resource metadata. Deploy the
gateway and create a fresh authorization grant before repeating the interactive
check.
