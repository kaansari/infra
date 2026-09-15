# CEERAT configuration-hardening (`confi`) PR plan

This is the extensible configuration-security track for CEERAT. It contains
deployment, secret, network, identity-provider, observability, and operational
gates that do not belong inside a business-domain implementation PR.

Add future configuration-hardening items here as separately reviewable PRs.
Do not hide application behavior changes, domain schema changes, or compatibility
paths inside this track.

## Relationship to canonical OAuth

The OAuth/gRPC implementation series in [`../oauth-grpc-auth/`](../oauth-grpc-auth/)
may complete local functional development independently. It cannot be declared
production-complete or rated at the target 7.5–8 security level until the
required `confi` gates below pass in the deployment environment.

## PR sequence

| Order | PR | Outcome |
| --- | --- | --- |
| 1 | [Credential inventory and rotation](01-credential-inventory-rotation.md) | Rotate exposed/shared credentials and establish ownership/rotation evidence |
| 2 | [PostgreSQL network isolation](02-postgres-network-isolation.md) | Remove broad public database exposure and use private connections |
| 3 | [gRPC transport security](03-grpc-transport-security.md) | Require TLS for public gRPC and document private-service transport controls |
| 4 | [Administrative MFA and session policy](04-admin-mfa-session-policy.md) | Require strong MFA and constrained admin sessions |
| 5 | [Automated secret scanning](05-secret-scanning.md) | Block committed credentials and scan build/log artifacts safely |
| 6 | [Keycloak configuration drift](06-keycloak-drift-gate.md) | Detect realm/client/scope/provider skew before deployment |
| 7 | [Centralized security audit](07-central-security-audit.md) | Retain correlated append-only security events with restricted access |
| 8 | [Production configuration acceptance](08-production-acceptance.md) | Verify every required configuration gate and freeze sanitized evidence |

## Required versus extensible items

PRs 01–08 are required before the canonical OAuth series is declared complete
for production. Additional `confi` PRs may be appended for WAF, DDoS controls,
SIEM alerting, dependency scanning, backup policy, disaster recovery, access
reviews, compliance controls, or provider-specific hardening.

## New-system rules

- Configure one intended production path; do not preserve obsolete settings,
  public fallbacks, dual secrets, alternate issuers, or compatibility networks.
- Local, test, and production credentials and OAuth applications are distinct.
- Secrets are never committed, printed, copied into evidence, or placed directly
  in `render.yaml`.
- Configuration changes are reviewed as code where possible, reconciled through
  idempotent tooling, and verified against actual deployed state.
- Local-first tests precede Render changes. Live mutation requires explicit
  operator intent and is followed by read-only verification.
- Browser applications and legacy agent work remain out of scope.

## Builder workflow

Use `ceerat-platform-builder-agent` for architecture, security, database, RBAC,
and drift context on every PR:

```text
ceerat-builder check-context
ceerat-builder codex-context --output json
ceerat-builder evidence request "CEERAT production configuration hardening" --output json
ceerat-builder patterns grpc-security --output json
ceerat-builder rbac check --output json
ceerat-builder check sql --output json
ceerat-builder check drift --output json
```

Builder output informs boundaries; it does not authorize live mutation. Update
durable builder standards only after automated and human validation.

## Evidence rules

Evidence may contain resource names, configuration booleans, CIDR counts,
certificate metadata, policy hashes, sanitized client IDs, request/trace IDs,
timestamps, and PASS/FAIL results. It must never contain passwords, private
keys, access/refresh tokens, authorization codes, cookies, SMTP/API secrets,
database URLs, full claim sets, customer PII, or recovery codes.

