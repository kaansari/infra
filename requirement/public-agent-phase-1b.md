# Public agent Phase 1-B: self-service identity

Status: native identity exchange, split OAuth clients, verified-email policy,
and Keycloak-backed session revocation are deployed; final multi-user and
provisioning acceptance remains pending

## Outcome

A ChatGPT or Codex user authenticates at CEERAT Keycloak using a native CEERAT
account. On each protected MCP call, the gateway validates the Keycloak access
token and forwards that exact bearer token over private gRPC. The user service
independently validates it and idempotently creates or resolves the CEERAT
customer user and profile from the verified issuer/subject.

```text
ChatGPT/Codex
  -> Keycloak native login or Google federation
  -> OAuth access token with verified email and stable subject
  -> ceerat-agent-gateway
  -> same OAuth token over private gRPC
  -> external_identities mapping + CEERAT user/customer
  -> method scopes + RBAC + ownership
```

There is no password/token-minting or identity-exchange RPC. Model arguments
never select a CEERAT user.

## Security properties

- The gateway validates OAuth signature, issuer, audience, client, lifetime,
  subject, verified email, and operation scopes.
- The user service repeats issuer, signature, canonical `ceerat-api` audience,
  client, lifetime, subject, scope, role, account, and ownership enforcement.
- Provisioning stores a unique `(issuer, subject)` mapping and creates the user,
  customer, and mapping in one transaction.
- A verified email may resolve an existing active customer account. Noncustomer
  or inactive accounts fail closed.
- Provider credentials and tokens are never stored by CEERAT.
- Public failures remain generic and model-actionable; workload credentials and
  identity internals are not returned.

## Deployment prerequisites

Set the `CEERAT_SMTP_HOST`, `CEERAT_SMTP_PORT`, `CEERAT_SMTP_FROM`,
`CEERAT_SMTP_USER`, and `CEERAT_SMTP_PASSWORD` secrets on Keycloak. Google
client settings are optional and unused while federation remains deferred.

Keycloak startup import skips an existing realm. Apply SMTP and
`verifyEmail=true` through the Admin Console/API on the live realm as well as
retaining them in `dev/keycloak/ceerat-realm.json`.

The current pilot uses Brevo authenticated SMTP through
`smtp-relay.brevo.com:2525`, with STARTTLS enabled and implicit SSL disabled.
The Brevo SMTP key exists only in the Render secret
`CEERAT_SMTP_PASSWORD` and must never be committed.

Hosted ChatGPT and native Codex use separate OAuth clients. ChatGPT is a
confidential client whose secret is held only by ChatGPT and has only its exact
hosted callback. Codex is a public client with only the loopback callback
exception. Both require authorization code + PKCE `S256`, disable
implicit/password flows, and receive the explicit CEERAT scopes/audience. The original
`ceerat-mcp-dev` client remains enabled only for a time-bounded rollback until
both replacements pass live smoke tests. Google federation is a later optional
login method and is not part of the Phase 1 release gate.

## Acceptance criteria

1. A new native user verifies email and the first MCP call creates exactly one
   CEERAT user, customer, and external identity mapping.
2. Repeated and concurrent exchanges do not create duplicates.
3. A new native user completes verified-email provisioning without duplicate
   CEERAT records; Google federation is tested only if it is enabled later.
4. Missing, malformed, or wrong-audience OAuth credentials fail with `Unauthenticated`.
5. No CEERAT RPC can mint or exchange an end-user token.
6. Invalid OAuth identity or scope data fails safely.
7. ChatGPT and Codex can access only the provisioned customer's records.
8. Credentials and tokens never appear in responses or logs.

## Remaining release gate

Connection revocation and profile-update preparations use PostgreSQL in the
dedicated `ceerat_agent_gateway` schema and survive restarts/multiple gateway
instances. Logout now records the local deny decision and deletes the backing
Keycloak normal/offline session; a confirmed live logout forced ChatGPT to
reconnect. The remaining release gate is the repeatable multi-user,
provisioning, datastore, audit-log, and client acceptance evidence listed in
`verification/phase1/README.md`.
