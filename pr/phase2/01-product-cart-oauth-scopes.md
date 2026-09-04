# Phase 2 PR 01: Product and cart OAuth scopes

Repository: `infra`  
Depends on: Phase 1 release acceptance  
Risk: OAuth configuration only; no tools become callable in this PR

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
