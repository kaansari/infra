# PR 01: Canonical OAuth architecture and method-scope policy

Repositories: `infra`, `contracts-repo` documentation/security inventory  
Depends on: none

## Objective

Freeze the single end-user authentication contract before runtime code changes.
Define the canonical API audience, approved client classes, verified claims,
method-to-scope matrix, workload boundary, TLS boundary, error semantics, and
coordinated cutover/rollback procedure.

## Work

- Inventory all contract and live gRPC services/RPCs; explain any contract/live
  mismatch such as a contract that is not registered yet.
- Add an explicit scope requirement for every protected method. A method may
  name one required scope or an intentional any/all expression; absence is an
  error, never “authentication only” by accident.
- Keep only true bootstrap/health methods public. Re-evaluate the superseded
  development `auth.Auth` password/token methods and mark them for removal in
  PR 07.
- Define `ceerat-api` audience semantics shared by direct gRPC and MCP tokens.
- Define approved end-user clients and separate workload clients. Forbid using
  client-credentials tokens as customer/user delegation.
- Define safe OAuth errors: `Unauthenticated` for invalid/missing credentials,
  `PermissionDenied` for valid tokens lacking scope/RBAC/ownership, with no
  claim or cryptographic diagnostic leakage.
- Define local loopback plaintext versus production TLS requirements.
- Document deployment ordering and the absence of a runtime dual-token mode.
- Define the mandatory local-first gate and guard local scripts against Render
  hosts or the live issuer. No later implementation PR may deploy before both
  local direct gRPC/OAuth and MCP/OAuth paths pass.
- Update Keycloak realm/reconciliation configuration design for audience
  mapper and `ceerat-grpc-dev`; do not reconcile live state in this PR.

## Tests and gates

```text
ceerat-builder inventory contracts --output json
ceerat-builder rbac check --output json
ceerat-builder check sql --output json
go test ./security/...
```

Add a contract test proving every protected known gRPC method has an explicit
scope policy and no protected method appears in the public allowlist.

## Out of scope

Runtime validator wiring, token forwarding, database migration, browser apps,
legacy agent service, REST, and live Keycloak mutation.

## Documentation after PR

Update the contract security inventory, gRPC security documentation, OAuth
deployment runbook, and this plan with the frozen identifiers and test result.
This documentation-only PR may be pushed after its static gates; runtime PRs
must obey the local-first gate in the parent plan.
