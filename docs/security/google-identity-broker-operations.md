# Google identity broker operations

Google is an authentication source for Keycloak, not a CEERAT token issuer.
CEERAT services accept only the Keycloak-issued `ceerat-api` access token and
persist only its Keycloak `(issuer, subject)` binding.

## Google OAuth applications

Use separate Google OAuth applications and secrets for local development and
production. Register only these exact authorized redirect URIs as applicable:

```text
http://localhost:8080/realms/ceerat/broker/google/endpoint
https://ceerat-keycloak.onrender.com/realms/ceerat/broker/google/endpoint
```

Do not register wildcard callbacks, ChatGPT callbacks, gateway URLs, gRPC
addresses, or application pages with Google. The Google client requests only
`openid profile email`.

## Local configuration

Keep the development ID and secret in shell/session secret state, not `.env`,
source, shell history, screenshots, or test evidence:

```text
read -r -p 'Google development client ID: ' CEERAT_GOOGLE_CLIENT_ID
read -r -s -p 'Google development client secret: ' CEERAT_GOOGLE_CLIENT_SECRET; echo
export CEERAT_GOOGLE_CLIENT_ID CEERAT_GOOGLE_CLIENT_SECRET
deploy/render/keycloak/reconcile-google-provider.rb
unset CEERAT_GOOGLE_CLIENT_ID CEERAT_GOOGLE_CLIENT_SECRET
```

The command defaults to local Keycloak, reads its generated admin password
file, performs an idempotent create/update, and prints only the non-secret
callback. It refuses non-loopback servers by default.

Verify the running local provider and first-login flow without exposing its
configuration secrets:

```text
verification/oauth-grpc/verify-local-google-broker.rb
```

The check fails if Keycloak's automatic existing-user linker is present or its
explicit account-confirmation step is absent.

Production reconciliation additionally requires all Keycloak admin variables,
production Google credentials, the exact HTTPS Keycloak server, and the
deliberate `CEERAT_ALLOW_LIVE_GOOGLE_RECONCILE=true` opt-in. Never reuse the
development Google application or secret.

## Identity and collision policy

Keycloak owns Google account linking. Google email is trusted only through the
provider's verified-email result. CEERAT never auto-links by matching email:
the PR 03 resolver creates an account only when both the Keycloak
issuer/subject binding and case-insensitive CEERAT email are unused. An email
collision requires explicit authenticated Keycloak linking or administrative
resolution. Google claims cannot assign CEERAT role, status, scopes, RBAC,
entitlements, user ID, customer ID, or ownership.

Repeated login must produce the same Keycloak subject and CEERAT user. A
blocked CEERAT user remains blocked even when Google authentication succeeds.

## Failure and incident handling

Give users a stable provider-login failure with a correlation ID. Operators may
inspect sanitized Keycloak `IDENTITY_PROVIDER_*`, login, and token-exchange
events plus correlated gateway/service logs. Never copy provider tokens,
authorization codes, cookies, PKCE verifiers, Google IDs/secrets, full claim
sets, or customer PII into tickets or evidence.

On suspected compromise, disable the Google provider, rotate the Google secret,
reconcile it, revoke affected Keycloak sessions, and verify CEERAT mappings.
Do not enable direct Google-token acceptance or an email auto-link fallback.
