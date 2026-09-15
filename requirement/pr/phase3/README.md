# CEERAT Phase 3 preference-domain PR plan

Phase 3 implements customer-owned portable preferences for ChatGPT, Codex, and
compatible MCP clients. The canonical requirement is
[`../../pref.md`](../../pref.md).

Phase 3 also prepares this domain for the new TXSE Intelligence direction in
[`../../txse_developer_platform.md`](../../txse_developer_platform.md). This is
an accommodation boundary, not a TXSE data implementation: preferences may
shape bounded presentation/query defaults but never market truth, entitlement,
health, classification, formulas, or warnings.

## Dependency order

| Order | PR | Primary repository | Outcome |
| --- | --- | --- | --- |
| 1 | [OAuth scopes](01-preference-oauth-scopes.md) | `infra`, `apps-repo` metadata | Implemented locally; register read/write scopes and consent policy, then complete live reconciliation |
| 2 | [gRPC contract](02-preference-grpc-contract.md) | `contracts-repo` | Implemented locally; typed, protected, self-scoped contract and inventories pass |
| 3 | [Database foundation](03-preference-storage.md) | `services-repo` | Add migrations, constraints, seed catalog, preflight, and repositories |
| 4 | [Read service](04-preference-read-service.md) | `services-repo` | Implement self-scoped get/list/context/definition reads |
| 5 | [Write service](05-preference-write-service.md) | `services-repo` | Implement preview, confirmed idempotent mutation, history, and reconciliation |
| 6 | [MCP read tools](06-preference-mcp-read-tools.md) | `apps-repo` | Expose bounded preference discovery and read tools |
| 7 | [MCP write tools](07-preference-mcp-write-tools.md) | `apps-repo` | Expose durable prepare/confirm/status flows |
| 8 | [Security and resilience](08-preference-security-integration.md) | all implementation repositories | Prove privacy, isolation, concurrency, failure, and deployment boundaries |
| 9 | [Live acceptance and freeze](09-preference-live-acceptance.md) | `infra`, builder docs | Validate ChatGPT/Codex and freeze Phase 3 evidence |

Merge and deploy in this order. A later PR may begin locally after its dependency
passes, but it must not be exposed publicly until the required contract,
database, service, OAuth, and gateway versions are live and verified.

## Frozen architecture

```text
AI host -> HTTPS MCP + user OAuth -> ceerat-agent-gateway
        -> authenticated private gRPC -> preference.PreferenceService
        -> ceerat-user-service preference module -> PostgreSQL
```

`PreferenceService` is a domain contract/module, not another deployable binary.
No REST, browser, legacy AI tool, generic AI API, direct database caller,
compatibility alias, fallback, feature flag, or dual path belongs in Phase 3.

## Canonical public tools

```text
preferences_context
preferences_list
preferences_get
preferences_definitions
preferences_operation_status
preferences_upsert_prepare
preferences_upsert_confirm
preferences_delete_prepare
preferences_delete_confirm
```

There are no parallel direct upsert/delete tools. Public inputs never accept
customer/user/tenant/role/scope identity. The two OAuth scopes are
`ceerat.preferences.read` and `ceerat.preferences.write`.

## Cross-cutting release blockers

- External OAuth terminates at the gateway; private gRPC uses authenticated
  workload/user context and repeats RBAC and ownership enforcement.
- Definitions are server-owned and immutable through customer MCP.
- Values are closed typed unions; reuse canonical exact money and avoid
  arbitrary JSON and floating-point identity/hash behavior.
- Customer-authored strings are untrusted data, never executable instructions.
- Context reads are category-bounded and minimized.
- Writes use preview, explicit confirmation, optimistic versions, durable
  idempotency, and operation-status reconciliation. Unknown writes are never
  blindly retried.
- Logs/errors/evidence exclude values, notes, names, queries, summaries, page
  tokens, raw idempotency keys, prompts, credentials, and request bodies.
- Explicit migrations and preflight precede the dependent service binary.
- Hosted MCP schemas are versioned/refreshed and verified live after changes.
- TXSE-oriented definitions are curated typed settings with declared consumer
  domain; opaque instrument/watchlist references are resolved only by the TXSE
  owner. No FEED, reconstructed book, signal history, positions, or suitability
  data enters preference storage.
- Preference-context failure cannot fail TXSE ingest/recovery/book publication;
  the intelligence caller uses documented defaults and preserves health,
  freshness, provenance, entitlement, and classification controls.

## Required builder workflow

Every PR must use `ceerat-platform-builder-agent` for context, ownership,
security, architecture, RBAC, inventory, and drift:

```text
ceerat-builder check-context
ceerat-builder codex-context --output json
ceerat-builder evidence request "Phase 3 customer-owned preferences MCP" --output json
ceerat-builder patterns grpc-security --output json
ceerat-builder rbac check --output json
ceerat-builder check apps --output json
ceerat-builder check drift --output json
```

Contract/app PRs run the relevant impact, app-context, and
contract-and-service verification commands in their documents. Builder output
does not authorize generic CRUD or a new service deployment.

## Documentation discipline

After every PR, update its affected source-of-truth contract/service/app
inventory and documentation. Update durable platform-builder standards after
automated behavior is validated; record live completion only after human
ChatGPT/Codex acceptance. Evidence contains commit/version/request IDs and
PASS/FAIL results, never actual preference contents.

## Definition of done

Phase 3 closes only after PR 09 proves the full OAuth MCP -> private gRPC ->
service -> PostgreSQL path with two customers, both supported AI clients,
create/read/context/update/delete, replay/conflict, unknown-outcome
reconciliation, privacy/redaction, token refresh/revocation, rate limiting, and
cleanup—without any parallel preference implementation.
