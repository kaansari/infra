# PR 04: Token verification and scope enforcement tests

Repository: `apps-repo`

Depends on: PR 01 and the final client/audience decisions in PR 03

Status: **implemented and verified locally; deployment validation pending**.

## Objective

Prove CEERAT, rather than ChatGPT or tool metadata, enforces authentication and
authorization on every protected call.

## Changes

- Add a table-driven token-validation suite covering signature, issuer,
  audience/resource, expiration, not-before, subject, authorized client,
  verified email, token ID/session ID, and malformed claims.
- Add a table-driven tool/scope matrix:
  - profile read -> `ceerat.profile.read`
  - prepare/update -> `ceerat.profile.write`
  - connection list -> `ceerat.connections.read`
  - connection revoke -> `ceerat.connections.revoke`
- Invoke handlers directly with deliberately under-scoped valid tokens so tests
  do not depend on MCP descriptions.
- Assert safe `WWW-Authenticate`, `UNAUTHENTICATED`, `INSUFFICIENT_SCOPE`,
  request ID, agent action, and operation state behavior.
- Enforce an explicit OAuth authorized-client allowlist from
  `CEERAT_OAUTH_ALLOWED_CLIENT_IDS`; audience validation alone is insufficient.

## Tests

Every validation dimension has positive and negative cases. Tests also assert
that raw JWTs, secrets, claims dumps, stack traces, internal hosts, and gRPC or
database errors do not appear in public output.

## Non-goals

No rate limiter, Keycloak administration, or live multi-user fixture.

## Builder-agent and documentation gate

- Run the shared workflow plus `ceerat-builder patterns grpc-security --output
  json` and `ceerat-builder rbac check --output json`.
- Validate that JWT verification and tool-scope enforcement occur inside
  CEERAT and that neither annotations nor model arguments grant authority.
- Update the gateway security/testing documentation and scope matrix in this
  PR.
- After validation, synchronize the tested token/scope matrix into the builder
  public-AI and RBAC standards before PR 05.

## Acceptance

Mutation handlers cannot be reached with a token lacking their required scope,
even when called directly and with otherwise valid arguments.

## Validation evidence

- Builder context loaded successfully.
- Builder gRPC security pattern confirmed JWT -> RBAC -> logging -> handler for
  the private unary gRPC boundary.
- Builder RBAC check passed with 146 contract/inventory methods and no issues.
- The complete gateway Go test suite and build passed with an isolated module
  workspace.
- Negative tests cover wrong signature, issuer, audience, authorized client,
  expiry, not-before and required identity claims.
- Direct handler tests prove every Phase 1 read/write/revocation scope fails
  before handler work when absent.
- Safe-response tests prove verifier details, raw-token markers, internal hosts,
  ports and stack-trace text are not returned to the MCP client.
