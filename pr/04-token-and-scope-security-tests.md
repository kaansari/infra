# PR 04: Token verification and scope enforcement tests

Repository: `apps-repo`

Depends on: PR 01 and the final client/audience decisions in PR 03

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

## Tests

Every validation dimension has positive and negative cases. Tests also assert
that raw JWTs, secrets, claims dumps, stack traces, internal hosts, and gRPC or
database errors do not appear in public output.

## Non-goals

No rate limiter, Keycloak administration, or live multi-user fixture.

## Acceptance

Mutation handlers cannot be reached with a token lacking their required scope,
even when called directly and with otherwise valid arguments.
