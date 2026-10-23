**TXSE INTELLIGENCE  
PLATFORM**

Technical architecture, phased implementation roadmap, compliance plan, and next-action checklist

| **Version**           | 1.1                                                                                                                                                                                       |
|-----------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Date**              | September 2026                                                                                                                                                                            |
| **Primary objective** | Build a TXSE market-intelligence platform around FEED, recovery services, derived analytics, APIs/WebSockets, and MCP.                                                                    |
| **Planning basis**    | TXSE FEED specification plus the uploaded Connectivity Manual, Market Data Agreement, Market Data Policies, Exchange Data Order Form/System Description, and September 2026 Fee Schedule. |

**Recommended starting point:** UAT-first, derived-intelligence-first. Treat TXSE UAT as the primary build environment for the full pre-production platform: ingest, decoding, replay, order-book reconstruction, recovery, historical storage, intelligence signals, APIs/MCP, compliance logging, and operational runbooks. Commit to production connectivity only after the UAT system passes explicit technical and product gates.

# 1. Executive summary

The project should be treated as two products sharing one exchange-data core: (1) a tightly controlled raw market-data infrastructure layer and (2) a higher-value intelligence layer that converts TXSE FEED events into proprietary metrics, signals, anomaly scores, auction analytics, and natural-language explanations. The external commercial focus should initially be the intelligence layer, not broad resale of raw FEED.

| **Decision**                 | **Recommended direction**                                          | **Why**                                                                                                                                               |
|------------------------------|--------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Market data source**       | TXSE FEED                                                          | Depth-of-book events are the foundation for order-book, execution, liquidity, auction, and anomaly analytics.                                         |
| **Initial environment**      | TXSE UAT                                                           | VPN/cloud is permitted for test/certification, reducing early infrastructure cost and allowing the entire ingest/recovery stack to be proven first.   |
| **Production access**        | Extranet or direct physical connectivity                           | Production/DR cannot be reached by VPN/cloud. Direct connectivity is 10 Gb; an approved extranet may be the simpler first production path.            |
| **Recovery model**           | A/B multicast + TCP Rewind + SILO Snapshot                         | Small gaps are repaired via rewind; restarts/major desynchronization use SILO bootstrap/catch-up.                                                     |
| **External product**         | Derived intelligence first                                         | The policies generally treat non-reversible Derived Data more favorably than raw Exchange Data distribution, subject to TXSE approval and exceptions. |
| **Implementation languages** | Go + protobuf/gRPC; Python only where useful for research/modeling | Matches the desired services architecture and keeps feed/book paths deterministic and low-latency.                                                    |
| **AI role**                  | Explanation and query layer, not primary signal computation        | Market metrics and anomaly detection should be deterministic/statistical; the LLM explains, ranks, and answers natural-language questions.            |

# 2. What the TXSE documents now establish

- **Connectivity:** Primary is Equinix NY6; DR is Equinix DA11. Firms can use local cross-connect, telco circuit, or approved extranet providers. VPN/cloud is for test/certification only, not production or DR.

- **Network:** IPv4 is used; BGP is the preferred unicast routing protocol and PIM-SM is the preferred multicast routing protocol.

- **Market-data transport:** Production FEED is multicast with A/B redundancy and five FEED units plus BALE. Feed identifiers are logical connectivity labels and must not be assumed to match matchingEngineId or streamId.

- **Recovery:** TXSE publishes TCP Market Data Rewind endpoints and SILO Snapshot Service endpoints for FEED units. These should be explicit parts of book-recovery design.

- **Data products:** TXSE FEED contains displayed orders, executions, cancellations, modifications, order IDs, and administrative messages. BALE provides top-of-book plus execution information.

- **Commercial use:** The Order Form requires the recipient to identify internal, display, non-display, controlled external, and uncontrolled external use, and to describe the systems and entitlement methodology.

- **Derived Data:** TXSE defines Derived Data as data created from Exchange Data that cannot be readily reverse-engineered to recreate or substitute for Exchange Data. The policies say such usage is generally not fee liable, subject to exceptions, and distribution still must be described in the System Description.

- **Recordkeeping:** Data recipients must retain complete and accurate records of receipt, use, display, and distribution for at least three years or longer if required.

- **Change control:** Reprocessing and derived services must be described in an approved System Description; material changes require prior TXSE approval of a revised description.

- **Current fees:** September 2026 schedule lists FEED internal/external distribution at \$1,500/\$2,500 per month (waived through Dec. 31, 2026), Multicast FEED Service at \$450/month, primary 10 Gb connectivity at \$6,000/month, and DR 10 Gb at \$3,000/month.

**Planning note:** The project timelines, team estimates, service decomposition, and product decisions in this document are planning recommendations. They are not TXSE commitments and should be validated during onboarding/certification.

# 3. Product definition and scope

## 3.1 Product promise

**TXSE intelligence in minutes, without the customer building exchange feed infrastructure.**

Customers should be able to consume normalized TXSE market state and proprietary market-intelligence signals through REST, WebSocket, SDKs, and MCP. The platform should hide multicast handling, duplicate suppression, sequence gaps, snapshot recovery, order-book reconstruction, historical storage, statistical baselining, and anomaly pipelines.

## 3.2 Product layers

| **Layer**            | **Purpose**                                   | **Example outputs**                                                                                              | **Commercial posture**                                                        |
|----------------------|-----------------------------------------------|------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------|
| **1. Raw Data Core** | Internal truth and approved raw-data products | orders, executions, book state, status, auction events                                                           | Restricted/entitled; treat as Exchange Data unless TXSE approves otherwise.   |
| **2. Analytics**     | Deterministic calculations                    | depth imbalance, liquidity withdrawal, replenishment, spread, hidden-liquidity ratio, auction pressure, velocity | Potential Derived Data if non-reversible and approved.                        |
| **3. Intelligence**  | Actionable signals and explanations           | anomaly score, unusual activity, regime labels, summaries, alert reasons                                         | Primary external product; deliberately avoid reconstructable raw-feed output. |
| **4. AI/MCP**        | Agent-native access                           | get_symbol_intelligence, get_unusual_activity, explain_signal                                                    | Expose intelligence objects first; gate raw tools separately if ever offered. |

## 3.3 MVP non-goals

- No order entry, execution, brokerage, custody, or trading membership dependency in the first release.

- No promise of consolidated NBBO or full U.S. market intelligence unless separate non-TXSE data sources are licensed and integrated later.

- No unrestricted raw FEED redistribution in MVP.

- No LLM-driven book reconstruction or signal computation in the critical path.

# 4. Target architecture

TXSE A/B Multicast (FEED 1-5)  
-\> Edge Ingest / Sequence Merge  
-\> Gap Detector -\> TCP Rewind  
-\> Bootstrap / Major Recovery -\> SILO Snapshot  
-\> FEED Decoder  
-\> Canonical MarketEvent bus  
-\> Book Engine  
-\> Trade/Execution Engine  
-\> Auction Engine  
-\> Status/Reference Engine  
-\> Metrics + Baseline Engine  
-\> Anomaly/Signal Engine  
-\> Intelligence API / WebSocket / MCP  
-\> Historical + Raw Archive + Audit/Entitlement

## 4.1 Service decomposition

| **Service**           | **Responsibility**                                                                                            | **Suggested tech** | **Design note**                                                                              |
|-----------------------|---------------------------------------------------------------------------------------------------------------|--------------------|----------------------------------------------------------------------------------------------|
| **txse-edge-ingest**  | Join A/B multicast groups, timestamp packets, de-duplicate, track sequence continuity, publish raw envelopes. | Go                 | Every downstream service depends on clean sequencing.                                        |
| **txse-recovery**     | Request TCP rewind for bounded gaps; coordinate SILO snapshot + catch-up for restart/desync.                  | Go                 | Must expose recovery state and prevent stale books from being published as healthy.          |
| **txse-feed-decoder** | Decode FEED binary messages into canonical protobuf MarketEvent messages.                                     | Go                 | Version decoder by TXSE specification revision.                                              |
| **txse-reference**    | Load daily reference data and map symbol/matchingEngineId/streamId independently of FEED unit numbering.      | Go                 | Do not hard-code feed-to-engine mapping.                                                     |
| **txse-book**         | Maintain order-level and price-level state; snapshots; integrity checks.                                      | Go                 | Shard by stream/symbol; deterministic replay.                                                |
| **txse-trades**       | Normalize executions/trades/breaks and publish trade-derived metrics.                                         | Go                 | Separate displayed execution lifecycle from non-displayed trade events.                      |
| **txse-auction**      | Track preamble/band-window/auction-print state and derive auction pressure.                                   | Go                 | High-value differentiating product.                                                          |
| **txse-metrics**      | Compute rolling market-microstructure metrics and historical baselines.                                       | Go/Python research | Keep production metric definitions versioned and reproducible.                               |
| **txse-signals**      | Score unusual activity, liquidity events, volatility/order-flow regimes.                                      | Go/Python          | Signal output must be explainable with metric evidence.                                      |
| **txse-api**          | REST/gRPC/WebSocket, tenant auth, rate limits, product entitlements.                                          | Go                 | Separate raw Exchange Data routes from Derived Intelligence routes.                          |
| **txse-mcp**          | Agent-facing tools over intelligence endpoints.                                                               | Go                 | Default to derived intelligence, not reconstructable raw events.                             |
| **txse-compliance**   | Usage ledger, entitlement state, subscriber/device records where applicable, audit exports.                   | Go/Postgres        | Three-year+ retention and TXSE audit readiness.                                              |
| **txse-ai-explainer** | Turn signals/metrics into concise natural-language explanations; no critical-path trading computation.        | LLM worker         | Stateless where possible; store prompt/model/version for reproducibility if customer-facing. |

# 5. Canonical event and state model

The decoder should preserve TXSE semantics but the rest of the platform should depend on a stable internal model. Every event should carry source identity, exchange timestamp, receive timestamp, sequence information, specification version, and a correlation/replay identifier.

- source_environment (UAT / PROD / DR)

- feed_unit and side (A/B/C/D as applicable)

- matching_engine_id and stream_id

- exchange_timestamp_ns

- receive_timestamp_ns

- decode_timestamp_ns

- sequence / session sequencing fields

- symbol / symbol_id

- raw_message_type and canonical event type

- decoder_spec_version

- replayed/recovered flag and recovery correlation ID

Canonical event families:  
SymbolDefined • MarketStateChanged • SymbolStateChanged • OrderAdded • OrderDeleted • OrderReduced • OrderReplaced • OrderExecuted • TradeOccurred • TradeBroken • AuctionProjected • AuctionBandUpdated • AuctionCompleted

## 5.1 Book-health state machine

INITIALIZING -\> SNAPSHOT_LOADING -\> CATCHING_UP -\> LIVE  
LIVE -\> GAP_DETECTED -\> RECOVERING -\> LIVE  
RECOVERING -\> DEGRADED (if bounded recovery fails)  
DEGRADED -\> SNAPSHOT_LOADING (full resync)

Customer-facing order-book and derived metrics should carry a health field. During DEGRADED/SNAPSHOT_LOADING/CATCHING_UP, the platform should either suppress authoritative live-book claims or clearly mark the data as recovering.

# 6. Storage and data lifecycle

| **Data class**         | **Store**                                         | **Policy**                                                                                                       | **Purpose**                                          |
|------------------------|---------------------------------------------------|------------------------------------------------------------------------------------------------------------------|------------------------------------------------------|
| Raw packet/archive     | Object storage                                    | Compressed immutable capture by session/feed/day; encryption and retention policy.                               | Replay, incident analysis, decoder regression tests. |
| Canonical events       | Kafka/Redpanda/NATS JetStream + object archive    | Partition by stream or symbol hash while preserving required ordering.                                           | Real-time fanout and deterministic replay.           |
| Current book           | In-memory per worker + periodic durable snapshots | Keep order-level state and derived price levels.                                                                 | Low latency; quick worker recovery.                  |
| Trades/metrics/signals | Postgres + TimescaleDB                            | Hypertables by time and symbol; compression/retention tiers.                                                     | APIs, baselines, research, billing.                  |
| Reference/config       | Postgres                                          | Effective-dated stream mappings, symbol metadata, spec versions.                                                 | Avoid hard-coded topology assumptions.               |
| Compliance ledger      | Postgres + immutable export/archive               | Tenant, product, entitlement, endpoint class, access time, display/non-display classification, raw/derived flag. | Audit readiness and usage reporting.                 |

# 7. Intelligence model: what to calculate before using AI

### Book/liquidity

- best bid/offer and spread

- depth by configurable bps bands

- bid/ask depth imbalance

- liquidity concentration by price level

- add/cancel/replacement velocity

- liquidity withdrawal and replenishment

- queue/order persistence and churn

### Execution

- displayed execution velocity

- non-displayed trade volume ratio

- price improvement/slippage relative to current TXSE book where computable

- trade-size distribution and burstiness

- execution/book divergence

### Auction

- projected matched-share trend

- excess-side persistence

- upper/lower band buy-vs-sell pressure

- extension-cycle state

- auction pressure score

- pre-auction acceleration

### Regime/anomaly

- rolling z-scores vs symbol/daypart baseline

- spread/depth shock score

- order-flow imbalance score

- cancellation shock score

- hidden-liquidity anomaly score

- halt/resume event context

- composite unusual-activity score

**Design rule:** An LLM may explain a computed signal, but it should not invent the signal from raw ticks. Every explanation should be traceable to explicit metrics, baseline windows, and a signal-definition version.

# 8. API, WebSocket, SDK, and MCP surface

## 8.1 Intelligence-first public API

- **GET /v1/intelligence/{symbol} —** Composite market state, derived metrics, active signals, book-health status, concise explanation.

- **GET /v1/signals —** Ranked unusual-activity events with filters for severity, symbol, signal type, and time.

- **GET /v1/auctions/{symbol} —** Derived auction pressure/state, not a reconstructable raw message dump by default.

- **GET /v1/liquidity/{symbol} —** Depth/imbalance/withdrawal/replenishment metrics.

- **GET /v1/history/signals —** Historical derived signals and metric context.

- **WS /v1/stream/intelligence —** Signal and intelligence updates, tenant-entitled.

- **MCP get_symbol_intelligence —** Agent-oriented version of intelligence endpoint.

- **MCP get_unusual_activity —** Rank current anomalies across TXSE symbols.

- **MCP explain_signal —** Explain one signal using stored evidence/metrics.

## 8.2 Raw-data routes

If raw/near-raw Exchange Data is offered, place it behind a separate product/entitlement boundary with distinct terms, usage logging, and TXSE-approved distribution model. Do not blur raw order-book/trade feeds with Derived Intelligence in the same unrestricted API tier.

# 9. Market-data licensing, compliance, and approval workstream

| **Control**                 | **Implementation**                                                                                                                                                                          |
|-----------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **System Description**      | Describe UAT/prod ingestion, storage, order-book reconstruction, derived analytics, AI/MCP use, external distribution model, entitlements, and non-reversibility controls for Derived Data. |
| **Access classification**   | For every product/endpoint classify internal vs external; display vs non-display; controlled vs uncontrolled distribution; raw Exchange Data vs Derived Data.                               |
| **Entitlements**            | API keys/OAuth tenants, product grants, account status, optional user/device tracking for controlled raw data.                                                                              |
| **Audit logs**              | Immutable or tamper-evident access ledger with at least the TXSE-required retention horizon.                                                                                                |
| **Product review**          | A release checklist that blocks material changes to data use/distribution until TXSE approval is received where required.                                                                   |
| **Derived-data guardrails** | Avoid fields/combinations that let customers readily reconstruct FEED, top-of-book, or a reasonable substitute. Document methodology and get TXSE approval.                                 |
| **Incident response**       | Ability to disable a tenant/product quickly if TXSE directs termination or unauthorized use is detected.                                                                                    |


## 9.1 UAT system strategy

The UAT environment should not be treated as a small connectivity test. It should be the primary engineering environment in which the complete TXSE Intelligence Platform is built and proven before production spend begins.

TXSE's current documents indicate that VPN/cloud connectivity is available for test/certification traffic and that Test Environment logical connectivity is not charged by TXSE. The project should therefore maximize the amount of architecture, recovery testing, analytics validation, API development, and operational testing completed in UAT.

### UAT objective

By the end of the UAT program, the team should have a production-shaped system that can:

- Receive all assigned TXSE UAT FEED multicast units on redundant A/B sides.
- Identify packet loss, duplicates, sequence discontinuities, and feed-side divergence.
- Persist raw packet/session captures with enough metadata for deterministic replay.
- Decode the complete FEED message set required by the platform.
- Load and apply daily symbol, matching-engine, and stream reference mappings.
- Reconstruct a correct order-level and price-level book.
- Recover bounded sequence gaps using TCP Rewind.
- Bootstrap/recover state using SILO Snapshot and catch up safely to live multicast.
- Maintain explicit book-health states and suppress publication when state is not trustworthy.
- Persist canonical events, trades, snapshots, metrics, and operational telemetry.
- Compute and backtest the first Derived Intelligence metrics/signals.
- Expose authenticated internal REST/gRPC/WebSocket and MCP interfaces.
- Produce compliance/audit records showing data source, use, access, and external-output classification.
- Run repeatable failure, restart, recovery, and soak tests.
- Produce evidence for the production go/no-go decision.

### UAT target architecture

```text
TXSE UAT
   |
   +-- FEED 1-5 A
   +-- FEED 1-5 B
   |        |
   |        v
   |   txse-edge-ingest
   |        |
   |        +--> raw packet/session archive
   |        |
   |        v
   |   sequence + duplicate reconciler
   |        |
   |        +--> TCP Rewind client
   |        +--> SILO Snapshot client
   |        |
   |        v
   |   txse-feed-decoder
   |        |
   |        v
   |   canonical protobuf event stream
   |        |
   +--------+----------------+----------------+
            |                |                |
            v                v                v
        txse-book        txse-trades      txse-auction
            |                |                |
            +----------------+----------------+
                             |
                             v
                       txse-metrics
                             |
                             v
                       txse-signals
                             |
                 +-----------+-----------+
                 |                       |
                 v                       v
             Timescale               API / MCP
                                         |
                                         v
                                Analyst validation
```

### UAT work packages

#### UAT-1 — Access, networking, and environment

Tasks:

- Obtain UAT credentials, multicast group assignments, TCP Rewind/SILO access details, and reference-data procedures from TXSE.
- Confirm the supported VPN/cloud connectivity method and any source-IP, routing, firewall, or allow-list requirements.
- Create separate `uat`, `prod`, and `dr` configuration domains from the beginning.
- Provision the initial UAT compute environment.
- Configure secrets management and credential rotation.
- Add network observability for multicast joins, packet rates, dropped packets, socket errors, reconnects, and reachability.
- Validate connectivity to one FEED unit first, then FEED 1-5 A/B.
- Document the complete UAT connection procedure in a runbook.

Deliverable: repeatable deployment that can connect to TXSE UAT and receive assigned FEED traffic.

#### UAT-2 — Raw capture, transport, and sequence integrity

Tasks:

- Capture receive timestamp, source, multicast group, port, feed side, feed unit, datagram length, and sequence metadata.
- Persist raw datagrams/session files before decoding.
- Implement A/B duplicate detection and deterministic merge policy.
- Track expected sequence by applicable transport/stream scope.
- Detect gaps immediately and emit structured gap events.
- Build dashboards for packet rate, duplicates, gaps, out-of-order delivery, and A/B lag.
- Add a replay mode that feeds captured packets through the exact same downstream decoder path.

Deliverable: raw UAT sessions can be replayed and produce deterministic transport-level results.

#### UAT-3 — FEED decoding and reference data

Tasks:

- Implement every FEED message required by the current specification.
- Create golden binary fixtures for each message type.
- Preserve exchange timestamp, receive timestamp, feed identity, and canonical event ID.
- Implement daily reference-data ingestion.
- Never infer `matchingEngineId` or `streamId` from FEED unit number.
- Version the decoder and reference-data schemas.
- Fail safely on unknown/unsupported message versions instead of silently corrupting state.

Deliverable: captured FEED sessions decode into a versioned canonical event stream with regression tests.

#### UAT-4 — Order-book reconstruction

Tasks:

- Implement `AddOrder`, `DeleteOrder`, `ExecuteOrder`, `ExecuteOrderWithPrice`, `ModifySizeDown`, and `ReplaceOrder` semantics.
- Maintain order ID -> order state lookup.
- Maintain aggregated price levels separately from order-level state.
- Validate quantities never become negative.
- Define behavior for unknown order references and duplicate lifecycle events.
- Implement symbol trading-state handling.
- Treat symbol/book state as unavailable until the required initial state has been established.
- Create deterministic book hashes for replay verification.

Deliverable: repeated playback of the same UAT session produces the same final order-book hash.

#### UAT-5 — TCP Rewind recovery

Tasks:

- Implement authenticated/session-aware Rewind connections for each required FEED unit/side.
- Convert gap events into bounded recovery requests.
- Buffer live events safely while recovery is in progress.
- Apply recovered events in exact sequence order.
- Reject overlapping, stale, or inconsistent recovery data.
- Measure recovery duration and number of recovered messages.
- Add maximum-gap/recovery policies that escalate to SILO when bounded recovery is no longer appropriate.

Deliverable: injected packet gaps recover automatically and return the affected book to `LIVE`.

#### UAT-6 — SILO bootstrap and major recovery

Tasks:

- Implement SILO client and authentication/session handling.
- Load a fresh snapshot for each required FEED unit.
- Establish the correct snapshot/catch-up barrier.
- Buffer and replay multicast events arriving during snapshot acquisition.
- Transition book state through `INITIALIZING -> SNAPSHOT_LOADING -> CATCHING_UP -> LIVE`.
- Support `DEGRADED` and `RECOVERING` states.
- Test process restart, machine restart, long disconnect, corrupted local state, and forced resynchronization.

Deliverable: a clean process can start with no local book state, use SILO, catch up, and reach a verified `LIVE` state.

#### UAT-7 — Historical data platform

Tasks:

- Persist canonical events, executions/trades, status changes, auction events, and selected snapshots.
- Implement Timescale/Postgres retention, compression, and indexing.
- Keep raw packet archive separately in object storage.
- Add replay-to-database verification tools.
- Measure daily UAT data volume and extrapolate production storage needs.
- Implement internal historical query APIs.

Deliverable: any selected UAT session can be replayed and reconciled against stored event counts and state.

#### UAT-8 — Intelligence research with financial-data partners

The two financial-data-analysis partners should become part of this phase rather than waiting for production.

Tasks:

- Define the first five signals:
  1. depth imbalance,
  2. liquidity withdrawal/replenishment,
  3. execution velocity,
  4. hidden/non-displayed-liquidity ratio,
  5. auction pressure.
- Define formulas, units, lookback windows, normalizations, and confidence scores.
- Establish symbol/daypart baselines.
- Build replay-based notebooks or analysis jobs in Python where appropriate.
- Separate exploratory analysis code from production deterministic calculations.
- Review false positives and identify misleading interpretations.
- Define the evidence object that accompanies every signal.
- Determine which outputs might expose or allow reconstruction of Exchange Data.
- Produce example JSON payloads for TXSE Derived Data review.

Deliverable: versioned signal specifications plus evidence-backed results from recorded UAT sessions.

#### UAT-9 — Developer APIs and MCP

Tasks:

- Implement authenticated internal REST/gRPC endpoints.
- Add WebSocket streaming for derived signal updates.
- Implement MCP tools focused on intelligence, not raw FEED redistribution.
- Initial MCP tools:
  - `get_symbol_intelligence`
  - `get_unusual_activity`
  - `get_liquidity_analysis`
  - `get_auction_state`
  - `get_halt_state`
  - `explain_signal`
- Keep raw/order-book tools behind internal or separately entitled interfaces.
- Add request/response audit logging.
- Build a small developer sandbox using UAT-derived outputs.

Deliverable: an application or LLM client can query the UAT intelligence platform without direct knowledge of TXSE transport protocols.

#### UAT-10 — Compliance and data-classification controls

Tasks:

- Maintain a data dictionary for every exposed field.
- Mark each field as raw Exchange Data, internal transformation, or candidate Derived Data.
- Record real-time/delayed/historical classification.
- Record display/non-display use.
- Record internal/external exposure.
- Record retention requirement.
- Track the exact version of every derived formula.
- Make audit logs tamper-evident or immutable.
- Prepare sample external payloads for TXSE review before production commercialization.

Deliverable: product output can be traced back to source classification, formula version, and authorized use.

#### UAT-11 — Reliability, chaos, and soak testing

Tasks:

- Drop random multicast packets.
- Drop a contiguous packet range.
- Deliver duplicates.
- Deliver packets out of order.
- Disable A side.
- Disable B side.
- Kill the ingest process.
- Kill the book service.
- Restart with empty local state.
- Simulate Rewind timeout/failure.
- Simulate SILO restart.
- Simulate stale reference data.
- Run at least one 24-hour UAT soak, followed by longer soaks as TXSE activity permits.
- Verify there are no silent transitions from degraded state to healthy state.
- Produce test evidence and recovery-duration metrics.

Deliverable: written UAT certification report for internal production approval.

### UAT completion gate

Do not purchase direct production connectivity merely because development is feature-complete. UAT should be considered complete only when all of the following are true:

- FEED 1-5 A/B connectivity is repeatable.
- Decoder regression tests pass.
- Recorded sessions replay deterministically.
- Order-book hashes are deterministic.
- TCP Rewind successfully repairs injected bounded gaps.
- SILO successfully bootstraps a fresh process.
- Book health prevents publication of untrusted state.
- Historical event counts reconcile with replay.
- Initial intelligence metrics have documented formulas and analyst validation.
- Candidate Derived Intelligence payloads have been submitted to TXSE or are on a documented approval path.
- API/MCP requests are authenticated and auditable.
- UAT system has passed the agreed soak and chaos tests.
- Production connectivity quotes and architecture have been reviewed, but no unnecessary production commitment has been made.

### UAT monthly operating-cost target

TXSE's published Test Environment logical-connectivity fee is currently $0. The items below are internal planning allowances, not TXSE quotes:

| UAT item | Planning target per month |
|---|---:|
| TXSE Test Environment logical connectivity | $0 |
| Compute / VMs | $100-$300 |
| Database / storage | $50-$150 |
| Raw capture / object storage | $25-$100 |
| Monitoring / logs | $0-$100 |
| VPN / networking | $0-$100 |
| **Initial UAT target** | **about $175-$750/month** |

The team should optimize first for correctness and observability rather than ultra-low latency. Production-specific colocation and direct 10 Gb spending remain outside the UAT phase.

# 10. Phased implementation plan

The schedule below is a planning baseline for a small, focused team. Calendar duration depends heavily on TXSE onboarding/certification responsiveness and access to UAT. Run the commercial/legal and engineering tracks in parallel.

> **Phase 0 — TXSE approvals and UAT provisioning \| Week 0-2**

Make UAT the formal first delivery environment. Complete the legal/market-data onboarding path, obtain test access, and create the minimum engineering platform required to receive and preserve TXSE UAT traffic.

### Work

- Confirm which legal entity will be the TXSE Data Recipient.
- Submit/confirm Market Data Agreement and Exchange Data Order Form/System Description.
- Explicitly describe the UAT build: FEED ingest, raw capture, decoding, book reconstruction, Rewind/SILO recovery, analytics, internal APIs, AI/MCP experimentation, and candidate Derived Intelligence.
- Request UAT FEED 1-5 A/B connectivity and credentials.
- Request current TCP Rewind and SILO Snapshot protocol/session documentation and credentials.
- Request daily reference-data specification and delivery procedure.
- Obtain TXSE certification/test scenarios and test-symbol guidance.
- Confirm supported UAT VPN/cloud path, source-IP/firewall requirements, and any onboarding lead times.
- Ask TXSE to review representative Derived Intelligence payloads and MCP/API distribution model.
- Create repositories, protobuf module, CI/CD, secrets management, issue tracker, observability baseline, and runbook template.
- Provision the initial UAT compute/database/object-storage environment.
- Keep UAT, PROD, and DR configuration/secrets namespaces separate from day one.

### Exit criteria

- TXSE UAT access/credentials are available or all remaining onboarding dependencies have named owners/dates.
- At least one UAT endpoint/path can be reached from the chosen environment.
- Rewind/SILO/reference-data documentation is available or formally requested with an owner.
- Written project-specific approval path exists for intended raw and derived usage.
- Architecture decision records exist for event bus, Timescale/Postgres, raw object storage, and deployment model.
- Initial UAT monthly infrastructure budget is approved.

> **Phase 1 — UAT system foundation \| Week 2-5**

Build the repeatable UAT transport, packet-capture, decoder, replay, and reference-data foundation. This phase ends only when the team can deterministically reproduce TXSE UAT input as canonical events.

### Work

- Establish and document UAT VPN/cloud connectivity.
- Join one FEED unit on A/B and validate packet flow before scaling to all FEED 1-5 A/B.
- Record feed unit, side, source, multicast group/port, receive timestamp, packet length, and sequence metadata.
- Implement raw packet/session capture before decoding.
- Implement packet-rate, drop, duplicate, out-of-order, reconnect, and A/B-latency metrics.
- Implement deterministic A/B duplicate suppression/merge logic.
- Implement sequence tracking and structured gap events.
- Implement the FEED binary decoder with golden test vectors for required message types.
- Create canonical protobuf `MarketEvent` contracts and schema versioning.
- Implement raw capture replay through the same production decoder path.
- Implement daily reference-data ingestion and effective-dated symbol/stream mapping.
- Add regression tests that compare canonical event output byte-for-byte or field-for-field across repeated replays.
- Create `uat-connect`, `uat-capture`, `uat-replay`, and `feed-inspect` operational tools/scripts.

### Exit criteria

- FEED 1-5 A/B can be joined repeatably in UAT.
- A/B duplicate merge works under live capture and replay.
- Sequence gaps are detected and surfaced immediately.
- All expected UAT FEED message types decode without silent corruption.
- Recorded UAT sessions replay to the same canonical event sequence.
- Daily reference mappings are loaded without assuming FEED unit == stream/matching engine.
- Decoder/replay regression suite runs in CI.
- A new developer can follow the UAT runbook and reproduce the environment.

> **Phase 2 — Recovery and book correctness \| Week 5-8**

Produce a self-healing, verifiable TXSE order book.

### Work

- Implement gap detector and bounded TCP Rewind recovery.

- Implement SILO Snapshot bootstrap/recovery and catch-up orchestration.

- Build order-level book engine and price-level aggregation.

- Add integrity invariants: no negative size, unknown order handling policy, sequence continuity, snapshot/catch-up barrier.

- Book-health state machine and monitoring.

- Chaos tests: packet loss, duplicate packets, process restart, delayed rewind, snapshot restart.

### Exit criteria

- Book returns to LIVE after injected bounded gaps.

- Fresh process can bootstrap with SILO and catch up to live multicast.

- No customer/API publication of book as healthy while state is degraded.

- Deterministic book hash matches across repeated replays.

> **Phase 3 — Historical store and base APIs \| Week 8-11**

Persist the stream, query history, and expose internal engineering APIs.

### Work

- Event/trade/metric schema in Timescale/Postgres.

- Batch writers and backpressure policies.

- Internal REST/gRPC endpoints for symbol state, trades, book health, book snapshot.

- WebSocket internal stream.

- Operational dashboards: packet rates, gaps, recovery duration, decoder errors, lag, book health.

- Retention/compression policies and data-volume measurement.

### Exit criteria

- 24+ hour UAT soak test without unrecovered gaps.

- Historical query results match replayed event counts.

- SLO candidates measured for ingest-to-publish latency and recovery time.

> **Phase 4 — Intelligence engine \| Week 11-15**

Turn reconstructed market state into proprietary non-reversible metrics and signals.

### Work

- Implement rolling metric engine and daypart/symbol baselines.

- Liquidity/depth/imbalance/cancel/replenishment metrics.

- Execution and hidden-liquidity metrics.

- Auction intelligence metrics.

- Composite anomaly framework with versioned signal definitions.

- Evidence payload for every signal.

- Backtest/replay tooling to evaluate false positives and signal stability.

### Exit criteria

- Each signal is reproducible from versioned inputs.

- Signal payload does not require raw FEED exposure.

- Derived output reviewed against the planned TXSE System Description/non-reversibility boundary.

> **Phase 5 — Customer platform, MCP, and compliance \| Week 15-19**

Create the actual developer product around Derived Intelligence.

### Work

- Tenant/auth/API-key or OAuth layer, rate limits, plans, usage metering.

- Public intelligence REST/WebSocket endpoints.

- Go/TypeScript SDKs or one SDK for MVP.

- MCP server with intelligence-first tools.

- AI explainer constrained to metric evidence.

- Compliance access ledger and entitlement service.

- Customer/admin portal for keys, usage, entitlements, alert rules.

- External security review and abuse controls.

### Exit criteria

- A developer can sign up in sandbox, obtain credentials, query intelligence, and receive signals.

- Raw routes are inaccessible without a distinct entitlement.

- Every request can be classified and audited by product/data class.

> **Phase 6 — TXSE certification and production readiness \| Week 19-23**

Prove network/recovery behavior and operational readiness before production cutover.

### Work

- Complete TXSE certification steps required for data access/connectivity.

- Finalize production connectivity (extranet or NY6 physical) and DR design.

- Provision redundant A/B paths and secrets/config.

- Production runbooks, on-call, alert thresholds, capacity tests.

- Security hardening and disaster-recovery exercise.

- Finalize TXSE-approved System Description for actual launch scope.

### Exit criteria

- TXSE production access is authorized.

- Production topology passes failure/recovery drills.

- Launch scope matches approved data use/distribution description.

> **Phase 7 — Limited production beta \| Week 23-27**

Run a controlled beta before broad external commercialization.

### Work

- Ingest live FEED and compare with UAT assumptions.

- Invite a small set of approved beta users for Derived Intelligence.

- Measure latency, uptime, anomaly quality, cost per symbol/customer, and support load.

- Tune signal thresholds and API payloads without making material distribution changes outside approval.

- Prepare pricing/SLAs and customer documentation.

### Exit criteria

- 30-day stable live operation target.

- No unresolved data-integrity incidents.

- Customer feedback confirms intelligence value beyond raw market data.

- Go/no-go decision for general availability and any raw-data tier.

# 11. Parallel workstreams and ownership

| **Workstream**                 | **Primary owner**                          | **Scope**                                                                                                     |
|--------------------------------|--------------------------------------------|---------------------------------------------------------------------------------------------------------------|
| Exchange / legal / market-data | Founder/Product + counsel/market-data lead | Agreements, System Description, derived-data review, user/distributor classification, fees, approval changes. |
| Network / exchange edge        | Senior network/low-latency engineer        | UAT/production connectivity, multicast, routing, A/B, rewind, SILO, network observability.                    |
| Feed and market-state platform | Senior Go engineer                         | Decoder, canonical events, book, replay, recovery orchestration.                                              |
| Data platform                  | Backend/data engineer                      | Event bus, Timescale, storage lifecycle, historical API, capacity.                                            |
| Intelligence / quant analytics | Quant/data engineer                        | Metrics, baselines, signal definitions, replay evaluation.                                                    |
| Developer platform / MCP       | Backend/product engineer                   | REST/WebSocket, SDK, MCP, auth, plans, docs.                                                                  |
| SRE/security/compliance        | SRE/platform engineer + security support   | Secrets, CI/CD, observability, audit ledger, DR, incident response.                                           |

**Lean-team option:** One strong Go/platform engineer can initially cover edge + decoder + book, one backend/data engineer can cover storage/API, and one founder/product lead can handle TXSE/commercial work. Add quant/SRE specialists as the UAT feed becomes stable. Do not under-resource network/recovery correctness.

# 12. Milestones, dependencies, and critical path

| **Milestone** | **Definition**                    | **Hard dependency**                                                   |
|---------------|-----------------------------------|-----------------------------------------------------------------------|
| M0            | Project approved                  | TXSE onboarding path + internal architecture decisions                |
| M1            | First UAT packet received         | UAT connectivity/credentials                                          |
| M2            | Canonical FEED replay             | Decoder + raw capture                                                 |
| M3            | Correct live book                 | A/B sequencing + reference mappings + book engine                     |
| M4            | Self-healing book                 | TCP Rewind + SILO                                                     |
| M5            | Historical/queryable market state | Timescale + writers + APIs                                            |
| M6            | First derived signal              | Metrics + baseline framework                                          |
| M7            | Developer sandbox                 | Auth + intelligence endpoints + MCP                                   |
| M8            | Production authorization          | TXSE certification + approved System Description + production network |
| M9            | Limited beta                      | Stable live feed + external derived-intelligence users                |
| M10           | GA decision                       | 30-day beta evidence + economics + compliance signoff                 |

**Critical path:** TXSE access/approval -\> UAT transport -\> decoder -\> sequence/recovery correctness -\> book correctness -\> derived analytics -\> certification/production connectivity. UI, SDK, and AI work should not be allowed to hide delays in the exchange-edge critical path.

# 13. What you need to do next

These are the next actions I would take, in order, before committing to production infrastructure.

1.  **1. Confirm the Data Recipient legal entity —** Decide the exact company name that will sign/has signed the TXSE market-data documents. This name becomes the compliance and billing anchor.

2.  **2. Submit or update Schedule B/System Description —** Describe FEED UAT and intended production use, internal non-display processing, derived analytics, external Derived Intelligence APIs/WebSocket/MCP, entitlement controls, historical storage, and any planned raw-data distribution. Ask TXSE to confirm classification.

3.  **3. Request UAT FEED onboarding —** Ask TXSE for current UAT access instructions/credentials, current FEED and transport specs, TCP Rewind/SILO protocol specs, daily reference-data delivery details, test symbols/scenarios, and certification checklist.

4.  **4. Ask three policy questions in writing —** (a) Confirm the planned intelligence metrics/signals qualify as Derived Data when non-reversible; (b) confirm whether LLM/MCP delivery of those outputs changes classification; (c) confirm whether any specific planned metric is fee liable or needs additional licensing.

5.  **5. Choose the first production-connectivity path —** Request approved extranet providers and quotes. Compare that path with direct NY6 10 Gb economics; do not buy physical connectivity yet unless latency/business needs justify it.

6.  **6. Start the engineering repository now —** Create Go workspace, proto repo, txse-edge-ingest, txse-feed-decoder, replay tool, shared observability, and test fixtures. Keep UAT/PROD/DR configs fully separate.

7.  **7. Build decoder/replay before UI —** The first demo should be: captured UAT packets -\> decoded canonical events -\> deterministic replay. The second demo should be: live/replayed full order book with health state.

8.  **8. Define the first 5 intelligence signals —** Start with depth imbalance, liquidity withdrawal, execution velocity, hidden-liquidity ratio, and auction pressure. Define formula, baseline, confidence, evidence payload, and non-reversibility constraints.

9.  **9. Create a compliance data dictionary —** For every stored/output field tag: source, Exchange Data vs derived, real-time/delayed/historical, display/non-display, external exposure, retention, and customer entitlement requirement.

10. **10. Schedule the production go/no-go only after UAT recovery passes —** Do not commit to NY6/DR production spend until A/B merge, TCP Rewind, SILO recovery, book integrity, and 24-hour soak tests are passing.

# 14. First 30-day UAT execution checklist

## Week 1 — UAT onboarding and environment

☐ Finalize the System Description draft with the full UAT build scope.

☐ Open UAT onboarding request and collect FEED, Rewind, SILO, reference-data, and certification documentation/credentials.

☐ Confirm TXSE-supported UAT VPN/cloud network path and firewall/source-IP requirements.

☐ Provision UAT compute, Postgres/Timescale, object storage, secrets, and baseline monitoring.

☐ Create repo/CI/protobuf skeleton and architecture decision records.

☐ Create separate `uat`, `prod`, and `dr` configuration/secrets namespaces.

☐ Assign owners for UAT networking, FEED decoder/book, storage/API, and financial-data analysis.

## Week 2 — First packets and raw truth

☐ Establish UAT connectivity and document the connection runbook.

☐ Join at least one FEED multicast unit on both A and B sides.

☐ Persist raw packet capture with feed-side/unit/network metadata and receive timestamps.

☐ Implement packet-rate, duplicate, drop/gap, out-of-order, and A/B-latency telemetry.

☐ Implement framing/session parsing required to extract FEED payloads.

☐ Build a minimal packet inspection CLI.

☐ Confirm daily reference-data delivery and load one day's mappings.

## Week 3 — Decoder and deterministic replay

☐ Implement core FEED decoder messages and golden binary tests.

☐ Publish versioned canonical events to the local event bus.

☐ Build replay CLI using the same decoder path as live traffic.

☐ Verify repeated replay produces an identical canonical event sequence.

☐ Add CI regression fixtures from sanitized/approved UAT captures.

☐ Start the order ID/state model and price-level aggregation design.

☐ Financial-data partners begin formal specifications for the first five intelligence signals.

## Week 4 — Full UAT feed and recovery foundation

☐ Join FEED 1-5 A/B.

☐ Implement deterministic A/B merge and full sequence/gap monitoring.

☐ Start the live/replayed order-book engine.

☐ Implement book-health state machine skeleton.

☐ Establish TCP Rewind sessions and test at least one controlled recovery path if credentials/specs are available.

☐ Establish SILO client skeleton and snapshot/catch-up design.

☐ Define the first chaos tests: dropped packet, duplicate packet, A-side loss, process restart.

☐ Produce sample Derived Intelligence JSON payloads with the financial-data partners.

☐ Send candidate Derived Intelligence/MCP payloads to TXSE or place them on the formal review path.

## Day-30 gate

By day 30, the project should be able to demonstrate:

1. Live UAT FEED reception.
2. Raw packet capture.
3. Deterministic decode/replay.
4. A/B duplicate and sequence monitoring.
5. Initial order-book reconstruction.
6. Reference-data mapping.
7. Rewind/SILO integration underway with documented blockers.
8. Versioned definitions for the first five intelligence signals.
9. A documented path to TXSE review of Derived Intelligence outputs.

If the team cannot demonstrate items 1-4 by day 30, do not expand into customer UI or production-connectivity work; resolve UAT transport/decoder correctness first.

# 15. Cost model and purchasing gates

| **Cost item**                    | **Current published amount / planning estimate** | **When to incur** | **Decision gate** |
|----------------------------------|--------------------------------------------------|-------------------|-------------------|
| UAT Test Environment logical connectivity | **$0/mo from TXSE under current fee schedule** | During development/certification | Use UAT as the default build environment before production spend. |
| UAT cloud/VPN/storage/monitoring | **Planning estimate: ~$175-$750/mo initially** | During UAT | Internal planning estimate, not a TXSE quote; measure actual packet/storage volume. |
| FEED internal distribution       | \$1,500/mo; waived through 12/31/2026       | When credentialed/required for planned use          | Confirm billing start and exact entity/use classification with TXSE.       |
| FEED external distribution       | \$2,500/mo; waived through 12/31/2026       | Only if raw Exchange Data is externally distributed | Avoid for initial Derived Intelligence-only MVP unless TXSE says required. |
| Multicast FEED service           | \$450/mo                                    | Production market-data multicast service            | Needed for production feed subscription.                                   |
| Primary 10 Gb                    | \$6,000/mo                                  | If direct physical production connectivity selected | Compare approved extranet first.                                           |
| DR 10 Gb                         | \$3,000/mo                                  | If direct DR physical connectivity selected         | Add after primary architecture is proven and DR requirement is finalized.  |
| Colocation/carrier/cross-connect | Not specified in uploaded TXSE fee schedule | Direct-connect scenario                             | Obtain Equinix/provider quotes; these are additional to TXSE fees.         |

**Fee caveat:** Use the current TXSE Fee Schedule and written TXSE confirmation for budgeting. Fees and classifications can change; do not treat this planning table as an invoice quote.

# 16. Risk register

| **Severity** | **Risk**                                              | **Failure mode**                                                                       | **Mitigation**                                                                                                               |
|--------------|-------------------------------------------------------|----------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------|
| High         | Policy classification differs from product assumption | TXSE determines some outputs are Exchange Data or fee-liable rather than Derived Data. | Get written approval of sample schemas/metrics before external launch; isolate output layers so products can be re-entitled. |
| High         | Book corruption from missed events                    | Packet loss or recovery bug silently corrupts book and analytics.                      | A/B merge, gap alarms, rewind, SILO, deterministic replay, book hashes, health state.                                        |
| High         | Production connectivity lead time                     | Physical/extranet provisioning delays launch.                                          | Start provider discussions during UAT; keep production access off critical engineering path until needed.                    |
| Medium       | Spec changes                                          | TXSE changes FEED/transport messages.                                                  | Versioned decoders, raw archive, regression replay, spec-version metadata.                                                   |
| Medium       | Data volume/cost growth                               | Order-level history becomes expensive.                                                 | Measure in UAT; tier raw retention vs canonical retention; compress Timescale/object storage.                                |
| Medium       | False-positive intelligence                           | Signals are noisy and undermine customer trust.                                        | Evidence payloads, replay evaluation, per-symbol/daypart baselines, confidence scores.                                       |
| Medium       | AI hallucination                                      | LLM explanation overstates what metrics prove.                                         | Generate from bounded structured evidence; templates/guardrails; never let AI change underlying signal.                      |
| Low/Medium   | Vendor lock-in                                        | Event bus or cloud choice becomes costly.                                              | Protobuf contracts + replayable raw archive + simple service interfaces.                                                     |

# 17. Definition of done for MVP

☐ Receives all intended UAT FEED units over redundant sides and identifies gaps/duplicates.

☐ Decodes FEED into a versioned canonical event stream and can deterministically replay recorded sessions.

☐ Bootstraps/recoveries via SILO and bounded gaps via TCP Rewind without exposing an unhealthy book as healthy.

☐ Maintains a correct order book and persists core historical events/metrics.

☐ Computes at least five versioned intelligence signals with evidence and historical baselines.

☐ Exposes authenticated intelligence REST/WebSocket and MCP interfaces.

☐ Separates raw Exchange Data entitlements from Derived Intelligence entitlements.

☐ Retains auditable usage/access records and can produce a TXSE-oriented audit export.

☐ Has an approved/accepted TXSE System Description covering actual MVP use and distribution.

☐ Passes a sustained UAT soak test plus recovery chaos tests and a security review.

# 18. Questions to send TXSE now

11. Please confirm the current UAT onboarding process and whether UAT FEED, TCP Rewind, and SILO are all available through the same test/certification network path.

12. Please provide the current protocol specifications for TCP Market Data Rewind and SILO Snapshot Service, plus any authentication/session details.

13. Please provide the daily reference-data specification/delivery mechanism used for matchingEngineId and streamId assignments.

14. For a platform that computes liquidity, order-flow, hidden-liquidity, auction-pressure, anomaly, and regime metrics from FEED, then distributes only non-reversible metrics/signals externally through APIs/WebSocket/MCP, does TXSE expect that output to be treated as Derived Data as defined in the Market Data Policies?

15. Does delivering approved Derived Data through an AI assistant or MCP tool change its classification or subscriber-reporting requirements?

16. Which of the proposed metrics, if any, would TXSE consider a reasonable facsimile/substitute for Exchange Data and therefore unsuitable for unrestricted Derived Data distribution?

17. If the MVP distributes only approved Derived Data externally while FEED remains internal/non-display, which current fee categories will apply?

18. What certification cases does TXSE require for market-data recipients before production enablement?

19. Can TXSE provide the current approved extranet-provider list and any recommended providers for market-data-only recipients?

20. What notice/approval process should we follow when adding new derived metrics that do not materially change the underlying distribution model?

# Appendix A — Source documents used

| **Source**                                                              | **Location**                   | **Use in this plan**                                                                                                                                        |
|-------------------------------------------------------------------------|--------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|
| TXSE FEED specification                                                 | download.web.txse.com/FEED.pdf | Message semantics, order lifecycle, trades, auctions, timestamps. Reviewed in the preceding analysis.                                                       |
| Connectivity Manual v1.4 (Sept. 1, 2026)                                | Uploaded                       | Primary/DR sites; connectivity methods; test-only VPN/cloud; IPv4/BGP/PIM-SM; multicast groups; TCP Rewind; SILO Snapshot.                                  |
| Schedule B — Exchange Data Order Form and System Description (May 2026) | Uploaded                       | Access type; internal/display/non-display; controlled/uncontrolled external distribution; FEED/BALE/Historical selections; system-description requirements. |
| TXSE Market Data Policies (updated Nov. 13, 2025)                       | Uploaded                       | Record retention; distributor requirements; delayed data; Derived Data; reporting/audit.                                                                    |
| TXSE Market Data Agreement (updated Nov. 13, 2025)                      | Uploaded                       | License scope, System Description approval/change control, proprietary rights, audit/use controls.                                                          |
| TXSE Fee Schedule (September 2026)                                      | Uploaded                       | FEED/BALE definitions; market-data fees; connectivity fees; membership/other fees.                                                                          |
| Prior TXSE Developer Platform — Technical Implementation Document       | ChatGPT Library                | Original product/architecture direction rewritten and expanded by this plan.                                                                                |

# Appendix B — Suggested repository layout

txse-platform/  
proto/  
market/v1/  
intelligence/v1/  
entitlement/v1/  
services/  
txse-edge-ingest/  
txse-recovery/  
txse-feed-decoder/  
txse-reference/  
txse-book/  
txse-trades/  
txse-auction/  
txse-metrics/  
txse-signals/  
txse-api/  
txse-mcp/  
txse-compliance/  
tools/  
txse-replay/  
feed-inspect/  
book-verify/  
deploy/  
uat/  
prod/  
dr/  
docs/  
architecture/  
runbooks/  
txse-approvals/  
data-classification/

# Appendix C — Key TXSE source pointers

- Connectivity Manual: pp. 3-4 — NY6 primary, DA11 DR, connectivity methods, UAT-only VPN/cloud; p. 5 — IPv4/BGP/PIM-SM; p. 6 — A/B multicast FEED 1-5 and UAT/DR groups; pp. 7-8 — TCP Rewind; pp. 8-9 — SILO Snapshot.

- Exchange Data Order Form/System Description: p. 1 — access type and intended-use classifications; p. 2 — controlled/uncontrolled system descriptions and FEED/BALE/Historical selections.

- Market Data Policies: §2/§3 — retention and approval; §11 — 15-minute delayed data; §12 — Derived Data definition and distribution treatment; §13 — fees and non-display uses.

- Market Data Agreement: §3-4 — non-member data recipient rights and license; §4 — System Description and approval of derived/reprocessed services; §5-6 — records/reporting; §11 — audit rights.

- Fee Schedule, Sept. 2026: Section B — FEED/BALE market-data fees; Section C — physical/logical connectivity fees.
