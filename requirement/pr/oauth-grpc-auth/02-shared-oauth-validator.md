# PR 02: Shared Keycloak/OIDC access-token validator

Repository: `contracts-repo`  
Depends on: PR 01

Implementation status: complete (synthetic local gates passed; local Keycloak
acceptance remains a required pre-push gate)

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

Before push, run the validator against tokens issued by local Keycloak in
addition to synthetic cryptographic fixtures. It must not contact Render.

## Out of scope

Service wiring, identity database access, gateway forwarding, browser apps,
runtime validator activation, and live deployment.

## Documentation after PR

Update contract security docs and inventory with validator inputs, principal
fields, cache/rotation behavior, and error contract.

## Implemented result

- Added a dependency-free RSA/RS256 validator with exact issuer,
  `ceerat-api` audience, approved `azp`, `sub`, `jti`, `sid`, time, signature,
  token-size, claim-size, and key-type checks.
- Added immutable `OAuthPrincipal` accessors for issuer, subject, client ID,
  normalized scopes, safe token/session IDs, expiry, and verified identity
  attributes, plus context helpers for later interceptors.
- Added bounded JWKS request timeout, response and key-count limits, cache TTL,
  single-flight refresh, rotation on unknown `kid`, and known-key-only bounded
  stale fallback.
- Added stable sanitized validation codes whose public error text never embeds
  token, claim, signature, or key content.
- Did not change `NewJWTInterceptor`, service wiring, gateway behavior, or live
  Keycloak state.

## Automated evidence

```text
go test -race ./security/... PASS
go test ./...                PASS
go build ./...               PASS
ceerat-builder rbac check    PASS
ceerat-builder check drift   PASS
```

The remaining local Keycloak token test cannot be replaced by synthetic
fixtures and must pass before these commits are pushed, as required by the
parent local-first gate.
