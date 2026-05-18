# Ceerat Business Intelligence and AI System Intelligence Requirements

## 1. Purpose

This document defines the desired business intelligence, AI insight, and executive recommendation layer for the Ceerat platform.

The goal is not to build a conventional log viewer or basic uptime dashboard. The goal is to create a structured intelligence system that learns from customer behavior, agent behavior, service usage, order outcomes, operational friction, and product performance, then turns those signals into useful summaries and recommendations for admins and executives.

This document should guide future implementation work.

## 2. Product Vision

Ceerat should evolve from a transactional application into a system that can answer questions like:

- Which services are being recommended most often?
- Which services are accepted or rejected most often?
- Which agents convert recommendations into orders?
- Which customers are likely to need a follow-up?
- Which discounts or bundles might increase conversion?
- Where are orders slowing down?
- Which product, pricing, or workflow changes would improve the business?

The admin UI should eventually include an intelligence page that explains what is happening in the business and recommends concrete next actions.

Example output:

```text
Over the last 7 days, bathroom plumbing was recommended 14 times but accepted only 2 times.
Customers who declined often had order totals above $900.
Recommendation: test a 10% bundle discount for bathroom plumbing when paired with bathroom fixtures.
```

## 3. Design Principle

Do not make raw application logs the foundation for business intelligence.

Raw logs are useful for debugging failures, but they are messy and inconsistent. Business intelligence should be based on structured business events and curated facts.

The recommended layers are:

```text
Application actions
  -> structured business_events table in a separate BI/analytics database
  -> rollups / summaries
  -> AI insight generation
  -> ai_insights table in the BI/analytics database
  -> Admin UI executive summary and recommendations
```

Health logs and technical logs can be used later as secondary signals, but the first implementation should focus on structured behavioral events.

The BI/intelligence storage must be separate from the primary OLTP application database. The OLTP database should remain optimized for user, customer, order, service, and authorization workflows. Analytics writes, exploratory queries, AI summarization, rollups, and executive reporting should use a separate database so reporting load does not degrade transactional performance.

## 4. Core Concepts

### 4.1 Business Events

A business event is an append-only record of something meaningful that happened in the product or operation.

Examples:

```text
customer.created
customer.updated
customer.inactive_detected
user.created
user.role_changed
agent.assignment_created
agent.assignment_completed
service.recommended
service.accepted
service.declined
service.assigned_to_customer
discount.offered
discount.accepted
discount.declined
order.created
order.updated
order.completed
order.cancelled
order.service_added
rbac.permission_added
rbac.permission_removed
admin.user_password_reset
```

Business events should be factual, structured, and durable.

### 4.2 AI Insights

An AI insight is a generated recommendation, observation, risk, or summary derived from business events and current application state.

Examples:

```text
conversion_opportunity
customer_retention_risk
agent_performance_signal
service_pricing_recommendation
discount_experiment
operational_bottleneck
executive_summary
```

AI insights should be persisted, reviewable, and explainable.

### 4.3 Executive Summary

The executive summary is the highest-level view of the business.

It should answer:

- What changed recently?
- What needs attention?
- What opportunities exist?
- What actions should leadership consider?

The summary should be short enough to read quickly, but backed by detailed events and evidence.

## 5. Data Model

### 5.0 Storage Boundary

Business intelligence data should live in a separate BI/analytics database, not in the primary OLTP database.

Recommended local development naming:

```text
OLTP database:      ceerat or postgres
Analytics database: ceerat_bi
```

Recommended configuration:

```text
BI_DB_HOST
BI_DB_PORT
BI_DB_USER
BI_DB_PASSWORD
BI_DB_NAME
```

The analytics database may run on the same local Postgres server during development, but it should be a distinct database/schema boundary. In production, it should be possible to move it to a separate Postgres instance or analytics store without changing product behavior.

The application must never require an analytics write to commit the main OLTP transaction. If the BI database is unavailable, the main customer/order/user workflow should continue and the failure should be logged for retry or investigation.

### 5.1 `business_events`

Add a `business_events` table in the BI/analytics database.
Recommended columns:

```text
id UUID primary key
event_type text not null
actor_user_id UUID null
actor_role text null
customer_id UUID null
order_id UUID null
service_id UUID null
assignment_id UUID null
entity_type text null
entity_id UUID null
source text not null
severity text not null default 'info'
metadata jsonb not null default '{}'
created_at timestamptz not null default now()
```

Recommended indexes:

```text
business_events(created_at desc)
business_events(event_type, created_at desc)
business_events(customer_id, created_at desc)
business_events(order_id, created_at desc)
business_events(service_id, created_at desc)
business_events(actor_user_id, created_at desc)
```

Notes:

- `source` examples: `user-service`, `admin-ui`, `web-ui`, `customer-ui`, `agent-service`.
- `severity` examples: `info`, `warning`, `risk`, `opportunity`.
- `metadata` should hold event-specific structured details.
- The table should be append-only for normal application behavior.

### 5.2 `ai_insights`

Add an `ai_insights` table in the BI/analytics database.

Recommended columns:

```text
id UUID primary key
insight_type text not null
title text not null
summary text not null
recommendation text null
priority text not null default 'medium'
status text not null default 'new'
confidence numeric null
evidence jsonb not null default '{}'
created_by text not null default 'ai'
reviewed_by_user_id UUID null
reviewed_at timestamptz null
created_at timestamptz not null default now()
updated_at timestamptz not null default now()
```

Recommended statuses:

```text
new
reviewed
accepted
dismissed
implemented
```

Recommended priorities:

```text
low
medium
high
urgent
```

### 5.3 Optional Future Rollup Tables

Later, add rollup tables if raw event queries become slow.

Examples:

```text
daily_service_metrics
daily_agent_metrics
daily_customer_metrics
daily_order_metrics
```

These should be derived from `business_events` and core domain tables.

Rollup jobs should read from the BI/analytics database whenever possible. If they need current domain data from the OLTP database, they should use bounded read-only queries or replicated snapshots, not heavy ad hoc queries against transactional tables.

## 6. Event Tracking API

Add a server-side helper in the user service:

```go
TrackBusinessEvent(ctx, BusinessEvent{
    EventType: "order.created",
    ActorUserID: userID,
    ActorRole: role,
    CustomerID: customerID,
    OrderID: orderID,
    ServiceID: serviceID,
    Source: "user-service",
    Severity: "info",
    Metadata: map[string]any{
        "order_total": total,
        "channel": "admin-ui",
    },
})
```

Requirements:

1. Business event tracking must write to the separate BI/analytics database.
2. Business event tracking must not break the primary user workflow if event persistence fails.
3. The primary OLTP transaction must not depend on the BI database transaction.
4. Event persistence failures should be logged as technical errors.
5. Events must not store passwords, raw JWTs, private tokens, or unnecessary sensitive data.
6. Event metadata should be explicit and structured.
7. Prefer event type constants to avoid typos.
8. A retry/outbox mechanism may be added later if direct BI writes are not reliable enough.

## 7. Initial Events To Emit

Start small. The first implementation should emit events in high-value areas only.

### 7.1 User Events

Emit:

```text
user.created
user.updated
user.role_changed
admin.user_password_reset
```

### 7.2 Customer Events

Emit:

```text
customer.created
customer.updated
```

### 7.3 Service Events

Emit:

```text
service.assigned_to_customer
service.recommended
service.accepted
service.declined
```

If the current product does not yet distinguish recommendation from assignment, start with `service.assigned_to_customer`.

### 7.4 Order Events

Emit:

```text
order.created
order.updated
order.service_added
order.completed
order.cancelled
```

### 7.5 RBAC/Admin Events

Emit:

```text
rbac.role_created
rbac.role_updated
rbac.role_deleted
rbac.permission_added
rbac.permission_removed
rbac.cache_refreshed
```

## 8. Admin API Requirements

Add admin-only API endpoints exposed through the user service admin HTTP API.

These endpoints should read BI data from the separate BI/analytics database. They may enrich results with small, bounded lookups from the OLTP database when needed for display names, but heavy reporting queries should stay off the OLTP database.

Initial endpoints:

```text
GET /api/admin/business-events
GET /api/admin/business-events/{id}
GET /api/admin/intelligence/summary
GET /api/admin/intelligence/insights
PATCH /api/admin/intelligence/insights/{id}
POST /api/admin/intelligence/generate
```

### 8.1 `GET /api/admin/business-events`

Query parameters:

```text
event_type
source
severity
customer_id
order_id
service_id
actor_user_id
from
to
limit
cursor
```

Default behavior:

- Return latest events first.
- Default limit: 100.
- Maximum limit: 500.

### 8.2 `GET /api/admin/intelligence/summary`

Return a current executive summary.

Initial non-AI version may return deterministic statistics:

```text
total users
total customers
total orders
orders created in last 7 days
services assigned in last 7 days
top services
recent high-signal events
latest AI insights
```

### 8.3 `POST /api/admin/intelligence/generate`

Triggers AI insight generation.

Request body:

```json
{
  "window": "7d",
  "focus": "executive_summary"
}
```

The first implementation may be manual and admin-triggered. Later this can run on a schedule.

## 9. Admin UI Requirements

Add a new admin UI section:

```text
/admin/intelligence
```

Initial tabs:

```text
Summary
Recommendations
Business Events
Experiments
```

### 9.1 Summary Tab

Show:

- Executive summary
- High-priority recommendations
- Business activity counts
- Top service activity
- Recent changes

### 9.2 Recommendations Tab

Show AI insights as cards or rows.

Each insight should display:

```text
priority
type
title
summary
recommendation
confidence
evidence
status
created_at
```

Admin actions:

```text
Mark reviewed
Accept
Dismiss
Mark implemented
```

### 9.3 Business Events Tab

Show a searchable/filterable event stream.

Filters:

```text
event type
source
severity
date range
customer
order
service
actor
```

This is not a raw log viewer. It is a business activity feed.

### 9.4 Experiments Tab

This can be placeholder-only at first.

Future use:

- Discount experiments
- Service bundle tests
- Agent workflow experiments
- Customer retention campaigns

## 10. AI Insight Generation

The AI should not receive unbounded raw data.

The system should prepare a compact insight packet first.

Example packet:

```json
{
  "window": "7d",
  "counts": {
    "orders_created": 22,
    "services_assigned": 31,
    "customers_created": 8
  },
  "top_services": [
    {"service": "Bathroom plumbing", "assigned": 14},
    {"service": "Electrical trim", "assigned": 7}
  ],
  "recent_events": [
    {
      "event_type": "service.assigned_to_customer",
      "created_at": "2026-05-18T10:00:00Z",
      "metadata": {}
    }
  ]
}
```

The AI should return structured JSON.

Recommended response shape:

```json
{
  "executive_summary": "Short summary here.",
  "insights": [
    {
      "insight_type": "discount_experiment",
      "priority": "medium",
      "title": "Test bundle discount for bathroom services",
      "summary": "Bathroom-related services are frequently assigned together.",
      "recommendation": "Offer a 10% bundle discount when plumbing and fixtures are selected together.",
      "confidence": 0.72,
      "evidence": {
        "window": "7d",
        "service_names": ["Bathroom plumbing", "Bathroom faucets"]
      }
    }
  ]
}
```

Requirements:

1. AI output must be parsed and validated before saving.
2. Failed AI generation must not affect normal application behavior.
3. Store evidence so admins can understand why a recommendation was made.
4. Do not send passwords, tokens, secrets, or unnecessary personal data to AI.
5. Prefer aggregated facts over raw individual records.

## 11. Privacy and Safety Requirements

1. Do not store sensitive secrets in business events.
2. Do not send raw JWTs, passwords, API keys, or database credentials to AI.
3. Avoid sending excessive PII to AI.
4. Use customer IDs and aggregate counts where possible.
5. Admin-only access is required for all BI and AI insight endpoints.
6. Every admin action on insights should be auditable.

## 12. Phased Implementation Plan

### Phase 1: Business Event Foundation

Implement:

- BI/analytics database connection and configuration.
- `business_events` model/table in the BI/analytics database.
- event tracking helper.
- emit events for users, customers, orders, service assignment, and RBAC admin actions.
- admin API to list/filter events.
- admin UI Business Events tab.

Acceptance criteria:

- Admin can see recent business events in the admin UI.
- Events are structured and filterable.
- Normal workflows continue even if event tracking fails.
- Business event reads and writes use the BI/analytics database, not the primary OLTP database.

### Phase 2: Deterministic Intelligence Summary

Implement:

- `/api/admin/intelligence/summary`.
- summary cards and tables in admin UI.
- counts by date range.
- top services.
- recent high-signal events.

Acceptance criteria:

- Admin can open `/admin/intelligence`.
- Page shows useful summary without requiring AI.
- Counts match BI events and any bounded OLTP reference checks.

### Phase 3: AI Insight Generation

Implement:

- insight packet builder.
- AI generation endpoint.
- `ai_insights` model/table in the BI/analytics database.
- save generated insights.
- admin UI Recommendations tab.

Acceptance criteria:

- Admin can trigger insight generation.
- AI-generated recommendations are saved.
- Admin can review, accept, dismiss, or mark insights implemented.

### Phase 4: Scheduled Intelligence

Implement:

- scheduled insight generation.
- configurable windows such as daily, weekly, monthly.
- duplicate detection to avoid repeated recommendations.

Acceptance criteria:

- System can generate weekly executive summaries automatically.
- Admin UI shows latest summary and prior summaries.

### Phase 5: Experiments and Feedback Loop

Implement:

- experiments table.
- connect accepted recommendations to experiments.
- track outcomes.
- let AI learn from accepted/dismissed/implemented insight status.

Acceptance criteria:

- Admin can turn a recommendation into an experiment.
- System can compare before/after performance.
- AI recommendations improve based on feedback.

## 13. First Baby-Step Task For Codex

When implementation begins, start here:

1. Add `BusinessEventEntity` model.
2. Add BI database configuration and connection.
3. Add migration through GORM auto-migration against the BI database.
4. Add `TrackBusinessEvent` helper that writes to the BI database without blocking OLTP success.
5. Emit:
   - `user.created`
   - `customer.created`
   - `order.created`
   - `service.assigned_to_customer`
   - `rbac.permission_added`
   - `rbac.permission_removed`
6. Add `GET /api/admin/business-events`.
7. Add an Admin UI `Business Events` tab under `/admin/intelligence`.

Do not start with complex AI generation. First make the product produce clean behavioral facts.

## 14. Open Questions

These can be answered during implementation:

1. Should the BI/analytics database initially be a separate database on the same local Postgres server, or a separate Postgres instance from day one?
2. Should event writes go directly to the BI database first, or through an OLTP outbox plus background relay for stronger durability?
3. Should the agent service write events directly, or call the user service/admin API to record events?
4. What OpenAI model should be used for insight generation?
5. How much customer-level detail is acceptable in AI prompts?
6. Should executives see all events, only summaries, or both?
7. Should recommendations be sent by email/slack later?

## 15. Non-Goals For The First Pass

Do not implement these in the first pass:

- Full data warehouse.
- Grafana/Loki integration.
- Real-time streaming analytics.
- Automated discount execution.
- Automated agent behavior changes.
- AI making irreversible business decisions without admin review.

The first pass should create the foundation: structured business events and a simple intelligence surface in the admin UI.
