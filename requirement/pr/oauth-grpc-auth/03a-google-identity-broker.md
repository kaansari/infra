# PR 03A: Minimal Google login through Keycloak

Repository: `infra` and Keycloak realm configuration  
Depends on: PR 03  
Required before: PR 04 local end-to-end acceptance

Implementation status: local Google consent, Keycloak-issued CEERAT token
validation, and idempotent JIT identity resolution complete; direct gRPC/MCP
and negative security acceptance remain pending

## Objective

Allow a new customer to authenticate with Google while keeping exactly one
downstream security path. Google authenticates the person; Keycloak brokers the
identity and issues the same CEERAT API OAuth token used by every direct gRPC
and MCP client.

```text
Google -> Keycloak broker -> Keycloak CEERAT API token
       -> gRPC or MCP -> OAuth scope -> CEERAT RBAC -> ownership
```

Neither gRPC nor MCP accepts, sees, stores, or validates a Google token.

## Minimal work

- Add one Google identity-provider definition to the `ceerat` Keycloak realm.
- Configure the Google client ID and secret only through local secret state and
  Render secret environment variables; never commit either value.
- Register exact local and later production Keycloak broker callback URIs. Do
  not use wildcard callbacks.
- Request only the minimum Google identity scopes needed by Keycloak for login.
- Require a verified email and stable Keycloak subject before CEERAT JIT
  provisioning from PR 03 runs.
- Create new social-login users as active customers with the least-privileged
  CEERAT customer role. Google claims can never assign agent/admin roles,
  product entitlement, OAuth scopes, or RBAC permissions.
- Store only the canonical Keycloak `(issuer, subject)` mapping in CEERAT.
  Provider linking remains Keycloak-owned; add no Google columns or token table
  to the CEERAT database.
- Keep current CEERAT account status, role, RBAC, and ownership authoritative on
  every request after Google authentication.
- Give login/broker failures a safe user-facing category and correlation ID;
  keep provider diagnostics sanitized in Keycloak/operator logs.

## Account collision policy

This is a new-system policy, not compatibility handling:

- A verified Google identity with an unused address creates one Keycloak user
  and one CEERAT user/customer through the canonical JIT flow.
- Never merge CEERAT accounts merely because email strings match.
- If the address is already bound to another Keycloak subject, fail closed and
  require explicit authenticated Keycloak account linking or administrative
  resolution. Do not implement automatic email linking in this minimal PR.
- Repeated login through the same brokered identity resolves the same Keycloak
  subject and CEERAT account idempotently.
- Blocked/inactive CEERAT accounts remain denied even when Google succeeds.

## Local-first tests

Use a dedicated Google development OAuth application and local Keycloak only.
The harness must reject Render/public issuers.

1. Start the MCP/gRPC-only local stack.
2. Configure the local Keycloak Google broker using uncommitted secrets.
3. Complete Google login in a browser and return to the exact local Keycloak
   broker callback.
4. Obtain a Keycloak access token with the canonical CEERAT API audience.
5. Call a protected direct gRPC self-profile method.
6. Verify one CEERAT user/customer and external identity mapping were created.
7. Repeat login and prove no duplicate account or mapping is created.
8. Use a separate local MCP authorization and prove it resolves the same user.
9. Verify default customer RBAC, missing scope, wrong role, blocked account,
   duplicate-email collision, logout, refresh, and revocation behavior.
10. Scan PostgreSQL, service/gateway logs, Keycloak evidence, and test artifacts
    for Google/Keycloak tokens, secrets, codes, PKCE verifiers, and PII.

Automated realm tests must verify provider enablement, exact callback contract,
secret indirection, and absence of unsafe first-login auto-link behavior. The
interactive Google login is recorded as a required local human test.

## Builder and database gates

```text
ceerat-builder codex-context --output json
ceerat-builder evidence request "Google login through Keycloak into canonical CEERAT OAuth gRPC identity" --output json
ceerat-builder patterns grpc-security --output json
ceerat-builder rbac check --output json
ceerat-builder check sql --output json
ceerat-builder check drift --output json
```

Expected database outcome: no provider-specific schema change. If code review
finds a genuine invariant missing from the existing issuer/subject identity
mapping, stop and amend PR 03 with a new migration/preflight/lifecycle test;
never add a compatibility table here.

## Deployment gate

Do not push configuration for Render until the local Google -> Keycloak ->
direct gRPC and Google -> Keycloak -> MCP -> gRPC paths pass. Production uses a
separate Google credential/redirect registration and Render secrets. Never copy
development secrets into production evidence.

## Out of scope

Apple or other providers, direct Google-token acceptance, Google API access,
social contacts/data, automatic email account merging, browser-app changes,
legacy agent tools, REST, provider-specific CEERAT tables, dual tokens, and
fallback authentication.

## Documentation after PR

Update Keycloak identity-provider operations, local secret setup, account
collision policy, JIT identity flow, OAuth security, testing, and incident
documentation. Update builder standards only after automated and human local
validation confirms the reusable broker pattern.

## Implemented result

- Added a secret-free Google provider template and idempotent reconciler that
  defaults to loopback and requires explicit live-mutation opt-in.
- Kept scopes at `openid profile email`, disabled upstream-token storage and
  read-token roles, and retained Keycloak's explicit first-login linking flow.
- Added static realm/provider/template tests, broker audit events, exact local
  and production callback documentation, collision/incident operations, and a
  read-only local flow verifier that rejects automatic account linking.
- Confirmed no provider-specific CEERAT schema or direct Google-token path was
  added. PR 03 remains the only JIT account authority.
- Extended real-token identity acceptance to prove repeated resolution is
  idempotent.
- Added an interactive, loopback-only PKCE runner that uses a temporary client,
  validates a Google-brokered Keycloak token with the shared CEERAT validator,
  exercises identity resolution twice in an isolated PostgreSQL schema, never
  prints sensitive OAuth material, and removes its temporary client.
- Restored Keycloak's standard scopes only on the built-in `account` and
  `account-console` clients after local acceptance exposed an incomplete realm
  import. CEERAT API client scope assignments and RBAC remain unchanged.

## Automated evidence

```text
realm/provider tests: 188 assertions, PASS
local first-broker flow: explicit confirmation present, auto-link absent, PASS
Google browser consent and CEERAT-audience token validation: PASS
idempotent JIT identity resolution (isolated PostgreSQL schema): PASS
ceerat-builder RBAC/SQL/drift: PASS
repository secret/config scan: PASS
```

The uncommitted Google development credential was reconciled into local
Keycloak. Browser consent, token exchange, shared validation, and isolated JIT
resolution now pass. Direct protected gRPC/MCP calls and the negative security
matrix in `verification/oauth-grpc/google-human-acceptance.md` remain blocking
local gates for the interceptor work. Do not reconcile Google credentials to
Render until those checks pass.
