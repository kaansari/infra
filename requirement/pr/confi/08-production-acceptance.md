# Confi PR 08: Production configuration acceptance

Depends on: Confi PRs 01–07 and OAuth/gRPC PRs 01–07

## Objective

Prove the deployed configuration meets the required security baseline before
declaring the canonical authentication series production-complete.

## Gate matrix

- All exposed/shared credentials rotated; superseded values rejected.
- No broad PostgreSQL public allowlist; private service connectivity passes.
- Public direct gRPC requires valid TLS; plaintext/downgrade fails.
- Admin MFA, separate clients, bounded sessions, and recovery pass.
- Repository/build/artifact/log secret scans pass.
- Keycloak/gateway client, scope, audience, redirect, PKCE, provider, lifetime,
  and grant configuration matches declared state.
- Direct gRPC and MCP use the same Keycloak OAuth-token security chain while
  retaining CEERAT scope, RBAC, account-status, and ownership checks.
- Central security audit receives a complete correlated sanitized chain.
- Backup/restore and credential/config rollback procedures are exercised.

## Execution order

1. Complete all local-first OAuth and configuration tests.
2. Review sanitized local evidence.
3. Apply live configuration changes explicitly in dependency order.
4. Run read-only deployed-state verification.
5. Run bounded direct gRPC/OAuth and MCP/OAuth acceptance.
6. Verify negative security cases and monitoring alerts.
7. Record commit/deploy/config hashes and PASS/FAIL evidence.
8. Roll back only through the new canonical configuration; do not restore
   superseded credentials, broad networks, plaintext, or dual token paths.

## Completion rule

Any failed, skipped, unknown, or manually assumed required gate blocks the
production-complete declaration. A provider or platform limitation must be
documented and remediated, not waived silently.

## Out of scope

Browser application validation, unrelated domain features, compliance
certification, and claiming a formal security score without independent review.

## Documentation after PR

Update the platform security baseline, incident response, deployment, secrets,
network, TLS, identity, audit, backup/restore, and operator runbooks. After human
validation, update the platform-builder standards and record the final sanitized
milestone evidence.
