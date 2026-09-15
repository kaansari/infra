# PR 02: Shared Keycloak/OIDC access-token validator

Repository: `contracts-repo`  
Depends on: PR 01

## Objective

Implement a reusable OAuth access-token validator and principal context without
wiring a parallel production authentication path.

## Work

- Validate signed JWT access tokens through bounded cached JWKS retrieval.
- Allowlist algorithms and key types; reject `none`, symmetric confusion,
  unsupported algorithms, missing/unknown `kid`, and invalid signatures.
- Validate exact issuer, canonical API audience, `exp`, `nbf`, optional `iat`
  bounds, approved client/authorized party, non-empty subject, and required
  session/token identifiers according to PR 01.
- Normalize scopes from supported Keycloak claims without trusting roles from
  token-controlled arbitrary fields.
- Return an immutable principal containing issuer, subject, client ID, scopes,
  safe token/session identifiers, expiry, and verified identity attributes.
- Add context helpers consumed by scope, RBAC, ownership, and logging layers.
- Implement bounded JWKS timeouts, cache lifetime, refresh-on-unknown-kid,
  single-flight behavior, stale-key rules, and sanitized errors.
- Do not depend on service repositories, GORM, gateway packages, or Keycloak
  admin APIs.

## Tests

- valid RSA token and multiple audiences;
- bad signature, issuer, audience, algorithm, client, `kid`, subject;
- expired/not-yet-valid/future-issued tokens and clock skew boundaries;
- malformed/oversized tokens and claims;
- scope normalization and duplicate handling;
- JWKS timeout, rotation, cache, concurrent refresh, and response-size bounds;
- error/log scan proving no token, header, claims dump, or key material leaks.

## Gates

```text
go test -race ./security/...
go test ./...
go build ./...
ceerat-builder rbac check --output json
ceerat-builder check drift --output json
```

## Out of scope

Service wiring, identity database access, gateway forwarding, browser apps,
legacy validators, and live deployment.

## Documentation after PR

Update contract security docs and inventory with validator inputs, principal
fields, cache/rotation behavior, and error contract.

