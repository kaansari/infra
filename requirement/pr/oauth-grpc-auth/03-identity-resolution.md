# PR 03: Verified OAuth identity resolution and account authority

Repository: `services-repo`  
Depends on: PR 02

Implementation status: complete and dormant (local Keycloak/PostgreSQL gates
passed; no production wiring or live mutation)

## Objective

Map a cryptographically verified Keycloak `(issuer, subject)` to the current
CEERAT user/customer without accepting identity from request payloads or minting
a second end-user token.

## Work

- Add a service adapter that accepts only the shared verified OAuth principal.
- Resolve the existing external identity mapping transactionally; on approved
  first login, JIT-provision the CEERAT user/customer using verified claims.
- Require verified email for automatic provisioning and handle concurrent first
  calls idempotently through the existing unique issuer/subject boundary.
- Reload current CEERAT role/status from PostgreSQL on authorization; token
  claims may not override a blocked/deactivated account or stored RBAC role.
- Define safe behavior for changed email/name, duplicate email, missing customer
  mapping, and subject/client changes. Never merge accounts by unverified email.
- Stop returning or persisting Keycloak access/refresh tokens.
- Determine whether the local password column can be made nullable or removed.
  If changed, add a new migration, rollback/preflight, and disposable lifecycle
  test; never rewrite an applied migration.
- Keep the resolver dormant until PR 04; do not add a second active validator.

## Tests

- existing identity, approved first login, concurrent first login;
- same subject across different issuers, same email across different subjects;
- missing/unverified email and disallowed client;
- blocked/inactive/deleted current CEERAT user;
- customer ownership derivation and no request-controlled identity;
- database error sanitization and absence of token storage.

## Gates

```text
go test -race ./user/... ./customers/...
CEERAT_TEST_DATABASE_URL="$CEERAT_TEST_DATABASE_URL" go test ./...
make db-verify
ceerat-builder check sql --output json
ceerat-builder check drift --output json
```

Before push, exercise identity resolution with a real local-Keycloak token and
disposable local PostgreSQL identities. The resolver remains dormant in the
production path until the coordinated cutover.

## Out of scope

OAuth interceptor activation, gateway changes, UI compatibility, account-linking
UX, social-provider configuration, and generic identity-provider abstraction.

## Documentation after PR

Update service architecture, gRPC security, database/migration, privacy, and
identity lifecycle documentation and service inventory.

## Implemented result

- Added a principal-only resolver; request payloads cannot select identity,
  client, role, status, user, customer, or ownership.
- Exact issuer/subject mappings are transactional and concurrent first calls
  converge through the unique identity boundary.
- Verified-email first login creates one active customer user and customer
  profile. Existing case-insensitive email is a conflict, never an automatic
  merge. Changed claim email/name does not overwrite stored profile data.
- Current PostgreSQL role/status and customer ownership are reloaded on every
  resolution. Blocked, pending, missing-user, and missing-customer states fail
  closed with sanitized errors.
- OAuth-only users store a nullable password and no generated placeholder.
  Access/refresh tokens, authorization codes, cookies, and token roles are not
  persisted.
- Added forward migration, preflight, refusal-safe development rollback,
  disposable PostgreSQL lifecycle/concurrency tests, and a combined local
  Keycloak PKCE + resolver acceptance harness.

## Evidence

```text
go test -race ./user/... ./customers/... PASS
CEERAT_TEST_DATABASE_URL=<local> go test ./user -run TestOAuthIdentity PASS
go test ./... PASS
make db-verify PASS
ceerat-builder check sql PASS
ceerat-builder check drift PASS
local Keycloak PKCE + PostgreSQL resolver acceptance PASS
```
