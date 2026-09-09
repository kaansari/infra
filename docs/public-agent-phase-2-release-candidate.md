# CEERAT public-agent Phase 2 release candidate

Status: automated acceptance implemented; interactive and deployment evidence
pending. This document is not a Phase 2 freeze declaration.

Phase 2 adds seven product-domain MCP tools over authenticated private gRPC:
bounded active product listing/detail, self-cart read, and versioned/idempotent
self-cart add, update, remove, and prepared/confirmed clear. External OAuth
terminates at the gateway. The user service remains authoritative for JWT/RBAC,
identity-derived customer ownership, product visibility, pricing, inventory,
transactions, idempotency, optimistic concurrency, and PostgreSQL persistence.

The reproducible automated and human runbook is
`verification/phase2/README.md`; its versioned redacted schema and runner are in
the same directory. Automated results belong under ignored `.verification/`
and must not include credentials, response bodies, customer data, cart content,
or database data.

On 2026-09-09 UTC the combined release-candidate run passed all eight automated
checks against the deployed Render gateway, including the exact public MCP
surface, TLS, deterministic gateway/service/contract/builder suites,
disposable PostgreSQL coverage, and the live credential-free rate limit. Six
authenticated/operator checks remain, so the milestone is still partial.

## Required freeze evidence

- exact repository commits deployed for contracts, services, apps, and infra;
- sanitized migration/preflight, disposable rollback/reapply, restart, and
  private gRPC JWT/RBAC/ownership evidence;
- complete automated harness PASS result;
- reversible Codex and ChatGPT User A/B acceptance with request-ID correlation;
- audit retention/access review and secret/PII/topology redaction review;
- confirmation, idempotent replay, stale-version, rate-limit, timeout,
  outcome-unknown reconciliation, logout, and post-revocation evidence; and
- cleanup/restoration confirmation.

The legacy browser UI is excluded by design and must not cause restoration of
the removed customer-ID-shaped cart contract. Kubernetes remains outside the
development scope.
