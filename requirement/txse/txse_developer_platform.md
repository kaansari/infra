# CEERAT TXSE Intelligence Platform — Product and Technical Direction

Status: canonical direction

Sources: `TXSE_Intelligence_Platform_Project_Plan_v1.1_UAT.md` and `docs/txse/`

Interfaces: public gRPC, WebSocket, and MCP; private authenticated gRPC

## 1. Direction

CEERAT will build an intelligence platform around TXSE FEED, deterministic
recovery/replay, reconstructed market state, versioned analytics, evidence-backed
signals, and agent-native access. It consists of a restricted raw Exchange Data
plane and a customer-facing Derived Intelligence plane. The first external
product is approved, non-reversible intelligence—not broad raw FEED resale.

TXSE UAT is the primary pre-production environment. Production connectivity is
purchased only after explicit recovery, book-correctness, compliance, and soak
gates pass. This replaces the earlier quote/trade-API-first TXSE concept. Phase 1
identity, Phase 2 commerce, and Phase 3 preferences remain reusable foundations,
but do not own TXSE market truth.

## 2. Binding source constraints

- Production is at NY6 and DR at DA11; VPN/cloud is test/certification only.
- FEED uses five units and redundant A/B multicast. Logical feed IDs are not
  `matchingEngineId` or `streamId`; daily reference data is authoritative.
- Bounded gaps use TCP Rewind; bootstrap/major recovery uses SILO Snapshot.
- Decoders must support FEED presence-bit/trailing-field extensibility and fail
  closed on unsupported protocol versions without silently corrupting state.
- Canonical coverage includes session/symbol status; displayed order lifecycle;
  displayed executions; non-displayed trades/breaks; and auction preamble,
  band-window, extension, and print semantics.
- Records of receipt, use, display, and distribution are retained for at least
  three years, or longer when required.
- Systems, external outputs, and material changes remain within a TXSE-approved
  System Description. CEERAT cannot self-approve a “Derived Data” label.

The UAT plan mentions REST, but CEERAT adapts that recommendation to its frozen
boundary: gRPC for typed queries, WebSocket for streaming, and MCP for AI hosts.
No REST compatibility or parallel backend is introduced.

## 3. Product boundary

> Evidence-backed TXSE intelligence without requiring customers or authorized
> AI assistants to build exchange-feed infrastructure.

| Class | Contents | Default exposure |
| --- | --- | --- |
| Raw Exchange Data | packets, decoded events, order book | internal or separately approved/entitled |
| Analytics | depth, imbalance, velocity, withdrawal/replenishment, auction metrics | candidate Derived Data; approval required |
| Intelligence | anomaly/regime signals, confidence, evidence, explanations | primary external product after approval |
| AI projection | bounded MCP tools over intelligence contracts | delegated, entitled, and audited |

MVP excludes order entry/execution, brokerage, custody, personalized investment
advice, consolidated-NBBO claims without other licensed sources, unrestricted
raw redistribution, LLM computation of market truth, REST, browser backends,
legacy AI tools, compatibility aliases, fallbacks, and dual implementations.

## 4. Architecture and ownership

```text
TXSE FEED 1-5 A/B
 -> edge ingest -> immutable raw archive
 -> sequence/duplicate merge -> Rewind or SILO recovery
 -> versioned decoder -> canonical MarketEvent stream
 -> reference + book + trades + auction
 -> metrics -> signals -> evidence-backed Intelligence
 -> txse-intelligence-service (private gRPC authority)
      -> CEERAT API gateway -> public gRPC/WebSocket
      -> ceerat-agent-gateway -> public HTTPS MCP
 -> entitlement + usage + compliance ledger

PreferenceService in ceerat-user-service
 -> bounded customer presentation/query defaults only
```

`txse-edge-ingest` owns sockets, timestamps, raw envelopes, and transport
telemetry. `txse-recovery` owns gaps, Rewind, SILO, buffering, and catch-up.
`txse-feed-decoder` owns framing-aware spec-versioned decoding. `txse-reference`
owns effective-dated mappings. `txse-book`, `txse-trades`, and `txse-auction`
own deterministic state. `txse-metrics` and `txse-signals` own versioned
calculation and evidence. A new `txse-intelligence-service` owns query contracts
and safe projections. The gateways only authenticate, authorize, meter, and
adapt; they own no market logic.

External OAuth terminates at a public gateway. Private calls use workload
identity and integrity-protected user/tenant context. Each service repeats RBAC,
entitlement, ownership, deadline, and classification checks. Public inputs never
select trusted identity, role, scope, environment, source feed, or data class.

## 5. Events, health, and intelligence

Every canonical event carries environment, FEED unit/side, engine/stream,
exchange/receive/decode timestamps, session/sequence, symbol, raw/canonical type,
decoder version, and recovery/replay correlation.

```text
INITIALIZING -> SNAPSHOT_LOADING -> CATCHING_UP -> LIVE
LIVE -> GAP_DETECTED -> RECOVERING -> LIVE
RECOVERING -> DEGRADED -> SNAPSHOT_LOADING
```

Authoritative book-derived output is suppressed while required state is
untrusted. Every response/update carries environment, as-of time, freshness,
health, completeness, and degradation/recovery warnings.

Initial signals are depth imbalance, liquidity withdrawal/replenishment,
execution velocity, hidden/non-displayed-liquidity ratio, and auction pressure.
Each has versioned formulas, units, windows, baselines, confidence, evidence,
health requirements, and replay tests. LLMs explain bounded evidence only; they
cannot invent causation, hide degradation, or describe a TXSE-only view as the
whole market.

## 6. Public interfaces

Illustrative gRPC operations are `GetSymbolIntelligence`,
`ListUnusualActivity`, `GetLiquidityAnalysis`, `GetAuctionIntelligence`,
`GetHaltState`, `GetSignal`, `ListHistoricalSignals`, and
`ExplainSignalEvidence`.

WebSocket publishes entitled intelligence updates with bounded subscriptions,
resumable cursors, heartbeats, backpressure, and explicit gap/reset semantics.
It is never a raw FEED tunnel.

Initial MCP tools use a flat `txse_` namespace and
`ceerat/domain: txse_intelligence`:

```text
txse_get_symbol_intelligence
txse_get_unusual_activity
txse_get_liquidity_analysis
txse_get_auction_state
txse_get_halt_state
txse_explain_signal
```

Schemas are closed/bounded. Responses include request ID, operation state,
timestamps, provenance, health, classification, and safe actionable errors.
Any future raw tools require distinct contracts, scopes, product entitlement,
audit classification, TXSE approval, and hosted-app review—not aliases.

## 7. Preference-engine accommodation

Phase 3 preferences may hold curated, typed choices such as preferred signal
families, explanation detail, default time window, alert-severity threshold,
presentation units, and bounded references to instruments/watchlists. Relevant
definitions declare consumer domain `txse_intelligence`.

```text
explicit current request
 > entitlement and server policy
 > health, quality, and classification controls
 > saved preferences
 > service defaults
```

Preferences cannot grant access, choose UAT/PROD/DR, suppress provenance,
freshness, health, risk, or licensing warnings, change formulas, authorize
trades, or represent holdings/suitability. Instrument/watchlist IDs are opaque
references validated by their owning domain; PreferenceService never ingests
FEED or dereferences market IDs. Customer-authored text remains untrusted data,
never system/developer instruction.

An intelligence service may request minimized self-scoped preference context
over authenticated private gRPC, or an AI host may call `preferences_context`
before a TXSE tool. Category, consumer purpose, and result size are mandatory
and audited. TXSE ingest/recovery/book availability never depends on preferences.

## 8. Entitlement, compliance, and errors

- OAuth scopes and product/data entitlements are independent; a scope alone is
  never permission to receive Exchange Data.
- Server-enforce symbol, window, history, rate, concurrency, and size limits.
- Classify every field by source, raw/derived status, time basis, use,
  distribution, retention, formula version, and required grant.
- Audit pseudonymous actor/tenant, product, entitlement, endpoint/tool, data
  class, time basis, formula version, outcome, request ID, and safe counts.
- Never log tokens, exchange credentials, packet bodies, reconstructable data,
  preference values, prompts, or customer content.
- Block unreviewed fields, formulas, tools, routes, external uses, and material
  System Description changes; provide emergency tenant/product/output disable.
- Errors include safe code/category/message, retryability/delay, operation state,
  request ID, safe violated rule/dependency class, and next action. They exclude
  topology, multicast/recovery credentials, SQL, raw data, and foreign identity.

## 9. Storage, replay, and observability

Use encrypted immutable raw object archives; an ordered replayable canonical
stream; integrity-checked book snapshots; and measured Postgres/Timescale stores
for reference, trades, metrics, signals, and compliance. Preference data remains
in CEERAT PostgreSQL, outside TXSE raw/event storage. Live and replay paths share
the decoder/book implementation and produce stable events and book hashes.

Observe A/B divergence, duplicates, gaps, Rewind/SILO, decoder unknowns,
reference age, event lag, book hashes/health, storage/backpressure, metric/signal
lag, WebSocket gaps, OAuth/RBAC/entitlement denials, MCP outcomes, compliance
ledger health, and preference minimization. Silent recovery or stale-data
downgrade is release-blocking.

## 10. UAT-first gates

1. **Legal/access:** Data Recipient, System Description, FEED/Rewind/SILO/
   reference access, certification cases, network path, and external-output
   classification path.
2. **Raw truth:** FEED 1–5 A/B, archive-before-decode, sequence merge, reference
   mapping, golden decoders, deterministic replay.
3. **Recovery/book:** injected Rewind recovery, empty-start SILO recovery,
   invariants, stable hashes, and fail-closed health publication.
4. **History/contracts:** replay reconciliation, measured cost/latency,
   authenticated internal gRPC/WebSocket, and 24-hour soak.
5. **Intelligence:** five backtested signals, evidence/confidence,
   false-positive review, and non-reversibility assessment.
6. **Customer/MCP:** entitled public gRPC/WebSocket/MCP, metering, audit,
   constrained explanations, sandbox docs, and safe preference defaults.
7. **Production/beta:** certification, approved System Description, network/DR,
   chaos/capacity/security/runbooks, then controlled 30-day live beta.

UAT acceptance requires repeatable A/B receipt/capture; decoder/replay/book-hash
determinism; working Rewind and SILO; chaos and soak evidence; historical
reconciliation; five reviewed signals; authenticated/entitled/audited public
interfaces; two-customer isolation and token lifecycle; redaction; and proof
that preferences cannot override explicit requests, entitlement, health,
classification, or warnings.

## 11. Existing milestones and governance

Phase 1 established OAuth MCP, PKCE/refresh, structured errors, private gRPC,
and authorization-server revocation. Phase 2 established catalog/cart/order,
prepare-confirm safety, idempotency/reconciliation, migrations/preflight, and
live clients. Commerce `Product` is not a TXSE instrument. Phase 3 provides
portable preferences and must follow the safeguards above without blocking the
TXSE data plane.

Use `ceerat-platform-builder-agent` for owner evidence, contracts, gRPC
security/RBAC, app surfaces, impact, and drift on every PR. Current evidence
finds no TXSE owner, so define a new explicit intelligence owner rather than
letting keyword matching place it in `ceerat-user-service`. Builder output is
evidence, not authority for generic CRUD, public gRPC methods, REST, or aliases.
After validation, update contract/service/app inventories and durable builder
architecture, security, compliance, logging, AI-tool, and testing standards.

## 12. Immediate actions

1. Confirm Data Recipient and submit/update the System Description for UAT,
   internal non-display processing, storage, derived outputs, gRPC/WebSocket/MCP,
   AI explanation, and entitlement.
2. Request current FEED framing, UAT 1–5 A/B, Rewind, SILO, reference data,
   test-symbol, and certification material.
3. Obtain written classification, non-reversibility, MCP/LLM delivery,
   reporting, and fee answers for representative outputs.
4. Create canonical protobuf/events, environment-separated configuration, raw
   capture, decoder fixtures, replay tooling, and observability.
5. Demonstrate capture -> decode -> deterministic replay before UI or production
   connectivity spend; define the five signal specs and compliance dictionary.
