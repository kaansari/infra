# Phase 3 PR 09: Live ChatGPT/Codex acceptance and milestone freeze

Repositories: `infra`, `ceerat-platform-builder-agent` documentation  
Depends on: PR 08 passing and all required services live

## Objective

Prove the Phase 3 preference lifecycle through fresh ChatGPT and Codex
connections, record redacted evidence, clean disposable state, synchronize
documentation/inventories, and freeze the milestone.

## Operator preflight

1. Verify deployed contract, database migration/preflight, user-service, and
   gateway commits match the supported tuple.
2. Reconcile Keycloak, run OAuth policy smoke tests, verify protected-resource
   metadata includes both preference scopes, and obtain fresh consent.
3. Verify authenticated private gRPC and live MCP `tools/list` schemas.
4. Create/refresh the hosted ChatGPT development app version and record its new
   Version ID; reconnect Codex. A new chat alone is insufficient.
5. Prepare two disposable customers and non-sensitive fixtures; capture initial
   preference state for cleanup.

## Acceptance sequence

Run through both clients with exact prompts stored in the acceptance harness:

1. Authentication/client/scopes and preference-domain discovery.
2. Search definitions and list/context empty state.
3. Prepare one safe canonical preference; report exact preview and stop.
4. Human confirms; confirm once; get/list/context verify versions and compact
   projection.
5. Replay original idempotency key and prove `replayed=true`; changed payload
   conflicts without mutation.
6. Prepare update, force stale version, prove no mutation; prepare/confirm fresh
   update and verify profile/resource version increments.
7. Prove the second customer cannot discover or mutate the first record and can
   independently use the same logical key.
8. Prepare/confirm deletion and verify absent from active get/list/context while
   retention semantics remain truthful.
9. Force one controlled unknown outcome and reconcile through operation status
   without repeating confirmation.
10. Verify token expiry/refresh, scope denial, logout/revocation, rate limit,
    safe dependency failure, and prompt-like fixture handling.
11. Clean all disposable preferences and verify original state restored except
    monotonic versions/audit allowed by policy.

Each write has a fresh idempotency key, its own preview, and separate explicit
human confirmation. Stop immediately on dependency unavailable, schema mismatch,
scope mismatch, unknown outcome without status, or evidence leakage.

## Evidence

Record only client/app version, deployed commits, request IDs, operation states,
safe versions/counts, replay flag, error codes, and PASS/FAIL. Do not commit
preference keys, names, values, notes, queries, summaries, user emails, tokens,
raw idempotency keys, page tokens, or preparation IDs.

## Freeze

After all checks pass:

- update the Phase 3 requirement/README and affected API, security, logging,
  architecture, migration, testing, and inventory documents;
- update durable `ceerat-platform-builder-agent` preference ownership, privacy,
  prompt-safety, confirmation, idempotency, and deployment standards;
- run all builder gates again and confirm no active legacy/parallel route;
- mark PRs 01–09 complete and create the agreed milestone tag.

## Completion rule

Automated tests alone do not close Phase 3. One client passing does not close
Phase 3. Phase 3 closes only after both ChatGPT and Codex pass the complete live
matrix, cleanup passes, evidence is redacted, and builder/inventory drift is
zero.
