# PR 03A local Google acceptance record

Do not place IDs, email addresses, names, tokens, codes, cookies, PKCE values,
or secrets in this record. Record only sanitized PASS/FAIL, correlation IDs,
timestamps, and commit/config hashes.

## Preconditions

- [x] Dedicated Google development OAuth application is used.
- [x] Its only CEERAT callback is
      `http://localhost:8080/realms/ceerat/broker/google/endpoint`.
- [x] Google ID/secret exist only in local secret state; the credential file is
      ignored by Git.
- [x] `make test-keycloak-config` passes (188 assertions).
- [x] `verify-local-google-broker.rb` confirms explicit linking and no auto-link.
- [x] A sanitized S256 PKCE probe enters the local Google broker and redirects
      to `accounts.google.com`; no verifier, token, code, or secret was logged.

## Acceptance

- [x] Google login completes through local Keycloak.
- [x] Keycloak—not Google—issues the downstream token.
- [x] Token has exact local issuer, `ceerat-api`, approved client, `sub`, `sid`,
      `jti`, verified email, given name, and family name.
- [x] First resolution creates one active customer user/profile/mapping with no
      local password.
- [x] Repeated identity resolution resolves the same Keycloak subject and
      CEERAT IDs in the isolated PostgreSQL acceptance schema.
- [ ] Direct protected gRPC succeeds with correct scope and fails without it.
- [ ] Separate MCP authorization resolves the same CEERAT user.
- [ ] Duplicate email fails closed without automatic CEERAT merge.
- [ ] Blocked CEERAT account remains denied.
- [ ] Refresh, logout, and revocation behavior pass.
- [ ] Sanitized log correlation passes and secret/token/artifact scan is clean.

## Evidence

```text
commit/config hash:
test timestamp: 2026-09-15
direct gRPC request ID:
MCP request ID:
result: GOOGLE BROKER, CEERAT TOKEN VALIDATION, AND IDEMPOTENT JIT PASS;
        DIRECT GRPC/MCP AND NEGATIVE SECURITY CASES PENDING
```
