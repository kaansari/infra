# PR08 preference security and resilience gate

From `infra`, run `make verify-phase3-preferences`. This is a local integration
gate before PR09 live acceptance. It does not deploy anything or connect to an
existing development or hosted database.

Prerequisites: the sibling contracts/services/apps/builder checkouts, Go,
protoc and its Go plugins, `ceerat-builder`, Python 3.7 or newer, and PostgreSQL
14 or newer binaries. Set `CEERAT_PR08_PG_BIN` to their directory if it differs
from `/usr/local/opt/postgresql@14/bin`. Run as an ordinary user because
PostgreSQL refuses `initdb` as root.

The runner creates a temporary cluster bound to loopback on an unused port,
bootstraps an empty database using the production bootstrap command, applies
every migration, and runs database preflight. It supplies that disposable DSN
to the real service and gateway database suites, then runs the cross-repository
integration module against the same schema. Only the directory created by the
runner can be stopped or removed. No existing database credentials are needed.

The nested Go module imports the production contract, service handlers,
OAuth/identity/scope/RBAC interceptors, and gateway HTTP handlers. Its module
name intentionally shares the gateway import prefix so it can exercise the
gateway's internal packages without exposing them as a production API. Local
module replacements select the exact sibling source trees. Production vendor
builds are checked separately by the runner.

The full gate also runs proto generation, race tests and builds in each owning
module, eight bounded fuzz campaigns, `make verify-platform`, and all four
required builder checks. Required database/integration test skips fail the
gate. `--focused` is a diagnostic shortcut that omits platform/builder checks;
its result is explicitly `diagnostic_passed` and cannot satisfy PR08.
`--integration-only` additionally skips owning-module suites and fuzzing to
reproduce integration assertions quickly in a newly bootstrapped database.

`evidence/latest.json` contains only check names, status, duration, approved
test names, timestamps, and the exact contract/service/gateway Git commit tuple
with source digests and dirty flags. Commands capture raw output privately;
they never print it or put it in evidence. PostgreSQL logs live only in the
temporary directory and are removed on cleanup.
Full acceptance requires committed owning module sources and rejects a tuple
that changes during the run. Diagnostic runs can exercise uncommitted fixes.
Failure reports give a stable failure code, the failed check, and safe test
names/source coordinates. They never serialize request bodies,
credentials, SQL, topology, fixture values, or exception strings.

Privacy assertions distinguish explicitly requested owning successful data
from forbidden artifacts: a successful preference read necessarily returns
its authorized value. Error/log/audit/trace artifacts permit only approved
metadata; foreign and unrelated preference values are forbidden everywhere.

The TXSE integration fixture is a test-only consumer with explicit defaults and
immutable entitlement/environment/classification/formula/provenance/health/
warning fields. The repositories currently contain no TXSE ingest/book engine.
This reduced boundary gate proves preference isolation and default behavior;
it does not certify a live exchange feed or create an intelligence product.

The OAuth audience is the canonical `ceerat-api` in gateway, private service,
and local/Render settings. The MCP resource URL remains the protected-resource
identifier. `/healthz` is liveness. `/readyz` requires a caller's read-scoped
OAuth bearer, checks durable gateway schema/revocation, and calls authenticated
private `ListMyPreferences` with page size one. Do not configure an anonymous
hosting health probe against `/readyz` or store a privileged probe bearer.

## Matrix ownership

| Required area | Executed evidence |
| --- | --- |
| Invalid tokens, scopes, stored roles, durable revocation, OAuth metadata | `TestPR08IdentityAuthorizationAndReadiness`; contract security tests and gateway binding tests |
| Two customers, prepare/confirm/delete/status, replay/conflict | `TestPR08TwoCustomersLifecycleAndReplay`; service ownership and write race suites |
| Lost committed reply, status without redispatch | `TestPR08LostReplyStatusWithoutRedispatch`; service encrypted replay and gateway outcome suites |
| Closed contract, unavailable service, missing durable schema | `TestPR08ContractSchemaAndServiceSkew`; contract JSON/wire and gateway malformed-response suites |
| Request authority, prompt data, pagination, category minimization | `TestPR08MCPAuthorityMalformedPromptAndPagination`; service context/edge suites |
| PostgreSQL restart/outage/recovery, gateway recreation | `TestPR08PostgresRestartReadinessAndDurability`; gateway durable multi-instance confirmation suite |
| Concurrency, stale versions, preparation expiry/reuse, definition changes | Service `write_race_postgres_test.go`, `write_edges_postgres_test.go`, `write_policy_postgres_test.go`; gateway `preference_preparations_test.go`, `preference_write_test.go` |
| Audit/idempotency dependency atomicity, status-only recovery, opaque refs, SQL/log privacy | Service `security_resilience_postgres_test.go`; real integration audit/correlation captures and projection assertions |
| Independent intelligence defaults and immutable safety fields | `TestPR08TXSEFixturePreferenceIsolationAndIndependentFailure` (explicit test consumer, real preference RPC) |
| Closed typed unions, bounded numbers/lists/text, unknown/authority fields | Six canonical fuzz targets and two MCP fuzz targets, plus aggregate-size/JSON regression tests |

The report enumerates the actual passing tests and required skips; the table is
an index of their owning suites, not a replacement for execution evidence.
