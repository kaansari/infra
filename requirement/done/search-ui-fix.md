# Requirement: Typesense Job Search UI + Agent Result Control

## Goal

Improve Ceerat Career job search so customers can use the search dimensions already indexed in Typesense, without exposing Typesense implementation details in the UI. Also make AI agent job search safe for broad queries by returning compact, limited results and requiring detail lookup for one selected job.

This document is both the requirement and a Codex execution prompt.

## Current Context

- Infra workspace is rooted at `infra/`.
- Ceerat workspace root is one level up from infra:
  - `/Users/kaansari/go/src/github.com/kaansari`
- Career service lives at:
  - `../services-repo/services/ceerat-user-service`
- Contracts live at:
  - `../contracts-repo/packages/ceerat-contracts`
- Customer UI lives at:
  - `../apps-repo/apps/ceerat-customer-ui`
- AI agent service lives at:
  - `../apps-repo/ai/ceerat-agent-service`

Current local Typesense dev setup:

- Config file:
  - `infra/typesense.env`
- Docker service file:
  - `infra/docker-compose.typesense.yml`
- Local container:
  - `ceerat-typesense`
- Typesense URL:
  - `http://localhost:8108`
- Collection:
  - `jobs`

Current search flow:

1. Customer browser opens `/customer/career/jobs`.
2. Customer UI JavaScript calls same-origin route `GET /api/jobs/search`.
3. `ceerat-customer-ui` calls `career.JobService/SearchJobs`.
4. `ceerat-user-service` uses Typesense when enabled, then falls back to DB if Typesense fails.
5. Browser never calls Typesense directly.

Current indexed Typesense job dimensions include:

- `company`
- `location`
- `locations`
- `country`
- `remote`
- `hybrid`
- `onsite`
- `employment_type`
- `department`
- `seniority`
- `skills`
- `source`
- `status`

Current public search request is limited. `career.SearchJobsRequest` currently exposes:

- `query`
- `location`
- `employment_type`
- `active_only`
- `page_size`
- `page_token`
- `company_id`
- `remote_type`
- `status`
- `source`

The customer UI currently exposes only:

- keyword
- location
- remote type
- employment type

The AI agent also calls `career.JobService/SearchJobs`; when Typesense is enabled, it uses the same backend path unless `company_id` forces the database path. The agent currently defaults job search page size to 50, which is too large for broad AI responses.

## Product Requirements

### Customer UI

The UI should represent search dimensions as customer-friendly job filters, not as Typesense metadata.

Use customer-facing labels:

- Keyword
- Location
- Company
- Work mode
- Employment type
- Department
- Seniority
- Skills
- Country
- Source

UI behavior:

1. Keep the first row simple:
   - keyword
   - location
2. Add mobile-friendly expandable filters:
   - Company
   - Work mode: Remote, Hybrid, Onsite
   - Employment type
   - Department
   - Seniority
   - Skills
   - Country
   - Source under More filters
3. Show facet counts where available:
   - `Databricks (784)`
   - `Remote (161)`
   - `Engineering (230)`
4. Do not use raw implementation words such as "Typesense metadata" in the UI.
5. Do not call Typesense directly from browser code.
6. Preserve the Ceerat UI standard:
   - `/customer/career/jobs` is the search/list page.
   - `/customer/career/jobs/{id}` is the detail page.
   - detail pages should not render the search/list below them.
   - navigation, breadcrumb, and back button remain consistent.

### Backend/API

Extend job search through the existing Career service boundary unless builder-agent evidence says otherwise.

Preferred API direction:

1. Extend `career.SearchJobsRequest` with:
   - `department`
   - `seniority`
   - repeated `skills`
   - `country`
   - `sort`
   - optional `include_facets`
2. Extend `career.ListJobsResponse` with search metadata:
   - total count
   - page/page size or next token behavior consistent with existing API
   - facet buckets for company, location, source, work mode, employment type, department, seniority, skills, country
3. Keep Typesense behind `ceerat-user-service`.
4. Keep Postgres as source of truth.
5. Keep database fallback behavior.
6. Customers must only see open jobs.
7. Agent/admin behavior must remain protected by existing RBAC rules.
8. If adding or changing proto fields, regenerate protobufs and update docs/inventories.

### AI Agent

AI search must not overload the model with broad result sets.

Requirements:

1. Default agent `search_jobs` result count to 10.
2. Hard cap agent `search_jobs` result count at 20.
3. Return compact search results only:
   - job id
   - title
   - company name
   - location
   - work mode
   - employment type
   - source
   - source URL or application URL if safe
4. Do not return full job descriptions from `search_jobs`.
5. Agent should call `get_job` for one selected job when details are needed.
6. For broad searches, agent should either:
   - ask a narrowing question, or
   - show top matching jobs plus available filter/facet suggestions.
7. Preserve service-owned auth/session behavior. The agent must not query Typesense directly.

## Security + Architecture Constraints

1. Use the builder agent before making code changes.
2. Run builder-agent discovery from the Ceerat workspace root, not from `infra`.
3. Browser/customer UI must call same-origin Ceerat APIs only.
4. No Typesense API key should be exposed to frontend code.
5. Typesense remains an implementation detail of `ceerat-user-service`.
6. Customer identity and role must come from auth/JWT context.
7. Customer searches must be forced to open jobs.
8. Do not introduce a new service process unless builder output clearly requires it.
9. Do not bypass `career.JobService/SearchJobs`.
10. Keep DB fallback for search.
11. Add tests for contract/service/UI/agent changes.
12. Update docs and builder inventories if contracts, app surfaces, or RBAC-protected methods change.

## Builder-Agent Discovery Commands

Run these from:

```bash
cd /Users/kaansari/go/src/github.com/kaansari
```

Required commands:

```bash
ceerat-builder codex-context --output json
ceerat-builder docs all --output json
ceerat-builder inventory services --output json
ceerat-builder inventory contracts --output json
ceerat-builder inventory apps --output json
ceerat-builder decide-owner "faceted customer job search UI and AI-safe job search limits for Typesense-backed Career jobs" --output json
ceerat-builder evidence request "extend career job search API with customer-friendly facets and cap AI agent job search results while keeping Typesense behind ceerat-user-service" --output json
ceerat-builder patterns service --output json
ceerat-builder patterns grpc-security --output json
ceerat-builder patterns repository --output json
ceerat-builder patterns testing --output json
ceerat-builder patterns apps --output json
ceerat-builder app-context --output json
ceerat-builder app-context ceerat-customer-ui --output json
ceerat-builder app-context ceerat-agent-service --output json
ceerat-builder app-surface ceerat-customer-ui --output json
ceerat-builder app-surface ceerat-agent-service --output json
ceerat-builder app-match "customer career faceted job search and AI-safe search result summarization" --output json
ceerat-builder app-impact ceerat-customer-ui --route "GET /customer/career/jobs" --surface "faceted customer job search page" --output json
ceerat-builder app-impact ceerat-customer-ui --route "GET /api/jobs/search" --surface "same-origin customer job search API wrapper" --output json
ceerat-builder app-impact ceerat-agent-service --surface "AI search_jobs tool result limit and compact summaries" --output json
ceerat-builder rbac check --output json
ceerat-builder check drift --output json
ceerat-builder check apps --output json
ceerat-builder plan --output json "implement faceted customer job search UI and AI-safe Typesense-backed job search"
```

If any builder command fails because a repo, inventory, or tool is missing, stop and report the missing prerequisite before editing.

Use builder output as factual context, not final design. The final design must still be based on the actual code currently present in the workspace.

## Required Code Inspection

Before implementing, read these files:

Contracts:

- `../contracts-repo/packages/ceerat-contracts/proto/career/career.proto`
- `../contracts-repo/packages/ceerat-contracts/security/grpc_methods.go`

Career service:

- `../services-repo/services/ceerat-user-service/careers/handler.go`
- `../services-repo/services/ceerat-user-service/careers/repository.go`
- `../services-repo/services/ceerat-user-service/careers/jobsearch/schema.go`
- `../services-repo/services/ceerat-user-service/careers/jobsearch/service.go`
- `../services-repo/services/ceerat-user-service/careers/jobsearch/client.go`
- `../services-repo/services/ceerat-user-service/careers/jobsearch/normalizer.go`
- `../services-repo/services/ceerat-user-service/docs/api.md`

Customer UI:

- `../apps-repo/apps/ceerat-customer-ui/internal/server/server.go`
- `../apps-repo/apps/ceerat-customer-ui/internal/apiclient/client.go`
- `../apps-repo/apps/ceerat-customer-ui/web/templates/career_jobs.html`
- `../apps-repo/apps/ceerat-customer-ui/web/static/app.js`
- `../apps-repo/apps/ceerat-customer-ui/docs/ui-rendering-standard.md`

AI agent:

- `../apps-repo/ai/ceerat-agent-service/internal/agent/tools.go`
- `../apps-repo/ai/ceerat-agent-service/internal/platform/client.go`
- `../apps-repo/ai/docs/agent-tools.md`

Infra/local search:

- `infra/typesense.env`
- `infra/docker-compose.typesense.yml`
- `infra/common.sh`
- `infra/start-stack.sh`

## Implementation Prompt For Codex

```text
You are working in the Ceerat multi-repo workspace.

Goal:
Implement a customer-friendly faceted job search UI for Typesense-backed Career jobs, and make AI agent job search safe for broad queries.

Use the Ceerat builder agent first for security, architecture integrity, ownership, API consistency, app-surface impact, RBAC drift, and testing guidance.

Run builder discovery from `/Users/kaansari/go/src/github.com/kaansari`, not from infra. Run the commands listed in `infra/requirement/search-ui-fix.md`.

After builder discovery, inspect the code files listed in the requirement. Then implement the safest production-ready path.

Constraints:
- Typesense must remain behind `ceerat-user-service`.
- Browser/customer UI must call same-origin Ceerat APIs only.
- AI agent must call Ceerat service APIs only.
- No frontend code may use the Typesense API key.
- Customers must only see open jobs.
- Preserve DB fallback when Typesense is unavailable.
- Preserve existing career navigation, breadcrumbs, and mobile UI standards.
- Do not create a new service process unless builder evidence clearly requires it.

Backend:
- Extend `career.SearchJobsRequest` with any missing filter fields needed for faceted search, preferably:
  - department
  - seniority
  - repeated skills
  - country
  - sort
  - include_facets
- Extend `career.ListJobsResponse` with search metadata/facets if not already present.
- Update generated protobufs.
- Update `KnownGRPCMethods`, `DefaultRolePermissions`, and docs only if method surfaces change.
- Wire new filter fields into `ceerat-user-service/careers/jobsearch.SearchOptions`.
- Return facet buckets from Typesense through the service response.
- Keep database fallback safe if the new fields are not available in DB fallback; document any fallback limitations.
- Add focused service tests for new filters, facets, customer open-job enforcement, and Typesense fallback.

Customer UI:
- Update `/customer/career/jobs` to keep keyword/location prominent.
- Add mobile-friendly expandable filters:
  - Company
  - Work mode
  - Employment type
  - Department
  - Seniority
  - Skills
  - Country
  - Source
- Show facet counts when available.
- Use customer-friendly labels; do not expose Typesense terminology.
- Keep list and detail pages separate.
- Ensure jobs list still links to `/customer/career/jobs/{id}`.
- Add route/render or JS tests where the repo has a local pattern.

AI agent:
- Cap `search_jobs` to 20 results maximum.
- Default `search_jobs` to 10 results.
- Return compact job summaries from search, not full descriptions.
- Keep `get_job` as the path for full details.
- Add tests proving broad search does not return huge/full-detail payloads.
- Update `ai/docs/agent-tools.md`.

Docs:
- Update user-service API docs.
- Update customer UI docs if the search UI standard changes.
- Update agent tool docs.
- Update any builder inventories/docs required by the repo process.

Verification:
- Run relevant proto generation/build commands.
- Run contract tests.
- Run ceerat-user-service tests.
- Run ceerat-customer-ui tests/build.
- Run ceerat-agent-service tests/build.
- Run builder checks:
  - `ceerat-builder rbac check --output json`
  - `ceerat-builder check drift --output json`
  - `ceerat-builder check apps --output json`
- With local Typesense running, rebuild the jobs index and verify:
  - collection has documents
  - direct service/customer search returns facet-backed results
  - broad AI search returns compact capped results

Deliverables:
1. Summarize builder-agent findings.
2. Summarize architecture decision.
3. List changed files.
4. List tests/build commands and results.
5. Mention any fallback limitations or follow-up work.
```

## Acceptance Criteria

- Customer job search page provides useful faceted filters without exposing Typesense details.
- Facet counts appear when the backend returns them.
- Customer UI still uses same-origin APIs only.
- `career.JobService/SearchJobs` remains the service-owned search boundary.
- Typesense remains optional with DB fallback.
- Customer searches are forced to open jobs.
- AI `search_jobs` returns at most 20 compact results.
- AI does not receive full descriptions during broad search.
- `get_job` remains available for one-job detail retrieval.
- Relevant tests and builder checks pass.

