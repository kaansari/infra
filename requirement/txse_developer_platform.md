# CEERAT TXSE Developer Platform — Product and Technical Direction

## 1. Purpose

This document defines the proposed TXSE market-data product and how it fits the CEERAT platform established during the identity-focused Phase 1.

CEERAT is not initially a retail trading application, broker, exchange member, order router, or custodian. The proposed product is a developer- and agent-facing data service that hides exchange feed, normalization, history, replay, and entitlement complexity behind stable APIs.

> Reliable, licensed TXSE data through one CEERAT integration—for software developers and user-authorized AI assistants.

This is a directional requirement, not proof that CEERAT has permission to consume or redistribute TXSE data. Data licensing is the first commercial gate.

## 2. Business thesis

The initial customer is a fintech, research team, financial-software company, or smaller financial institution that needs market data without operating exchange connectivity and feed infrastructure.

```text
Without CEERAT:
exchange connectivity -> decoder -> sequence recovery -> normalization
-> order-book state -> historical storage -> replay -> customer API

With CEERAT:
customer software -> gRPC/WebSocket -> CEERAT market-data services
customer + AI chat -> OAuth + MCP    -> CEERAT market-data services
```

Both paths use the same authoritative domain services, authorization rules, entitlements, metering, and audit controls. MCP is an additional customer interface, not a separate business implementation.

### Product priorities

1. **Licensed** — access, storage, redistribution, display/non-display, and derived-data rights are documented before commercial launch.
2. **Reliable** — sequence integrity and correct normalized data take priority over analytics or AI explanations.
3. **Simple** — a developer should reach a first successful sandbox call in minutes.
4. **Developer-first** — stable gRPC/WebSocket contracts, documentation, credentials, usage reporting, and SDKs.
5. **Agent-native** — user-authorized assistants receive a bounded MCP tool surface over the same backend.
6. **Intelligent** — anomaly detection and explanations sit on authoritative data and remain distinguishable from observed facts.

## 3. CEERAT platform direction

CEERAT has two public integration styles:

| Interface | Consumer | Authentication | Best suited for |
| --- | --- | --- | --- |
| gRPC/WebSocket | Customer software | OAuth workload/user credentials or scoped API credentials, as appropriate | Typed queries and streaming |
| Remote MCP | ChatGPT, Codex, and compatible assistants | User-delegated OAuth authorization code with PKCE | Tool discovery and user-authorized actions |

```text
Chat user
   |
AI host (ChatGPT/Codex/other MCP client)
   | HTTPS MCP + user OAuth bearer token
ceerat-agent-gateway
   | authenticated private gRPC
CEERAT domain service
   | ownership + policy + validation + persistence
CEERAT stores / licensed upstream data
```

The public gateway owns protocol adaptation, discovery, external token validation, coarse scope checks, safe response shaping, and gateway abuse controls. Domain services remain authoritative for ownership, entitlements, validation, business policy, concurrency, and persistence.

### Legacy AI-tool retirement

The direct AI tools previously exposed by `ceerat-agent-service` are legacy and are not the target public integration. Their capabilities will move to remote MCP.

- Do not add new public tools to the legacy surface.
- Do not require new MCP tools to mirror legacy agent/customer inventories.
- Exclude deprecated legacy inventories from active consistency gates once the builder inventory distinguishes `active` from `deprecated`.
- Retain legacy definitions temporarily only for migration, rollback, or reference, with an owner and removal condition.
- Confirm production traffic and consumers before removing any path.

The desired end state has two supported public integration paths:

```text
AI host -> remote MCP -> ceerat-agent-gateway -------+
                                                      |
Developer application -> CEERAT API gateway ---------+
                                                      v
                                          authenticated private gRPC
                                                      |
                                             gRPC security/RBAC
                                                      |
                                             CEERAT domain services
                                                      |
                                              databases/backends
```

The developer platform includes the developer portal, application/client
registration, credentials, API documentation, sandbox access, usage and quota
visibility, and gRPC/WebSocket APIs exposed through the CEERAT API gateway. The
API gateway and agent gateway are separate protocol edges over the same domain
services; neither gateway owns domain data or bypasses service authorization.

Builder drift checks should validate the active MCP inventory. Stale legacy entries are migration debt, not the canonical product contract.

## 4. Phase 1 foundation and status

Phase 1 establishes identity and safe account operations before CEERAT publishes jobs, skills, applications, or market-data tools.

The deployed development integration has demonstrated:

- public remote MCP discovery from Codex and ChatGPT;
- OAuth authorization-code login with PKCE;
- bearer tokens on protected MCP requests;
- current-user and authentication-status queries;
- customer-profile read and confirmed low-risk update;
- connection listing, revocation, and logout;
- typed schemas, request IDs, and agent-actionable errors;
- public MCP backed by private gRPC services.

This proves the integration direction but does not close the full security milestone. The dependency-ordered work lives in [`../pr/README.md`](../pr/README.md):

| PR | Outcome |
| --- | --- |
| 01 | Strict gateway contracts and correct authentication-status behavior |
| 02 | Truthful connection/access-token lifecycle and `is_current` |
| 03 | Keycloak OAuth/OIDC client and policy hardening |
| 04 | Negative tests for token validation and per-tool scopes |
| 05 | Session-aware logout and connection revocation |
| 06 | Prepare/confirm profile-write safety and replay/conflict tests |
| 07 | Rate limiting and safe audit controls |
| 08 | Live two-user and credential-revocation acceptance |
| 09 | Evidence, documentation synchronization, and Phase 1 freeze |

PRs 01–07 are implemented. PR 08 has eleven passing Codex checks and eight
explicit human/operator checks remaining. PR 09 freezes the release candidate,
but Phase 1 is complete only when those remaining checks pass and the milestone
tag is created. A successful development login is not production security
sign-off.

Phase 1 includes identity, self-profile, agent connections, OAuth, scopes, safe errors, auditability, and abuse protection. It excludes jobs, skills, applications, TXSE data, account deletion, brokerage, and Kubernetes. TXSE work builds on the frozen identity boundary; it does not widen Phase 1.

## 5. Identity and authorization

An AI host must not receive a shared CEERAT platform key. Each user connects their own CEERAT account through OAuth and grants explicit scopes. Protected calls carry the resulting bearer access token. OAuth supplies delegated, revocable consent; the bearer token is the credential used afterward.

The gateway validates at least signature and algorithm, issuer, audience/resource, expiration, not-before time, subject, required scope, and applicable session/revocation policy.

The model must never supply a `user_id`, `customer_id`, tenant, role, scope, or connection owner to gain authority. Identity and ownership derive from validated credentials and server-side records.

The external token terminates at the gateway. Internal calls use authenticated workload identity and trusted identity context. Services must not trust arbitrary gRPC metadata.

Authorization and approval are separate. Consequential operations must use prepare/confirm where appropriate. Prepared actions bind subject, normalized inputs, policy decision, expiry, and a single-use or replay-safe identifier. An uncertain write result must not invite blind retries.

## 6. Agent-compatible contracts and errors

Every MCP tool publishes a closed, typed schema with descriptions, required fields, bounds, enums, and defaults where appropriate. Unknown fields and malformed nested values fail before execution. No-argument tools reject unexpected arguments.

Errors must safely tell an assistant whether to correct the request, ask the user, authenticate, obtain consent/entitlement, wait, retry, or stop.

```json
{
  "ok": false,
  "error": {
    "code": "INSUFFICIENT_SCOPE",
    "message": "This operation requires an additional permission.",
    "category": "authorization",
    "retryable": false,
    "user_action_required": true,
    "required_scopes": ["ceerat.market.history.read"],
    "correct_arguments": null,
    "operation_state": "not_started",
    "request_id": "req_..."
  }
}
```

Public errors may include a stable code/category, safe message, retryability and bounded retry delay, required user action, scopes/entitlements, safe validation paths, operation state, and request ID.

They must not expose tokens, secrets, passwords, raw upstream responses, stack traces, SQL, private addresses, topology, or cross-customer data. Sanitized internal diagnostics correlate through the request ID.

## 7. Proposed TXSE product surface

Subject to licensing, capabilities include symbol/reference discovery, latest quotes, recent trades, streams, current/historical books, historical data, replay, derived aggregates, anomalies, and explanations that separate observations, calculations, and model interpretation.

Illustrative gRPC/WebSocket surface:

```text
MarketDataService.SearchSymbols(...)
MarketDataService.GetQuote(...)
MarketDataService.ListTrades(...)
MarketDataService.GetOrderBook(...)
MarketDataService.GetTradeHistory(...)
WSS /api/v1/market/stream
```

Illustrative MCP surface:

```text
search_market_symbols
get_market_quote
list_market_trades
get_market_orderbook
get_market_history
list_market_anomalies
explain_market_anomaly
```

Names remain provisional until rights, use cases, and canonical domain contracts are validated. Native WebSocket remains the streaming interface unless MCP client support makes an MCP stream operationally sound.

| Class | Examples | Default control |
| --- | --- | --- |
| Low-impact read | Quote, symbol lookup | Scope + entitlement + rate limit |
| Costly/bulk read | Long history, replay, export | Scope + entitlement + quotas/cost bounds |
| Derived/model output | Anomaly explanation | Provenance + uncertainty + factual grounding |
| Consequential mutation | Purchase, subscription, future order action | Prepare/confirm + policy + audit; defer unless required |

Bound symbols, time ranges, pages, book depth, subscriptions, concurrent streams, and export volume. Server-side entitlements override model requests.

## 8. Target architecture

```text
Licensed TXSE/vendor feed or approved replay data
                  |
       ingest + decoder + sequence checks
                  |
          normalized event stream
             /           \
  real-time/book state   historical writer
             \           /
              market-data service
                       |
             authenticated private gRPC
                       |
                gRPC security/RBAC
                  /             \
                 /               \
       CEERAT API gateway    MCP agent gateway
          /           \              |
       gRPC         WebSocket     remote MCP
         |              |             |
 developer apps      data apps      AI hosts
```

### Responsibilities

**Ingest/decoder:** use approved transport, decode canonical events, preserve timestamps, detect duplicates/order/gaps/reconnects, and retain raw data only when permitted.

**Real-time processor:** preserve per-symbol ordering, maintain bounded state and reproducible snapshots, produce data-quality metrics, and contain corrupt partitions.

**Historical storage:** evaluate PostgreSQL/TimescaleDB using measured volumes; define numeric precision, partitions, indexes, retention, compression, replay, and deletion around contractual rights.

**Market-data service:** own query semantics, data ownership, entitlements,
plans, pagination, validation, and usage accounting; expose private gRPC and
stable domain errors.

**gRPC security/RBAC boundary:** authenticate calling workloads, propagate only
trusted subject/customer context, authorize service methods, and preserve
defense in depth inside domain services. Network reachability alone never grants
authority.

**CEERAT API gateway:** expose the developer gRPC/WebSocket surface,
authenticate customers and applications, translate public contracts into
private gRPC, and enforce edge limits, heartbeat, reconnect, backpressure, and
gap semantics.

**MCP gateway:** translate bounded tools to domain calls, derive identity from OAuth, avoid duplicating market logic, and return timestamps, freshness, provenance, and partial-data warnings.

## 9. Canonical data model

Define versioned objects for `Instrument`, `Trade`, `Quote`, `OrderEvent` where licensed, `OrderBookSnapshot`, `FeedHealth`, `SequenceGap`, `AggregateMetric`, and `Anomaly` with evidence/detector version.

Every event carries source, schema version, exchange timestamp, ingestion timestamp, sequence identity where available, and data-quality state. Responses state whether data is real-time, delayed, simulated, replayed, incomplete, or stale.

Book reconstruction begins with a verified snapshot and ordered deltas. A missing sequence invalidates the affected book until recovery; guessed state is never presented as authoritative.

## 10. Licensing and entitlements

Obtain written answers for:

1. permitted feeds and test/certification environments;
2. connectivity and approved-provider requirements;
3. internal-use and external-redistribution rights;
4. gRPC, WebSocket, MCP, bulk, display, and non-display treatment;
5. historical storage and redistribution;
6. derived-data and AI-analysis rights;
7. downstream agreements and identity requirements;
8. entitlement, usage reporting, attribution, and audit obligations;
9. delayed-data requirements;
10. data, connectivity, certification, and redistribution fees;
11. retention/deletion obligations;
12. incident and compliance-review obligations.

An authoritative entitlement module maps customer and credential to datasets, symbols, depth, latency class, history, usage, and redistribution mode. OAuth scopes express operation categories; they do not replace commercial entitlements.

## 11. Security and operations

- Require TLS for public interfaces and authenticated internal traffic.
- Keep secrets in deployment secret stores, never Git, examples, logs, or responses.
- Apply least privilege, rotation, expiry, and revocation to user/workload credentials.
- Rate-limit by subject, customer, credential, operation, and costly query dimensions.
- Audit actor, client, operation, target class, decision, result, request ID, and safe reason—never credentials.
- Isolate customer data, queries, entitlements, usage, and saved artifacts.
- Fail closed when identity, entitlement, feed integrity, or ownership is uncertain.
- Treat model output as untrusted presentation, not market fact or policy input.
- Do not imply a trading recommendation or execution workflow from anomaly output.

Development may use direct Go deployment, managed services, and approved simulation/replay. Kubernetes is not required during development.

## 12. Reliability and observability

Monitor feed/heartbeat state; gaps, duplicates, and recovery; event and delivery latency; stream lag; storage failures; quote/book freshness; API availability; WebSocket backpressure/reconnects; entitlement/rate-limit/OAuth failures; MCP outcomes; and reconciliation correctness.

Health must distinguish process health from data readiness. A running service with stale or gapped data is not ready to serve authoritative results.

## 13. Testing and acceptance

### Data correctness

- Golden vectors for decoded messages and fuzz tests for malformed inputs.
- Duplicate, out-of-order, gap, reconnect, and rollover scenarios.
- Deterministic snapshot-plus-delta reconstruction and replay.
- Reconciliation against an approved reference source where permitted.

### APIs and streams

- Contract tests across public gRPC, WebSocket, private gRPC, and MCP projections.
- Pagination, time boundaries, freshness, and partial-data behavior.
- Subscription, reconnect, backpressure, slow-consumer, and measured load tests.

### Identity and isolation

- Missing, malformed, expired, wrong-issuer/audience, and revoked tokens.
- Insufficient scope versus insufficient commercial entitlement.
- Two-user and two-customer isolation.
- Attempts to select another identity through model-controlled fields.
- Rotation/revocation and secret/PII/topology leakage checks.

### LLM/MCP acceptance

1. Discover only intended active tools.
2. Complete OAuth and identify the correct user.
3. Request an entitled quote/history operation.
4. Verify missing scope and entitlement produce distinct safe guidance.
5. Reject unknown/out-of-range arguments before execution.
6. Clearly label stale, gapped, simulated, or replayed data.
7. Revoke the connection and reject subsequent calls.
8. Confirm legacy `ceerat-agent-service` tools are absent.

Chat testing is acceptance evidence, not a replacement for deterministic security and data tests.

## 14. Roadmap and gates

### Gate A — Finish identity

Complete Phase 1 PRs 02–09 and freeze the OAuth/MCP boundary. TXSE discovery may proceed in parallel, but TXSE tools must not bypass unfinished controls.

### Gate B — Validate business and rights

Interview 15–25 prospects, recruit 3–5 design partners, document licensing/entitlements/fees, and stop or reshape the product if rights or economics fail.

### Gate C — Prove feed feasibility

Using approved data, define schemas, decode required events, demonstrate sequencing/replay/reconciliation, and measure throughput, latency, storage, and cost.

### Gate D — Developer API pilot

Implement the domain service, minimal public gRPC and WebSocket surfaces,
credentials, entitlements, limits, metering, documentation, and design-partner
onboarding.

### Gate E — MCP pilot

Project a small read-only subset through the gateway. Begin with symbol search, quote, and bounded recent trades/history. Reuse Phase 1 OAuth, errors, connections, scopes, and audit controls. Validate with distinct Codex/ChatGPT users and entitlements.

Do not begin with bulk export, unconstrained history, execution, or an open-ended model-controlled query language.

### Gate F — Expansion

Add books, longer history, anomaly detection, and model explanations only when rights, correctness, and customer demand justify them.

## 15. MVP scope

Include approved data ingestion; normalized symbol/quote/trade schemas; sequence/readiness monitoring; quote/recent-trade APIs; bounded streaming; basic licensed history; identity, credentials, entitlements, rate limits and metering; quickstart documentation; and a small read-only MCP projection after Phase 1 closure.

Defer brokerage, custody, routing, execution, AI-first intelligence, unbounded exports, unnecessary full-depth books, multi-exchange support, Kubernetes, broad SDK coverage, and new legacy `ceerat-agent-service` tools.

## 16. Commercial model

Derive pricing from interviews, measured infrastructure cost, and exchange/provider charges. Potential developer, professional, and enterprise tiers may vary by latency, datasets, history, depth, throughput, streams, retention, SLA, and support. Earlier illustrative prices are not commitments.

Track time to first call, active customers/credentials, delivered usage, paid conversion, margin after data/infrastructure fees, reliability, support burden, retention, and expansion.

## 17. Builder-agent governance

`ceerat-platform-builder-agent` is a development-time source of CEERAT context, security standards, ownership boundaries, inventories, and validation. It is not a runtime anomaly-analysis service and does not sit in the market-data request path.

Before every implementation PR:

```bash
ceerat-builder check-context
ceerat-builder codex-context --output json
ceerat-builder app-context ceerat-agent-gateway --output json
ceerat-builder patterns grpc-security --output json
ceerat-builder docs all --output json
```

Add service-specific context when the market service exists. Validate OAuth termination, workload authentication, service ownership, tenant/entitlement boundaries, model-controlled inputs, error/log redaction, consequential operations, active/deprecated inventories, and preservation of public MCP -> gateway -> private gRPC.

After every PR:

```bash
ceerat-builder check apps --output json
ceerat-builder check drift --output json
```

Run `make verify-platform` for shared contracts, inventories, security boundaries, or deployment changes. Failures must distinguish active product drift from explicitly deprecated legacy inventory.

After merge, deployment, and human validation, update owning documentation and make a focused builder documentation checkpoint for reusable, tested rules. Deployment evidence belongs in `infra`; reusable standards belong in `ceerat-platform-builder-agent`; speculation does not become a standard.

## 18. Immediate actions

1. Complete the PR 08 human/operator acceptance checklist and attach redacted
   evidence to the Phase 1 release candidate.
2. Mark legacy `ceerat-agent-service` inventories deprecated in the builder
   model and focus validation on active MCP surfaces through a separate reviewed
   PR.
3. Create a written TXSE/vendor licensing and entitlement questionnaire.
4. Interview customers and recruit design partners.
5. Obtain approved specifications and sample/certification/replay data.
6. Draft the canonical event schema and minimal read-only API contract.
7. Prototype decoding, sequence recovery, and reconciliation before AI explanations or a broad portal.

The governing principle is: make licensed market data easy to consume without moving correctness, identity, entitlement, or customer policy decisions into an LLM.
