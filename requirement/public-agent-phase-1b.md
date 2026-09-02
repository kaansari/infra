# Public agent Phase 1-B: self-service identity

Status: native identity exchange is deployed and validated; split OAuth clients
and hardening require PR 03 live reconciliation and client smoke tests

## Outcome

A ChatGPT or Codex user authenticates at CEERAT Keycloak using either a native
CEERAT account or Google. On the first protected MCP call, the gateway validates
the external access token and exchanges the verified issuer/subject identity
over private gRPC. The user service idempotently creates or resolves the CEERAT
customer user and profile and returns a short-lived internal CEERAT session.

```text
ChatGPT/Codex
  -> Keycloak native login or Google federation
  -> OAuth access token with verified email and stable subject
  -> ceerat-agent-gateway
  -> gateway-workload-authenticated ExchangeExternalIdentity
  -> external_identities mapping + CEERAT user/customer
  -> internal JWT for private gRPC operations
```

The legacy `Auth(User{id})` token-minting behavior is removed. External OAuth
tokens never become internal service credentials, and model arguments never
select a CEERAT user.

## Security properties

- The gateway validates OAuth signature, issuer, audience, client, lifetime,
  subject, verified email, and operation scopes.
- The user service requires a separate random workload secret of at least 32
  characters using constant-time comparison.
- Render generates the secret once on the private user service and references
  the same value from the gateway with `fromService.envVarKey`.
- Provisioning stores a unique `(issuer, subject)` mapping and creates the user,
  customer, and mapping in one transaction.
- A verified email may resolve an existing active customer account. Noncustomer
  or inactive accounts fail closed.
- Externally provisioned users receive a random unusable local password hash;
  provider credentials and tokens are never stored by CEERAT.
- Public failures remain generic and model-actionable; workload credentials and
  identity internals are not returned.

## Deployment prerequisites

Set `CEERAT_GOOGLE_CLIENT_ID`, `CEERAT_GOOGLE_CLIENT_SECRET`, and the
`CEERAT_SMTP_HOST`, `CEERAT_SMTP_PORT`, `CEERAT_SMTP_FROM`,
`CEERAT_SMTP_USER`, and `CEERAT_SMTP_PASSWORD` secrets on Keycloak. The Google
OAuth client must allow:

```text
https://ceerat-keycloak.onrender.com/realms/ceerat/broker/google/endpoint
```

Keycloak startup import skips an existing realm. Apply Google, SMTP, and
`verifyEmail=true` through the Admin Console/API on the live realm as well as
retaining them in `dev/keycloak/ceerat-realm.json`.

The current pilot uses Brevo authenticated SMTP through
`smtp-relay.brevo.com:2525`, with STARTTLS enabled and implicit SSL disabled.
The Brevo SMTP key exists only in the Render secret
`CEERAT_SMTP_PASSWORD` and must never be committed.

Hosted ChatGPT and native Codex use separate public OAuth clients. ChatGPT has
only its exact hosted callback; Codex has only the loopback callback exception.
Both require authorization code + PKCE `S256`, disable implicit/password flows,
and receive the explicit CEERAT scopes/audience. The original
`ceerat-mcp-dev` client remains enabled only for a time-bounded rollback until
both replacements pass live smoke tests.

## Acceptance criteria

1. A new native user verifies email and the first MCP call creates exactly one
   CEERAT user, customer, and external identity mapping.
2. Repeated and concurrent exchanges do not create duplicates.
3. A new Google user completes the same flow without a CEERAT password.
4. Missing or incorrect workload credentials fail with `Unauthenticated`.
5. ID-only `auth.Auth/Auth` requests cannot mint a token.
6. Invalid OAuth identity or scope data fails safely.
7. ChatGPT and Codex can access only the provisioned customer's records.
8. Credentials and tokens never appear in responses or logs.

## Remaining production gate

Connection revocation and profile-update preparations use PostgreSQL in the
dedicated `ceerat_agent_gateway` schema and survive restarts/multiple gateway
instances. Keycloak session/token revocation remains a production gate: gateway
revocation currently denies MCP use at CEERAT but does not terminate the
authorization-server session itself.
