# CEERAT Preference Domain — Phase 3 Requirement

Status: approved design input for Phase 3 PR planning  
Primary clients: ChatGPT, Codex, Claude, Gemini, and compatible MCP hosts  
Canonical interfaces: public HTTPS MCP and authenticated private gRPC  
Persistence owner: `ceerat-user-service`

## 1. Product purpose

CEERAT Preferences is customer-owned, portable structured memory. A customer
can ask one authorized AI client to remember a preference and allow another
authorized AI client to use it later through the same CEERAT account.

```text
Customer -> authorized AI host -> CEERAT MCP -> preference domain
                                                -> PostgreSQL
Customer <- recommendation using relevant stored preferences
```

The service stores what the customer explicitly asks CEERAT to remember. It
does not infer hidden preferences, learn from behavior, score the customer, or
silently persist model guesses.

Every preference must be both machine-readable and understandable to its owner:

```text
food.ingredients.processing = minimally_processed / PREFER
Food processing — Prefer minimally processed food
```

## 2. Existing platform context

Phase 3 builds on the deployed Phase 1–2 path:

```text
ChatGPT/Codex/compatible MCP host
  -> HTTPS MCP + delegated OAuth bearer token
ceerat-agent-gateway
  -> authenticated private gRPC + short-lived internal user session
ceerat-user-service
  -> JWT -> RBAC -> logging -> handler
  -> authenticated-customer ownership -> repository -> PostgreSQL
```

External OAuth terminates at `ceerat-agent-gateway`. The gateway validates the
external token, performs coarse scope checks, adapts MCP schemas, and shapes
safe results. The user service independently enforces authentication, RBAC,
ownership, validation, concurrency, idempotency, and persistence.

There is currently no preference protobuf, gRPC service, database table,
repository, or MCP tool. The builder assigns customer-owned preferences to the
existing `ceerat-user-service` deployment boundary. Phase 3 adds a distinct
`preference.PreferenceService` contract and domain module inside that binary;
it does not create another deployable service.

Phase 3 exposes preferences publicly only through MCP. The broader CEERAT
developer API gateway may later expose the same gRPC contract to authorized
developer applications, but that is a separate reviewed release; it must reuse
this domain service and cannot create another preference implementation.

No REST API, browser implementation, legacy `ceerat-agent-service` tool,
generic AI endpoint, direct database caller, fallback, compatibility alias,
dual read/write, or parallel storage path is allowed.

## 3. Gaps corrected from the initial proposal

The original draft established the right product concept but left production
gaps. This requirement resolves them:

1. **Deployment ownership:** use a preference domain module hosted by the
   existing user service, not a standalone preference server/repository tree.
2. **Consequential writes:** conversational intent alone is not a server-side
   authorization boundary. Upsert and delete use read-only preview followed by
   explicit, short-lived confirmation.
3. **Unknown outcomes:** confirmation is never blindly retried. Durable
   idempotency and a self-scoped operation-status read reconcile timeouts.
4. **Upsert ambiguity:** canonical and custom preferences have one explicit,
   normalized logical identity; a client cannot rename or retarget a record by
   accident.
5. **Definition authority:** definitions, allowed values, labels, and templates
   are curated server-owned data. Customers and models cannot mutate them.
6. **Prompt-injection risk:** stored note/name/display text is untrusted data.
   The service does not store free-form executable model instructions or claim
   that stored text overrides current user/system/developer instructions.
7. **Scope identifiers:** context and entity references are bounded opaque
   labels, not authorization-bearing foreign IDs. V1 does not dereference them
   into other domains.
8. **Typed values:** normal values use protobuf `oneof` types and typed SQL
   columns where practical. Arbitrary JSON is not a V1 escape hatch.
9. **Privacy:** context retrieval is category-bounded, opt-in, and minimized.
   Preference bodies, notes, search queries, and values are excluded from logs.
10. **Pagination and caching:** list/definition results use stable bounded page
    tokens; context returns a profile version and deterministic ETag/fingerprint
    material without trusting client cache state.
11. **History and deletion:** changes retain a bounded operational audit without
    exposing it as ordinary context. Delete removes the active preference while
    retaining only the minimum policy-required audit/idempotency record.
12. **Definition evolution:** definitions have stable keys and versions. A
    disabled definition remains readable for an existing preference but cannot
    be selected for a new canonical write.

## 4. Domain ownership and boundaries

### 4.1 Canonical owner

- Contract package/service: `preference.PreferenceService`
- Generated contracts/security: `contracts-repo`
- Handler/repository/database: `services-repo/services/ceerat-user-service/preferences`
- Public adapter: `apps-repo/ai/ceerat-agent-gateway`
- OAuth and deployment policy: `infra`
- Durable architectural standards: `ceerat-platform-builder-agent`

The builder's generic CRUD output is an inventory hint, not a mandate. Public
and private customer operations are explicitly self-scoped `My` methods.

### 4.2 Identity

MCP and customer gRPC requests never accept `customer_id`, `user_id`, tenant,
owner, role, or scope. The service resolves:

```text
validated external subject
  -> gateway identity exchange
  -> authenticated internal user
  -> customers.user_id
  -> customer-owned preference rows
```

Missing and foreign opaque preference IDs return the same customer-safe
`NOT_FOUND` shape.

### 4.3 Authorization

OAuth scopes:

```text
ceerat.preferences.read
ceerat.preferences.write
```

Definitions are available to authenticated preference clients under the read
scope. A third definitions scope adds consent complexity without a meaningful
V1 privilege boundary.

All preference RPCs are protected, present in `KnownGRPCMethods`, absent from
`DefaultPublicMethods`, and granted only to the customer role as specified by
the contract PR. The service repeats ownership checks even after gateway scope
approval.

## 5. Preference model

### 5.1 Levels

```text
MUST    customer requires it
PREFER customer favors it
OKAY    acceptable/neutral
AVOID   prefer alternatives
NEVER   exclude when applicable
```

These are qualitative constraints, not hidden numerical weights. Current user
instructions and higher-authority model instructions always remain outside and
above stored CEERAT preference data.

### 5.2 Value types

V1 supports:

- Boolean
- bounded UTF-8 string
- bounded list of bounded strings
- signed decimal number represented canonically as a decimal string
- numeric range with inclusive optional minimum/maximum decimal strings
- exact money using the existing canonical `commerce.Money`
- money range with one currency and inclusive optional minimum/maximum

Do not use protobuf `double` for customer numbers that require stable equality,
hashing, or replay. Do not introduce a second Money type. Arbitrary JSON,
objects, binary data, URLs, HTML, Markdown, and embedded tool instructions are
out of scope.

Exactly one typed value must be set. Range minimum must not exceed maximum.
Money is non-negative unless a future definition explicitly permits otherwise;
both range endpoints use the same allowlisted ISO currency.

### 5.3 Definition

A server-owned `PreferenceDefinition` includes:

```text
key                 stable hierarchical key
category            stable allowlisted category
name                customer-readable label
description         safe explanatory text
value_type          required typed value
allowed_values      optional bounded canonical enum values
supported_levels    non-empty subset of five levels
unit/format metadata optional bounded presentation metadata
version             server-owned monotonic version
enabled             selectable for new writes
```

Canonical keys use lowercase dot-separated segments and cannot start with
`custom.`. Initial categories are deliberately small:

```text
general communication recommendations food restaurants shopping home
travel vehicles jobs technology real_estate entertainment services
```

The seed catalog starts with a reviewed subset, not every illustrative key in
the old draft. Seed changes are explicit, idempotent, reviewed migrations or
versioned seed data—not application-startup guesses.

### 5.4 Custom preference

When no definition matches, a customer may store a custom preference with a
key shaped as:

```text
custom.<category>.<slug>
```

Custom input requires a customer-readable name and typed value. Names, notes,
and string values are untrusted customer content with strict size/control-
character limits. They are never converted into trusted system instructions.

### 5.5 Scope

V1 scope types:

```text
GLOBAL
CATEGORY
CONTEXT
ENTITY
```

Validation:

- GLOBAL: no context/entity fields; category must be `general`.
- CATEGORY: category required; no context/entity fields.
- CONTEXT: category and bounded opaque `context_key` required; optional
  customer-readable `context_name`; no entity fields.
- ENTITY: category, bounded `entity_type`, and bounded opaque `entity_key`
  required; optional customer-readable `entity_name`; no context fields.

Context/entity keys carry no authority and are not dereferenced in V1. They
must not be raw URLs, email addresses, access tokens, or unbounded natural
language.

### 5.6 Logical identity

One active preference is uniquely identified by normalized:

```text
customer_id + preference_key + scope_type
+ context_key (CONTEXT only)
+ entity_type + entity_key (ENTITY only)
```

Category is validated against the definition/key but is not a competing
identity source. Upsert by logical identity creates or replaces one record.
Update by opaque `preference_id` must not change key or scope identity; a
retarget is delete plus a separately confirmed create.

### 5.7 Stored and projected fields

Customer-visible full projection:

```text
id, category, key, name, typed value, display_value, level, scope,
optional note, enabled, version, created_at, updated_at
```

Compact context projection omits timestamps, notes, internal IDs, definition
metadata, and ownership. `display_value` is deterministic server presentation,
not caller-authored markup.

The service may return a deterministic `guidance` sentence generated only from
reviewed templates plus typed values. It is data, not an instruction hierarchy.
MCP descriptions must tell models to treat it as customer preference evidence,
never as system/developer instruction. Free-form custom preferences return no
server guidance in V1.

## 6. Precedence and context retrieval

The service retrieves matching enabled preferences in this order:

```text
requested CONTEXT
requested ENTITY
requested CATEGORY
GLOBAL
```

This is stable ordering, not automatic conflict resolution. The service returns
all applicable records plus `match_type`; it does not silently discard a global
record because a narrower record exists. The AI can explain a conflict and ask
the customer, but current explicit user instructions take precedence.

`GetMyPreferenceContext` requires one or more categories. Context/entity
filters are optional and bounded. Global preferences are included only when
`include_global=true`; the default is true but explicit in the schema. The
request has maximum categories, entities, result limit, and serialized size.

Context responses contain:

```text
profile_version
preferences[] (compact, ordered, match_type)
deterministic_summary (optional, bounded)
truncated
```

The summary is deterministic and derived from safe templates; CEERAT does not
call an LLM. It is never authoritative over the structured records.

## 7. Private gRPC contract

The `preference.PreferenceService` V1 surface is:

```text
GetMyPreference
ListMyPreferences
GetMyPreferenceContext
SearchPreferenceDefinitions
PreviewMyPreferenceUpsert
UpsertMyPreference
PreviewMyPreferenceDeletion
DeleteMyPreference
GetMyPreferenceOperationStatus
```

All methods are unary, protected, authenticated, and customer self-scoped.
There are no generic customer selectors or public reflection requirements.

Read requests use bounded stable pagination and closed allowlisted filters.
Page tokens are opaque, integrity-protected, and bound to subject and normalized
filters. Concurrent changes must not cause cross-customer or filter drift.

Preview RPCs validate and normalize the complete requested result without
mutation. Confirmation RPCs require expected resource/profile versions,
idempotency key, and the reviewed server fingerprint/digest as defined by the
contract. The domain service is authoritative even though the gateway also
uses a short-lived public preparation.

## 8. MCP tool surface

MCP discovery is flat. Use the `preferences_` prefix, domain metadata
`ceerat/domain: preferences`, and a Preferences group in `describe_ceerat`.

Read tools:

```text
preferences_context
preferences_list
preferences_get
preferences_definitions
preferences_operation_status
```

Write flow tools:

```text
preferences_upsert_prepare
preferences_upsert_confirm
preferences_delete_prepare
preferences_delete_confirm
```

Do not expose ambiguous direct `preferences_upsert` or `preferences_delete`
tools in parallel. Confirmation tools accept only `preparation_id` and
`confirmed: true`. Avoid top-level `oneOf` schemas because hosted clients have
previously cached or misvalidated them. Every object is closed and bounded.

Read annotations must be read-only. Prepare tools are read-only because they do
not mutate domain state. Confirm tools are consequential; delete confirmation
is destructive. Tool annotations aid clients but never replace enforcement.

The gateway must not interpret natural language, choose a definition, compute
logical identity, create guidance, resolve conflicts, access PostgreSQL, or
infer success after a timeout. It validates public shape, verifies OAuth scope,
calls private gRPC, creates/consumes durable identity-bound preparations, and
projects safe results.

## 9. Write safety and consent

An AI may propose a preference from conversation, but it may prepare a write
only when the user explicitly asks CEERAT to remember/change/forget something
or clearly accepts a preceding save/delete question. The preparation preview
shows:

- create versus update versus delete;
- canonical/custom key and customer-readable name;
- normalized typed value and display value;
- level and complete scope;
- before and after state when updating;
- warnings, expected version, profile version, fingerprint, and expiry.

The AI stops after preview and asks the user to confirm the displayed change.
Only then does it call the matching confirmation tool.

This extra step is intentional: preferences are durable personal memory and may
be sensitive or affect future recommendations. It also gives consistent,
testable behavior across AI hosts. OAuth consent grants capability; it does not
confirm each persistent memory mutation.

## 10. Concurrency, idempotency, and outcomes

Every confirmed write uses a fresh 1–128 character idempotency key. The service
binds and hashes:

```text
customer + OAuth/public client context where available + operation kind
+ logical/resource identity + normalized request + expected versions
+ preview fingerprint + idempotency key
```

Same key and same request returns the original result with `replayed=true`.
Same key and different request returns `IDEMPOTENCY_KEY_REUSED`. Updates and
deletes use optimistic versions. Each successful mutation increments the
preference version and the customer's preference profile version exactly once.

The database transaction atomically claims idempotency, locks the profile and
logical preference in documented order, validates current state, applies the
mutation/history, increments versions, and stores the replayable result.

Operation state is always truthful:

```text
not_started      known no mutation occurred
completed        committed result known
outcome_unknown  dispatch/commit outcome cannot be proven
```

Never mark an unknown write retryable. Use
`preferences_operation_status(operation_kind, idempotency_key)` to reconcile.

Idempotency and operation records have an explicit retention and cleanup
policy long enough for realistic hosted-client retries and incident recovery.

## 11. Database design

Production uses explicit, ordered, idempotent SQL migrations plus preflight.
`AutoMigrate` is not the production migration authority.

Required tables:

```text
preference_definitions
customer_preferences
customer_preference_profiles
preference_operations
customer_preference_history
```

Key properties:

- UUID/opaque primary keys generated server-side.
- Foreign key from preferences/profiles/history/operations to customer.
- Typed discriminator plus validated typed columns; JSONB may store only a
  canonical bounded typed envelope when relational columns cannot represent the
  value cleanly. It is never an arbitrary payload escape hatch.
- Normalized context/entity columns and one database-enforced logical unique
  index using canonical empty sentinels.
- Positive versions and server timestamps.
- Indexes begin with `customer_id` for owned reads.
- Subject/filter-bound pagination uses an indexed stable ordering.
- Operations have unique `(customer_id, idempotency_key)`, request digest,
  operation type/state, safe result, expiry/retention timestamps.
- History stores change type, safe before/after digest or bounded necessary
  data, actor/client correlation, versions, and timestamp. It must not duplicate
  OAuth tokens, prompts, or full MCP payloads.

Migration includes rollback for development and a committed preflight that
fails service startup before public exposure when required schema is absent.

## 12. Definition catalog and custom data

Definitions are global product metadata managed through reviewed seed data in
V1. No customer/admin MCP mutation tools are included. Search supports exact
key/category filters plus bounded normalized text query over safe definition
fields. It does not search other customers' preferences.

Before preparing a canonical write, the AI should call definitions search when
the key is not already known. A valid canonical input must match the current
definition type, level set, allowed values, and category. A custom preference
is allowed only under `custom.` and cannot shadow a canonical key.

Initial seeds should cover a small tested selection across food, shopping,
home, travel, vehicles, jobs, communication, and general recommendations. Seed
quality and stable keys matter more than catalog size.

## 13. Privacy and prompt-injection controls

Preferences may reveal lifestyle, finances, employment, location, beliefs, or
health-adjacent facts even when those categories are not explicit. Treat all
preference content as sensitive customer data.

- Return only the authenticated customer's records.
- Require category-bounded context retrieval; never dump all preferences as an
  automatic preamble to unrelated tasks.
- Do not introduce protected/sensitive categories such as health, religion,
  politics, sexuality, biometrics, precise location, credentials, or legal
  status in the initial definition catalog without a separate policy review.
- Reject secrets/credential-shaped data where detectable, but do not claim
  perfect content classification.
- Escape/control presentation; prohibit control characters, HTML, Markdown
  links, tool-call syntax, role labels, and instruction delimiters in bounded
  custom fields where appropriate.
- Treat every customer-authored string as quoted data. Stored text can never
  instruct the agent to ignore policies, reveal data, call tools, or override
  the current user.
- Do not send preference data to another model or provider from the backend.
- Do not log preference values, names, notes, queries, summaries, complete
  request/response bodies, raw idempotency keys, or page tokens.

Customer-facing deletion semantics and retention must be documented accurately.
Do not call an audit-retained tombstone “fully erased” when policy retains it.

## 14. Errors and observability

Use the existing structured MCP envelope with:

```text
code, category, safe message/user_message, retryable, retry_after_seconds,
agent_action, operation_state, safe details, request_id
```

Required distinctions include unauthenticated, insufficient scope, invalid
definition/value/scope, preference not found, stale preference/profile version,
logical conflict, idempotency conflict, preparation expired/consumed, rate
limited, dependency unavailable, and outcome unknown.

Safe validation details may include bounded field paths, expected value type,
allowed enum values, current version, and required scope. Never echo a note,
string/list value, search query, definition description, token, SQL, topology,
or cross-customer identifier.

Audit every discovery/read/prepare/confirm/status attempt with request ID, tool
and domain, operation class, OAuth client, pseudonymous actor, scope decision,
safe hashed resource/key reference, versions, idempotency-key hash for writes,
downstream method, outcome/state, error code, latency, and replay status.

Writes fail closed before dispatch if required durable audit/idempotency state
cannot be recorded. Audit failure after a known commit must not turn success
into a retryable result.

## 15. Limits and abuse controls

Initial limits must be explicit constants and tested:

- request/body and nested object sizes;
- maximum categories/entities and result limit;
- maximum page size and query length;
- key/name/note/context/entity/value/list lengths;
- maximum list items and total serialized value size;
- maximum active preferences per customer and per scope/category;
- per-IP, client+subject, user, tool, and write rate limits;
- downstream deadlines, database statement/transaction timeouts, and bounded
  concurrent operations.

Reads may be cached only by authenticated customer, normalized filters, and
profile version. Never share customer-context cache entries between subjects.
Mutation invalidation follows the committed profile version.

## 16. Testing requirements

### Contract and security

- Every value and scope shape, enum, bound, unknown field, and invalid
  combination.
- No identity/authority fields in customer requests.
- Known method, role permission, public allowlist, inventory, generated-code,
  mapper, and drift consistency.
- Missing/expired/wrong issuer/audience tokens, missing scopes, revoked grants,
  wrong roles, and two-customer isolation.

### Service and database

- Canonical/custom create, update, get, list, context, delete, definition search.
- Logical uniqueness under concurrency and stable subject/filter pagination.
- Definition version/disabled behavior and exact type/allowed-level validation.
- Preference and profile optimistic versions.
- Idempotent replay, changed-payload conflict, restart persistence, cleanup,
  crash after commit/before response, and operation-status reconciliation.
- Transaction rollback, lock ordering, deadlock/serialization mapping, race
  tests, migration/preflight/rollback/reapply.
- No fallback, cross-owner record, or partial mutation.

### Gateway and MCP

- Exact live `tools/list` schemas with closed flat objects and accurate
  annotations/scopes/domain metadata.
- Read projections minimize data; prepare previews are complete; confirmation
  accepts only preparation ID plus true confirmation.
- Preparation expiry, replay, user/client binding, stale versions, scope revoked
  between prepare/confirm, dependency failures, and unknown outcomes.
- PII/prompt/query/value/idempotency/page-token redaction in responses, errors,
  logs, traces, and evidence.
- ChatGPT and Codex schema-import/cache behavior after gateway deployment.

### Live acceptance

Use two disposable customers and safe non-sensitive preferences. Prove:

1. OAuth grant includes read/write preference scopes.
2. Definition search and context/list/get reads work.
3. Prepare/confirm creates a canonical preference.
4. Same idempotency key replays; changed input conflicts.
5. Stale update fails without mutation; valid update increments both versions.
6. Another customer cannot observe or modify the record.
7. Delete preview/confirm removes it from active context.
8. Forced unknown outcome reconciles without blind retry.
9. Token expiry/refresh, scope denial, logout/revocation, rate limit, and safe
   dependency errors remain correct.
10. Cleanup restores disposable state and evidence contains no preference body.

## 17. Deployment order

For each dependency slice:

```text
contracts/generated/security/inventories
-> PostgreSQL migration and preflight
-> ceerat-user-service
-> Keycloak scope reconciliation when applicable
-> ceerat-agent-gateway
-> protected-resource metadata and live tools/list
-> refreshed/versioned hosted ChatGPT app
-> Codex + ChatGPT acceptance
```

Do not expose tools before matching schema and service binaries are live. Record
the contracts/service/gateway commit tuple. A failed Render deployment may
leave an older binary serving traffic; health checks must prove the private
preference RPC path, not merely process liveness.

## 18. Phase 3 definition of done

Phase 3 is complete only when:

- the nine canonical MCP tools operate through the one private gRPC/service
  path with read/write OAuth scopes;
- customers can discover, create, inspect, contextualize, update, delete, and
  reconcile their own preferences;
- definition authority, typed values, precedence, concurrency, idempotency,
  confirmation, and truthful outcomes are enforced by the service;
- privacy, prompt-injection, redaction, abuse, and two-customer isolation gates
  pass through both ChatGPT and Codex;
- migrations/preflight and deployment-skew gates pass;
- platform-builder standards and all inventories reflect the validated final
  surface; and
- no REST, browser, legacy, generic AI, direct database, fallback, or parallel
  preference path exists.

## 19. Deliberate V1 exclusions

- behavioral learning, implicit inference, confidence, weights, decay, ranking,
  embeddings, vector search, recommendation scoring, or an LLM in the backend;
- automatic conflict resolution or silent precedence suppression;
- arbitrary JSON, markup, executable instructions, files, URLs, secrets, or
  sensitive-category definition catalog expansion;
- admin/customer definition mutation APIs;
- sharing preferences with another customer or organization;
- multiple deployable preference services or databases;
- browser UI and existing UI migration;
- REST, legacy AI tools, compatibility aliases, flags, dual paths, or fallbacks.

## 20. TXSE Intelligence consumer profile

The TXSE Intelligence Platform is a supported preference consumer, not part of
the preference domain. Curated definitions may declare consumer domain
`txse_intelligence` for preferred signal families, explanation detail, default
time window, alert severity, presentation units, and bounded opaque
instrument/watchlist references.

The mandatory precedence is: current explicit request; entitlement/server
policy; market-data health, quality, and classification controls; saved
preference; service default. A preference must never grant Exchange Data access,
select UAT/PROD/DR, suppress provenance/freshness/book-health/risk/licensing
warnings, alter a metric or signal definition, authorize trading, or represent
positions or suitability. Market identifiers are resolved by their owning TXSE
domain; this service neither ingests FEED nor dereferences them.

`GetMyPreferenceContext` must require a bounded consumer purpose and categories
for TXSE use and return only the minimum matching projection. Server-authored
definition metadata may include `consumer_domains`; it is allowlisted and never
customer writable. Customer text remains untrusted data and is never converted
to instructions. TXSE services remain available without the preference service
and fall back only to documented service defaults.

Acceptance must prove preference values cannot override explicit query inputs,
OAuth scope, product entitlement, data classification, health/freshness fields,
formula versions, or required warnings; no raw/reconstructable Exchange Data or
market-derived customer profile is stored in preference tables.

## 21. Required builder workflow

Every implementing PR must use `ceerat-platform-builder-agent` before design and
after changes:

```text
ceerat-builder check-context
ceerat-builder codex-context --output json
ceerat-builder app-context ceerat-agent-gateway --output json
ceerat-builder evidence request "Phase 3 customer-owned preferences MCP" --output json
ceerat-builder patterns grpc-security --output json
ceerat-builder rbac check --output json
ceerat-builder check apps --output json
ceerat-builder check drift --output json
```

Contract PRs additionally run impact and contract/service verification. Builder
generic CRUD suggestions never override the self-scoped contract, confirmation,
or single-path rules in this requirement. Update applicable platform-builder
architecture, security, service, module, AI-tool, and public-integration
standards after each implemented behavior is tested; update durable completion
claims only after live human validation.
