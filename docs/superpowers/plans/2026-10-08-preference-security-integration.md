# PR08 preference security/resilience plan

Run the supplied reduced security gate using real production preference handlers,
OAuth/identity/scope/RBAC interceptors, the gateway, and disposable PostgreSQL.

1. In parallel, fix gateway authenticated readiness and add MCP fuzzing; add
   canonical protobuf fuzzing; strengthen private-service minimization/dependency
   tests. Keep each change in its owning earlier slice.
2. Build a repeatable infra harness with an isolated local PostgreSQL cluster,
   real bootstrap/migrations, signed test OAuth tokens, actual private gRPC and
   gateway HTTP boundary. Exercise two-customer reads/writes/confirm/delete/status,
   token matrix, opaque pagination/minimization, concurrency/restarts/lost replies,
   dependency failure, deployment skew and TXSE safety/default independence.
3. Scan errors, logs, traces/audit and harness artifacts with explicit context
   allowlists: owning successful preference projections are allowed; unrelated
   customer content, raw keys/tokens/SQL and sensitive artifacts are not.
4. Run proto generation, tests/race/build, verify-platform and required builder
   RBAC/apps/drift/contract-service checks, bounded fuzz campaigns. Emit only
   redacted machine-readable statuses and exact contract/service/gateway commits.
5. Resolve every discovered failure, review changes, document/run the harness,
   and record scoped local commits. Do not deploy or run live human writes.

Ruling: use the established checkout for cross-repository changes. Separate
agents own non-overlapping packages; root owns infra harness/integration module.
Disposable PostgreSQL startup/restart affects only the cluster created by the
harness, never the existing development or Render database.

## Execution ledger

- Production readiness and canonical audience alignment implemented in apps;
  canonical protobuf/MCP fuzz targets and service dependency/minimization tests
  added in their owning modules. Proto generation produced no drift.
- Disposable bootstrap/all migrations/preflight and full owning-module
  race/build suites passed. `make verify-platform` passed independently.
- Initial real integration RED exposed missing fixture customer/agent roles;
  production-style canonical role/permission reconciliation fixed it. All seven
  integration parents and nine token subcases then passed, including actual
  database restart/outage, durable preparations, and lost-reply reconciliation.
- Fresh reviewer found one important harness false-positive: partial integration
  and skipped durable gateway tests could satisfy the old coverage check.
  Three regression tests reproduced the defects (RED); explicit required parent
  inventories fixed them (GREEN, seven Python tests). Customer status assertions
  additionally check actual owning results and a foreign completed operation.
- Ruling: use an explicit test-only TXSE consumer because these repositories
  contain no TXSE engine. It exercises real preference RPC isolation/defaults;
  this evidence does not certify live ingest/book behavior. Cost if wrong: live
  TXSE acceptance must supply the actual engine rather than this reduced fixture.
- Final committed-tuple acceptance passed all 30 checks, with no required skips:
  contract `6961331`, service `fddee2c`, gateway `4cca58d`. The earlier diagnostic
  correctly rejected its tuple when those local commits changed during the run;
  the final full run used stable clean committed sources throughout.
- Nine Python harness regression tests and Render realm tests (18 tests,
  261 assertions) passed. Fresh-review coverage robustness finding is fixed;
  the additional actual foreign-completed-status assertion passed in the final
  real integration run. No review findings remain.
- Ruling: retain scoped local commits in the established checkout, matching the
  prior PR workflow. No push/deployment/merge was requested; PR09 performs hosted
  acceptance. Cost if wrong: integration into a shared branch remains separate.
