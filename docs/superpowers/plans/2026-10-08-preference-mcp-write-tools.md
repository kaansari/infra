# PR07 preference MCP prepare/confirm plan

Implement the supplied PR07 requirements inline in the existing gateway checkout.

1. Write failing four-tool inventory and confirmation/schema tests.
2. Add canonical four-tool policies and a narrow private preference mutation client.
3. Add flat closed upsert/delete preparation inputs with one closed typed value and scope shape, exact mutual-exclusion/contract validation, explicit confirmation descriptions, and no public authority fields.
4. Persist reviewed requests/previews in a dedicated short-lived gateway preparation table, with subject/user/client/operation/version/fingerprint/key-digest/expiry binding. Consume once atomically before dispatch. No retry of a consumed preparation; uncertain dispatch outcomes require operation status with the original key.
5. Add regression coverage for all value/scope shapes, previews, binding/tampering/expiry, revocation, lost replies, replay/conflicts, safe logging, limits and real PostgreSQL restart/horizontal-instance concurrency.
6. Update snapshots, discovery, inventory and documentation; run full tests/build, race/PostgreSQL tests and builder gates. Request one fresh final review, resolve findings, and record local commits.

Ruling: reuse the existing checkout in the established multi-repository workflow and execute the supplied design without another permission handoff. Scope is implementation/local verification; live writes and deployment remain gated on live PR05 and hosted app version acceptance.

## Execution ledger

- Initial inventory test failed with all four tools missing, then passed.
- Implemented schemas/contract validation, immutable previews, single-use durable confirmations, canonical policies, discovery/inventory and operational docs.
- Ruling: store private request/preview bytes using the existing private gateway database lifecycle. No new credential; restrict table/backup access like existing preparation tables. Exact bytes make digest/CAS stable across PostgreSQL restarts.
- Ruling: redact original operation keys from all errors. Status guidance references the original prepare key using operation kind/tool plus use_original_idempotency_key; successful preparation returns the original key.
- Ruling: FailedPrecondition after dispatch is uncertain because the private service uses that code for unknown outcomes too. Never parse private error text to infer rollback.
- Watched mismatched successful-result regression fail, then bound projection to the exact reviewed preference (timestamps excluded) and profile increment.
- Real PostgreSQL restart/concurrency tests passed under race detection. Initial fixture race came from a shared mutable fake principal; fixed with per-request principal copies. Full race suite exposed a 1 ms test deadline affecting unrelated rejection cases; restrict the deadline fixture to its intended post-dispatch delay with sufficient setup time.
- Fresh read-only review reported no actionable findings. Remaining work: record final verification outputs and scoped local commits. Hosted acceptance remains outside local completion.

## Completion

All tasks completed. Required full gateway tests/build, full race suite, real
PostgreSQL race tests, canonical security/preference checks and builder context/
apps/drift gates passed. Follow-up review confirmed exact-result binding and
consumed-preparation status guidance. Local implementation is ready; live PR05,
public schemas and hosted version acceptance remain deployment gates.
