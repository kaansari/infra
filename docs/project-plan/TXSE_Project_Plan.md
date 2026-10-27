# CEERAT TXSE Intelligence Platform Project Plan

Version: 1.0
Planning baseline: 2026-10-23
Status: Proposed delivery baseline; no implementation, exchange approval, or production acceptance is asserted.

**Goal:** Deliver a correct, recoverable, entitled TXSE intelligence platform in UAT, then progress through exchange authorization to a controlled production beta and a general-availability decision.

**Architecture:** A restricted raw-data plane captures FEED and owns sequencing, recovery, deterministic market state, and replay. Versioned metrics and signals feed a separate intelligence authority; public gRPC/WebSocket and MCP gateways expose approved projections with service-enforced entitlement and audit. Existing CEERAT identity and preferences are supporting capabilities, not owners of market truth.

**Technology direction:** Go and protobuf/gRPC, multicast ingest, TCP Rewind, SILO, encrypted object archive, an ordered durable event stream, PostgreSQL with measured Timescale requirements, WebSocket, and existing CEERAT OAuth/MCP infrastructure. Event-bus implementation and deployment grouping require early architecture decisions rather than installing every suggested technology.

**Execution:** This is a program delivery plan, not a code-level implementation script. Before implementing each work package, create its detailed PR specification under `requirement/txse/`, with exact contracts/files, failing-test cases, verification commands, rollout, and recovery. Use the applicable executing-plans workflow for the approved package. Independent review is required at each gate.

## 1. Source hierarchy and scope

| Source | Role in this plan |
| --- | --- |
| [Canonical product/technical direction](../../requirement/txse/txse_developer_platform.md) | Governs CEERAT ownership, interfaces, security, product scope, tools, and UAT gates |
| [UAT architecture and roadmap v1.1](../../requirement/txse/TXSE_Intelligence_Platform_Project_Plan_v1.1_UAT.md) | Supplies work packages, indicative week ranges, staffing, first-month objectives, and purchasing gates |
| [TXSE source documents](../txse/) | Exchange protocol, connectivity, agreement, policy, order-form, and fee evidence; obtain current revisions and written project-specific answers before relying on them for deployment |
| [Security and scale PR track](../../requirement/pr/security-scale/README.md) | Supporting CEERAT logging, database isolation, CI, action safety, resource budgets, recovery, and operational acceptance requirements |

The canonical direction overrides the earlier roadmap's REST examples, generic tool names, API-key suggestions, portal expansion, and standalone-repository layout. Public interfaces are **gRPC, WebSocket, and MCP**. Initial MCP tools use the `txse_` namespace. Preserve the existing multi-repository workspace unless an approved architecture decision changes it.

MVP includes FEED 1–5 A/B, raw capture, versioned decoding, reference mappings, Rewind/SILO recovery, deterministic books/trades/auctions, historical reconciliation, five reviewed signals, entitled intelligence delivery, audit, and operational acceptance.

MVP excludes order entry/execution, brokerage/custody, personalized investment advice, consolidated-market/NBBO claims, unrestricted raw redistribution, LLM calculation of market truth, REST, browser backends, legacy tool adapters, and parallel implementations. Sandbox delivery consists of authenticated protocol examples, fixtures, and developer documentation; a new web portal is a separate product decision.

### Source-document register

The supplied PDFs were locally extracted and checked for the planning constraints below. They are the repository snapshot, not confirmation of current exchange terms; WP-01 must obtain revision confirmation and missing companion protocols.

| Supplied document | Planning dependency |
| --- | --- |
| [FEED](../txse/FEED.pdf) | Message semantics; presence-bit optional fields and length-delimited trailing-field extensibility; canonical event/decoder coverage |
| [Connectivity Manual](../txse/ConnectivityManual.pdf) | Primary/DR sites, test-only VPN/cloud, multicast units/sides and Rewind/SILO endpoint inventory; endpoint tables alone do not define recovery protocols |
| [Market Data Policies](../txse/MarketDataPolicies.pdf) | Records, controlled/non-display use, derived-data definition, distribution and reporting/classification requirements |
| [Market Data Agreement](<../txse/TXSE - Market Data Agreement.pdf>) | Authorized receipt/use, approved System Description, change control, records and audit obligations |
| [Schedule B / Order Form and System Description](<../txse/TXSE_Schedule B Exchange Data Order Form and System Description.pdf>) | Data Recipient contacts, access source, intended use, system/entitlement description and selected data products |
| [September 2026 Fee Schedule](../txse/TXSE_Fee_Schedule.pdf) | Historical budget input only; current fees, billing triggers and waivers require confirmation before purchase |

## 2. Starting position and decisions

Existing CEERAT OAuth/MCP, private gRPC, commerce, and portable preferences are reusable foundations. Their prior functional results do not prove TXSE entitlement, workload identity, data-plane correctness, or production capacity. Commerce products are not financial instruments, and commercial subscription/payment state alone is not an exchange-data entitlement.

`requirement/txse/` currently contains two overarching planning/direction documents, not a numbered implementation PR series. The work-package identifiers below are proposed planning IDs, not existing PRs or implementation claims.

A fresh builder evidence request matched generic customer/ownership terms and suggested extending `ceerat-user-service`; it returned no TXSE domain requirements. That heuristic conflicts with the canonical TXSE direction. **WP-00 must establish explicit TXSE ownership and update builder discovery before service scaffolding.** Do not copy its unrelated customer/order implementation suggestions into the TXSE data plane.

Decisions to close in weeks 0–2:

| Decision | Accountable role | Required outcome / gate |
| --- | --- | --- |
| Legal Data Recipient and authorized use | Product lead + counsel/market-data lead | Named entity, onboarding owner, intended use/distribution, and written approval path; G0 |
| Current FEED framing, Rewind/SILO, reference and certification specifications | Feed/network lead + exchange liaison | Versioned source register and complete required protocol package; G1/G2 blocked where absent |
| UAT network path and production options | Network/SRE lead | Tested UAT path; production/extranet options and lead times, with no premature purchase; G0/G6 |
| Event bus and partition/ordering model | Platform lead | One selected implementation, ordering/durability/backpressure/replay rationale and benchmark; G1 |
| Storage and retention classes | Data lead + compliance | Separate raw, historical, compliance, and preference policies with costs, deletion/hold, and recovery; G3 |
| Workload identity and delegated user context | Security + platform leads | Authenticated private gRPC, integrity-protected context, anti-spoof/replay tests, consistent revocation; before customer integration |
| Resource targets and signal-quality thresholds | Product + quant + SRE leads | Numeric latency, recovery, throughput, signal evaluation, availability and budget targets; G3/G4 |
| Initial deployable grouping and operations ownership | Platform lead + SRE | Explicit modules versus processes, isolation needs, named owners/on-call; G0 |

Use role placeholders until actual people accept responsibility. An unassigned owner or unanswered mandatory decision remains an open gate, not an implicit approval.

## 3. Schedule, capacity, and critical path

The inherited baseline is approximately **27 weeks through a 30-day limited beta**, assuming a focused team, timely exchange access, and no major correctness rework. This is an estimate, not a committed launch date. Week 0 begins when the project is staffed and funded. Exchange approvals and network delivery are external dependencies; track their lead times separately and reforecast every week. Do not convert these week offsets into calendar commitments before G0.

| Phase | Indicative window | Main deliverable | Exit gate |
| --- | --- | --- | --- |
| 0 — Mobilize and obtain access | Weeks 0–2 | Owners, approved architecture decisions, UAT path, protocol/access requests, compliance register | G0 |
| 1 — Establish raw truth | Weeks 2–5 | FEED 1–5 A/B capture, decoder, reference mapping, deterministic canonical replay | G1 |
| 2 — Prove market state and recovery | Weeks 5–8 | Correct book/trades/auctions, Rewind gaps, SILO empty-start recovery | G2 |
| 3 — Build history and internal delivery | Weeks 8–11 | Reconciled historical storage, internal gRPC/streaming, measured 24-hour soak | G3 |
| 4 — Validate intelligence | Weeks 11–15 | Five versioned signals, baselines, analyst evaluation and output-classification review | G4 |
| 5 — Deliver customer sandbox | Weeks 15–19 | Entitled public gRPC/WebSocket/MCP, constrained explanation, audit and SDK/examples | G5 |
| 6 — Certify and authorize production | Weeks 19–23 | Exchange authorization, approved launch description, network/DR, security/capacity drills | G6 |
| 7 — Run limited production beta | Weeks 23–27 | At least 30 consecutive days of observed live operation and customer/economic evidence | G7 / GA decision |

Allow the full 30-day beta even if it extends beyond the indicative week-27 boundary. A material incident requires an explicit decision on whether a new observation window is needed.

**Critical path:** exchange access/specifications → capture/sequencing → decoder/reference → book + Rewind/SILO → history/replay reconciliation → validated signals → entitled delivery → exchange production authorization/network → beta. SDK, explanations, and preferences must not obscure slippage on this path.

Work that can progress in parallel: legal/classification from week 0; synthetic decoder fixtures while access is pending; quant formula/evidence definitions before live signals; identity/entitlement design during data-plane work; production provider discussions during UAT. Recorded or synthetic results must never be reported as exchange-connected UAT acceptance.

## 4. Team and accountability

| Role | Accountable deliverables | Indicative capacity assumption |
| --- | --- | --- |
| Product/program and exchange liaison | Scope, budget, access requests, dependency tracking, customer value, go/no-go | One accountable lead throughout |
| Senior feed/platform engineer | Framing, sequencing, decoder, recovery, market-state correctness | One dedicated engineer plus a second qualified reviewer |
| Backend/data engineer | Stream/storage, history, intelligence query authority, entitlement integration | One dedicated engineer |
| Quant/financial-data analysts | Formula/evidence specifications, baselines, false-positive review, five-signal acceptance | Two analysis partners participating from early UAT, as proposed in source roadmap |
| Network/SRE engineer | Multicast path, UAT environment, deployment, capacity, backup/DR, on-call | Shared early; increased coverage before G2/G6 |
| Developer-platform engineer | Public gRPC/WebSocket/MCP, SDK/examples, explanation projection | Dedicated capacity by phase 5; earlier contract work can share backend capacity |
| Security and market-data counsel | Threat model, privileged access, classification, agreement/approval review | Scheduled specialist reviews at G0/G4/G6 |

The 27-week estimate assumes these functions can overlap. A single coding agent or one engineer serializing all roles is not equivalent capacity; re-estimate after WP-00 rather than compressing testing, exchange response time, or beta observation.

## 5. Repository and ownership map

All paths below are relative to the sibling workspace unless prefixed `infra/`. Proposed paths are planning decisions to finalize in WP-00, not claims that files already exist.

| Repository / proposed area | Responsibility |
| --- | --- |
| `contracts-repo/packages/ceerat-contracts/proto/txse/` | Versioned market events, health/provenance, intelligence, query/stream and entitlement contracts; security inventories |
| `services-repo/services/txse-market-data/` | Proposed restricted data-plane Go module: ingest, decoder, reference, recovery, book, trade, auction, replay; process grouping documented by ADR |
| `services-repo/services/txse-intelligence-service/` | New explicit private intelligence authority, metrics/signals, query projections, entitlement and usage enforcement |
| `services-repo/services/ceerat-user-service/` | Existing identity/commerce/preferences only; no FEED ingestion, instrument truth, or analytics ownership |
| `apps-repo/` — public gRPC/WebSocket adapter | Thin typed gateway; exact project path is a WP-00 decision because a ready-made TXSE API gateway is not established by the current requirements |
| `apps-repo/ai/ceerat-agent-gateway/` | Existing MCP gateway, flat `txse_` tools, OAuth/schema registration; no market calculations |
| `infra/` deployment/verification areas | Environment-separated configuration, CI, UAT tooling, replay/chaos/capacity evidence, runbooks and release manifests |
| `ceerat-platform-builder-agent/` inventories and standards | Explicit TXSE discovery/owners, security boundaries, protocol surfaces, validated testing and operational standards |

Logical component ownership in the canonical architecture does not require a separate deployed process for every component. Preserve deterministic interfaces and isolate restricted raw data; choose additional process boundaries for fault isolation or measured scale.

## 6. Work packages and proposed PR sequence

Each row becomes one or more bounded PR specifications in `requirement/txse/`. Split only at independently reviewable/testable boundaries. Contracts and migrations land before dependent binaries are exposed; implementation PRs include affected inventories and runbooks.

| ID | Deliverable and proposed PR document | Owner | Dependencies | Acceptance evidence |
| --- | --- | --- | --- | --- |
| WP-00 | `00-foundation-ownership-and-adrs.md`: explicit owners, builder discovery, threat model, selected architecture and deployment grouping | Platform + security | Project staffing | No customer/order keyword routing for TXSE; reviewed ADRs; role and data-flow inventory |
| WP-01 | `01-access-licensing-and-uat-network.md`: Data Recipient, System Description, access/protocol register, UAT provisioning and environment separation | Product + network | WP-00 decisions | Written approval path, protected credentials, working UAT connection, missing-spec blockers tracked |
| WP-02 | `02-market-contracts-and-classification.md`: canonical envelopes, field dictionary, health/errors, versioning and trust boundaries | Platform + compliance | WP-00; current specs | Generated contracts; schema/compatibility tests; no client-selected authority or data class |
| WP-03 | `03-capture-sequencing-and-archive.md`: first unit A/B then all five, timestamps, archive durability, sequence merge, gap events and telemetry | Feed + SRE | WP-01, WP-02 | Live capture evidence; duplicate/divergence/loss tests; bounded buffers; archive integrity |
| WP-04 | `04-decoder-reference-and-replay.md`: complete required FEED families, extensibility, effective-dated mapping, shared replay path | Feed | WP-02, WP-03 | Golden/malformed/fuzz fixtures; version rejection; stable canonical output; no unit-to-engine inference |
| WP-05 | `05-book-trade-auction-state.md`: order/price state, execution vs trade/break lifecycle, status and auction semantics | Feed + quant reviewer | WP-04 | Invariants and golden books; deterministic hashes; halt/session/day boundaries; untrusted state suppressed |
| WP-06 | `06-rewind-silo-and-health.md`: bounded recovery, escalation, snapshot/catch-up barrier, restart/major desync and health machine | Feed + network | WP-03–05 and recovery specs | Injected gaps repaired; clean empty-state bootstrap; overlapping/stale recovery rejected; no false LIVE |
| WP-07 | `07-history-retention-and-internal-delivery.md`: ordered persistence, snapshots, indexes, retention, historical private gRPC/streaming | Data + SRE | WP-04–06 | Counts/hashes reconcile; restore/replay drill; volume/latency measured; 24-hour soak |
| WP-08 | `08-metrics-baselines-and-five-signals.md`: five production signals and evaluation harness, formula/evidence versioning | Quant + backend | WP-05–07; formula design can start earlier | Analyst-reviewed reproducibility, quality thresholds, warm-up behavior and non-reversibility assessment |
| WP-09 | `09-entitlement-usage-and-compliance.md`: scopes versus grants, delegated context, data-class gates, ledger and emergency disable | Security + backend + compliance | WP-02; integrates WP-07/08 | Two-tenant isolation, spoof/replay/expiry/revocation tests, immutable export and audit-outage policy |
| WP-10 | `10-public-grpc-and-websocket.md`: bounded intelligence query/stream adaptation and client examples | Developer platform | WP-08, WP-09 | Entitled output, provenance/health, cursor reset, backpressure, revocation during stream, no raw tunnel |
| WP-11 | `11-mcp-explanations-and-preferences.md`: six canonical tools, safe evidence explanations, minimized optional defaults | MCP + backend | WP-08–10; existing preferences for optional integration | Closed schemas; two customers; real Codex/ChatGPT lifecycle; prompt-safety and preference-failure isolation |
| WP-12 | `12-uat-security-chaos-and-acceptance.md`: integrated evidence package, external-output review and sandbox documentation | SRE + security + product | WP-01–11 | All G1–G5 evidence reproducible; chaos/capacity tests; documented exchange classification path |
| WP-13 | `13-certification-production-and-dr.md`: production authorization, approved description, topology, secrets, recovery and cutover | Product + network + SRE | WP-12; external approvals | G6 signed evidence, actual deployment checks, independent security review, failover and rollback drills |
| WP-14 | `14-controlled-beta-and-ga-decision.md`: approved users, 30-day observation, support, economics and launch decision | Product + operations | WP-13 | G7 report, no unresolved integrity incidents, measured product value/cost, explicit go/no-go |

**PR execution checklist, applied to every package:**

- [ ] Re-read canonical direction and applicable PDF revision; obtain builder owner/security/impact evidence and resolve conflicts before coding.
- [ ] Write the detailed PR specification, concrete negative/positive tests, contract/file changes and deployment dependencies; review before execution.
- [ ] Establish failing tests for behavior changes, implement the smallest reviewed slice, then run relevant module/integration/race checks and builder drift checks.
- [ ] Exercise the package's failure/recovery cases, document rollout/recovery and immutable version tuple, and attach sanitized results.
- [ ] Review and merge the bounded change; record local/staging/live status separately. Update inventories after implementation and durable standards after validation.

### Initial signal and interface scope

WP-08 delivers these five signals. Each specification defines exact formula/units, normalization, lookback/daypart baseline, warm-up and insufficient-data behavior, confidence, evidence, required book health, replay tests and accepted false-positive criteria. Quant reviewers approve these values before production implementation; the plan does not invent financially meaningful thresholds.

| Signal | Required interpretation boundary |
| --- | --- |
| Depth imbalance | TXSE-visible depth at declared bands/time; no consolidated-market claim |
| Liquidity withdrawal/replenishment | Versioned addition/removal and replenishment windows; recovery discontinuities cannot masquerade as activity |
| Execution velocity | Explicit execution/trade inclusion rules, units and window; breaks/corrections handled reproducibly |
| Hidden/non-displayed-liquidity ratio | Precisely defined numerator/denominator and limitations; no claim that unseen liquidity is directly observed |
| Auction pressure | Correct preamble/band/extension/print state; evidence and reset rules at auction boundaries |

WP-10 refines the canonical illustrative operations into reviewed protobuf contracts: `GetSymbolIntelligence`, `ListUnusualActivity`, `GetLiquidityAnalysis`, `GetAuctionIntelligence`, `GetHaltState`, `GetSignal`, `ListHistoricalSignals`, and `ExplainSignalEvidence`. All query/history operations have bounded filters, stable pagination where applicable, and explicit health/provenance/classification. WebSocket uses entitled subscriptions, resumable cursors, heartbeats and explicit gap/reset semantics.

WP-11 exposes only the initial canonical MCP surface, with `ceerat/domain: txse_intelligence`:

```text
txse_get_symbol_intelligence
txse_get_unusual_activity
txse_get_liquidity_analysis
txse_get_auction_state
txse_get_halt_state
txse_explain_signal
```

Saved preferences are optional minimized presentation/query defaults. Explicit requests take precedence within entitlement and server-policy bounds. Preferences cannot choose environment, change formulas, grant access, suppress provenance/freshness/health/classification warnings, represent suitability, or authorize trading. Instrument/watchlist references are validated by the owning TXSE domain. When preferences are unavailable, intelligence uses documented safe defaults; the ingest/recovery/book path is independent.

## 7. Milestone gates and release evidence

| Gate | Required proof | Signoff roles |
| --- | --- | --- |
| G0 — Ready to build connected UAT | Named owners/budget; selected architecture; current protocol register; authorized UAT access/path; any unavailable Rewind/SILO/reference dependency explicitly blocks its downstream package | Product, platform, network, compliance |
| G1 — Raw truth | Repeatable FEED 1–5 A/B receipt/archive; sequence integrity; all required decoder families; effective-dated mappings; repeated canonical replay equality | Feed lead + independent reviewer |
| G2 — Correct self-healing state | Deterministic books; execution/trade/auction correctness; Rewind injection recovery; empty-start SILO/catch-up; strict health publication | Feed, SRE, quant reviewer |
| G3 — Durable internal platform | Historical reconciliation; recoverable storage; measured resource envelope; at least 24-hour UAT soak; numeric SLO targets agreed from evidence | Data, SRE, platform |
| G4 — Intelligence accepted internally | Five replay-reproducible signals; formula/baseline/confidence/evidence versions; analyst-approved quality thresholds; sample outputs submitted for classification review | Quant, product, compliance |
| G5 — Sandbox/UAT accepted | Entitled/audited gRPC/WebSocket/MCP; tenant isolation/token lifecycle; safe explanations/preferences; chaos and redaction; external sandbox access only within explicitly authorized UAT use | Security, product, SRE, compliance |
| G6 — Production authorized | Required TXSE certification and written authorization; approved System Description for actual outputs; confirmed commercial terms; production/DR network; security/capacity/recovery evidence and on-call | Exchange authorization plus internal product, security, compliance, SRE signoff |
| G7 — GA decision | At least 30-day beta evidence; no unresolved integrity defects; observed SLOs, approved distribution, analyst/customer value, unit economics and support capacity | Product/business owner, quant, compliance, SRE/security |

G1–G5 can proceed internally with approved UAT access while production commercial questions remain open. No external distribution becomes authorized merely because an output is labeled derived. Missing approval, an unhealthy book presented as healthy, cross-tenant access, reconstructable unapproved output, unreconciled state, or mandatory audit failure blocks the relevant release.

Evidence records exact source revisions, specification/formula/schema versions, environment, configuration hashes, dataset/session identifiers, commands, PASS/FAIL, recovery timings, and reviewers. Raw captures, sensitive fixtures, credentials, and customer contents stay in access-controlled storage; committed reports contain safe summaries/references only.

## 8. First 30 days

| Period | Engineering actions | Exchange/product actions | Demonstration |
| --- | --- | --- | --- |
| Days 1–5 | WP-00 owners/ADRs; CI and fixture strategy; contracts and threat model; environment/secrets isolation | Confirm legal entity, submit/update System Description, request current access/specs/reference/certification package and sample-output review | Reviewed architecture and access/dependency register with owners |
| Days 6–10 | UAT connection and first FEED unit A/B capture; archive integrity; packet/sequence observability | Resolve onboarding issues; assign two analysis partners; draft five signal/evidence definitions | First authorized UAT packets stored and replayable |
| Days 11–20 | Canonical decoding, golden fixtures, reference mapping and repeated replay; extend across units | Review data dictionary, non-reversibility examples, intended MCP delivery and open classification questions | Same capture produces identical canonical events |
| Days 21–30 | FEED 1–5 A/B coverage; book foundations; Rewind/SILO protocol spikes and injected-gap plan | Review measured UAT cost/volume, vendor lead times, classification correspondence and next-phase readiness | Raw-truth report, replay equality and explicit recovery-readiness gaps |

Day-30 go/no-go: if first packets, archive integrity, correct decoder/reference behavior, and deterministic replay are not demonstrated, hold customer-interface and production-spend expansion. Continue synthetic work where useful, but report the exchange-connected milestone as blocked and reforecast its dependents.

## 9. Correctness, security, and capacity test strategy

| Risk/input class | Required behavior | Owning packages |
| --- | --- | --- |
| Malformed framing, unknown versions, optional fields, truncation, duplicated/conflicting A/B data | Bounded decoding; documented extensibility; unsupported critical state fails closed; no silent state corruption | WP-03/04 |
| Loss, out-of-order data, long disconnect, stale/overlapping recovery, buffer exhaustion | Ordered bounded recovery or explicit DEGRADED/resnapshot; snapshot barrier verified; no partial healthy publication | WP-05/06 |
| Session/day boundary, reference change, halt/resume, trade break, auction extension | Correct lifecycle, stable replay/hash and valid metric invalidation/recalculation | WP-04/05/08 |
| Baseline warm-up, sparse instruments, unavailable evidence, stale/incomplete books | Explicit insufficient-data/confidence/health outcome; no invented precision or unsupported signal/explanation | WP-08/11 |
| Tenant/context spoofing, expired/revoked grant, subscription change, prompt-like preferences or upstream text | Deny or reset safely; reauthorize streaming; preserve entitlement/classification/health; preference failure never affects ingest/recovery/book | WP-09–11 |
| Saturation, slow consumers, database/stream/archive/audit outage, node loss | Bounded pools/buffers, deterministic backpressure, explicit gap/reset, recovery/status evidence and agreed fail-closed exposure | WP-03/07/09/10/12 |

Live and replay use the same decoder/state code. Quant research can use Python, but production formulas require deterministic versioned implementations and shared fixture evidence. Canonical hashes exclude nondeterministic operational metadata by an explicit documented rule.

Before G3, agree numeric thresholds for ingest-to-publish p95/p99, recovery by gap class, maximum recovery memory, replay throughput, storage/day, archive persistence lag, stream lag and database connections. Before G4 agree signal quality and sample coverage; before G6 agree production capacity/headroom, availability and RPO/RTO. Lack of measurements is an open gate, not permission to invent thresholds.

Instrument packet/side divergence, gaps, Rewind/SILO outcomes, decoder unknowns, reference freshness, event/book/metric lag, health, stream gaps/backpressure, storage pressure, authorization/entitlement denials, ledger health and cost. Test actual alert delivery and on-call runbooks. Do not use secret-bearing payloads or high-cardinality customer content as telemetry labels.

## 10. Compliance, procurement, and budget controls

Track every stored/exposed field by source, raw/derived classification, real-time/delayed/historical basis, display/non-display use, internal/external distribution, entitlement, formula version, retention and approval reference. Obtain review of representative outputs for reconstructability, including combined, repeated and historical queries; per-field approval alone is insufficient.

Maintain receipt/use/display/distribution records for the source-required minimum of three years or longer as applicable, subject to current agreement and counsel confirmation. This is not a blanket requirement to keep every raw packet or every prompt for three years. Define separate evidence, raw archive, historical, personal-data and legal-hold policies. Keep restricted inputs out of external LLM systems unless their use is explicitly authorized; explanations consume minimized approved evidence.

The source roadmap's UAT infrastructure allowance is approximately **$175–$750/month**, excluding engineering/specialists and subject to actual traffic/storage. It is a historical planning allowance, not a current quote or guaranteed ceiling. Reconfirm exchange fees, waivers, provider charges and billing start in writing; do not base the business case on a waiver extending into the launch period.

| Spend stage | Permitted planning purpose | Approval evidence |
| --- | --- | --- |
| Before G0 | Access/architecture diligence and explicit capped setup work | Product sponsor budget and responsible owner |
| UAT G0–G5 | Measured compute, archive, database, VPN/network, CI and observability | Approved UAT cap; weekly actual/forecast report and retention measurements |
| Production planning during UAT | Provider discussions, topology and current quotes | No purchase implied; document primary/DR lead times and total landed cost |
| Production commitment | Authorized production path with sufficient recovery/UAT evidence | G5/UAT acceptance, business approval, current terms and delivery plan; activation still blocked on G6 |
| Beta/GA | Limited-user operation, support and measured scaling | Approved user/use scope; cost per session/symbol/customer and margin review |

Do not assume Render/cloud hosting can supply the exchange multicast edge or production connectivity. The canonical source limits VPN/cloud connectivity to test/certification and identifies NY6/DA11; confirm the current supported production/extranet topology with TXSE before purchase.

## 11. Risk register and control dependencies

| Risk | Owner | Early indicator | Response / release consequence |
| --- | --- | --- | --- |
| UAT or recovery/reference specs delayed | Exchange liaison | Incomplete access/protocol register | Escalate weekly; build fixture tooling; no unsupported G1/G2 claims |
| Builder routes TXSE into commerce service | Platform lead | Evidence suggests customer/order owner | WP-00 explicit owner/discovery correction; block scaffolding |
| Silent market-state corruption | Feed lead | Replay/hash divergence or unexplained recovery | Stop authoritative publication; investigate from archive; G2 blocker |
| Output classification rejected or changes | Compliance + product | Unanswered examples or reconstructability findings | Restrict fields/products and resubmit; no unauthorized external exposure |
| Shared CEERAT security/scale gaps | Security + SRE | Logging secrets, shared DB access, missing CI gates/pool limits | Implement applicable security-scale PRs before dependent customer/production gates |
| Data volume exceeds budget/capacity | Data + SRE | Archive/day, lag or connection waits above envelope | Tier retention with approvals, bound work, benchmark partitions; reforecast |
| Noisy signals or misleading explanation | Quant + product | Low evaluation quality, unsupported causal claims | Reject/revise signal version, constrain evidence/templates; G4/G5 blocker |
| Network procurement or certification lead time | Network + liaison | Provider/exchange dates move | Quote early, sequence activation after authorization, move beta date |
| Insufficient independent review/on-call | Program lead | One person is sole implementer and approver | Add specialist/reviewer capacity; reduce parallel scope rather than waive gates |
| Audit/recovery evidence unavailable | Compliance + SRE | Missing/failed exports, backups or drills | Defined fail-closed delivery and repair plan; G6 blocker |

The existing security-scale documents are supporting dependencies, not evidence of completed controls. Some earlier configuration-hardening references may have moved: at implementation kickoff locate their current authoritative versions and register any missing requirement explicitly. Do not waive MFA, isolation, transport, secret scanning, drift, audit or recovery because a referenced file is absent.

## 12. Governance, progress reporting, and completion

Run a weekly delivery review with milestone forecast, completed PRs, actual connected-UAT evidence, critical-path blockers/owners, next-week commitments, approval register and actual/forecast cost. Review market-state correctness and exchange classification separately from UI/tool demos. Rebaseline after each gate or material scope/access change.

Maintain these registers under `requirement/txse/` or an approved restricted evidence system: PR/dependency status, decisions, source specification revisions, exchange approvals/questions, data classification, risks, capacity/cost and gate evidence. Use statuses Planned → Spec reviewed → In implementation → Locally verified → UAT verified → Production verified where applicable; a merged PR is not live acceptance.

Required builder context for implementation PRs, run from the builder checkout:

```text
ceerat-builder check-context
ceerat-builder codex-context --output json
ceerat-builder evidence request "TXSE intelligence" --output json
ceerat-builder patterns grpc-security --output json
ceerat-builder rbac check --output json
ceerat-builder check apps --output json
ceerat-builder check sql --output json
ceerat-builder check drift --output json
```

Resolve source/owner conflicts explicitly. Add applicable contract/service impact checks and new TXSE modules to CI/workspace inventories as they exist; current builder success cannot certify missing TXSE implementation.

Project completion requires G7 approval: correct and recoverable market state, five validated signals, entitled/audited gRPC/WebSocket/MCP, explicit exchange authorization for launch scope, tested security/DR/capacity, and a completed limited beta with a documented commercial go/no-go. General availability and any future raw-data tier are separate explicit decisions. This plan does not authorize production credentials, purchases, external messages, load tests, or failover actions.
