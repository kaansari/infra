Use this prompt with Codex:

```md
Use the builder agent for consistency, architecture integrity, security, documentation, and service standards before making any code changes.

Task:
Implement read-optimized Career market/customer KPI metrics so customer-facing pages and AI tools can show job-market counts without each customer running expensive live count queries over jobs/companies.

Business goal:
The platform now imports universal companies and jobs through `atscrawler` and `career.JobService/ImportATSJobs`. Customer UI needs KPI cards and charts such as:

- Available jobs
- Number of companies
- Number of jobs by employment type
- Jobs by month
- Jobs by location
- Jobs by company/source

Customers should not directly run broad count queries. Customer job search is paginated and limited, so the UI cannot infer total market counts from `/SearchJobs` results. Metrics should be precomputed/read-optimized and returned through a service API.

Required builder-agent workflow:
Run builder discovery first:

- `ceerat-builder codex-context --output json`
- `ceerat-builder docs all --output json`
- `ceerat-builder inventory contracts --output json`
- `ceerat-builder inventory services --output json`
- `ceerat-builder inventory apps --output json`
- `ceerat-builder evidence request "career market and customer KPI metrics aggregate service for customer UI without live count queries" --output json`
- `ceerat-builder patterns service --output json`
- `ceerat-builder patterns grpc-security --output json`
- `ceerat-builder patterns testing --output json`
- `ceerat-builder rbac check --output json`
- `ceerat-builder check drift --output json`

Use builder output as factual context, not final design.

Architecture requirements:
1. Keep metrics owned by `ceerat-user-service`.
2. Do not let apps or AI clients query the database directly.
3. Do not make customer UI compute global counts from paginated job search.
4. Prefer extending the existing Career domain boundary instead of creating a new service process.
5. Add read-optimized aggregate persistence for global career market metrics.
6. Keep customer-specific workflow metrics separate from global market metrics.

Recommended data model:

Global market metrics table:

```text
career_market_metrics
- id
- scope_type              // "global" initially; future: segment
- scope_id                // empty for global
- metric_date             // optional date/month bucket
- available_jobs
- company_count
- remote_job_count
- job_type_counts_json
- jobs_by_month_json
- jobs_by_location_json
- jobs_by_company_json
- source_counts_json
- generated_at
- created_at
- updated_at
```

Customer workflow metrics table:

```text
customer_career_metrics
- id
- customer_id
- saved_jobs_count
- applications_count
- submitted_count
- reviewing_count
- interview_count
- rejected_count
- offered_count
- withdrawn_count
- resume_count
- skill_profile_count
- generated_at
- created_at
- updated_at
```

Implementation requirements:
1. Add a Career metrics API. Prefer one of:
   - extend `career.JobService` with `GetCareerMarketMetrics`
   - or add `career.CareerAnalyticsService` if builder evidence says a separate service inside the same process is cleaner
2. Add customer workflow metrics API if in scope:
   - `GetMyCareerMetrics`
   - customer id must be derived from authenticated JWT, not request-supplied ids
3. Return sanitized aggregate data only.
4. Metrics responses should include generated timestamp so the UI can show freshness if needed.
5. Refresh global market metrics after `ImportATSJobs` completes successfully.
6. Add repository refresh method(s) that compute aggregates inside `ceerat-user-service`.
7. Do not block import on noncritical metrics refresh failure unless builder/service standards recommend otherwise. Prefer logging and returning import success if jobs imported safely.
8. Keep metrics idempotent and recomputable.
9. Add a service method or internal function to recompute metrics on demand for tests/admin tooling.
10. Use JSON fields only for aggregate buckets where a fixed protobuf repeated message would be too rigid; otherwise prefer structured repeated protobuf messages.

Suggested proto shape:

```proto
message MetricBucket {
  string key = 1;
  string label = 2;
  int64 count = 3;
}

message GetCareerMarketMetricsRequest {}

message CareerMarketMetricsResponse {
  int64 available_jobs = 1;
  int64 company_count = 2;
  int64 remote_job_count = 3;
  repeated MetricBucket jobs_by_type = 4;
  repeated MetricBucket jobs_by_month = 5;
  repeated MetricBucket jobs_by_location = 6;
  repeated MetricBucket jobs_by_company = 7;
  repeated MetricBucket jobs_by_source = 8;
  string generated_at = 9;
  repeated Error errors = 10;
}

message GetMyCareerMetricsRequest {}

message CustomerCareerMetricsResponse {
  int64 saved_jobs_count = 1;
  int64 applications_count = 2;
  int64 submitted_count = 3;
  int64 reviewing_count = 4;
  int64 interview_count = 5;
  int64 rejected_count = 6;
  int64 offered_count = 7;
  int64 withdrawn_count = 8;
  int64 resume_count = 9;
  int64 skill_profile_count = 10;
  string generated_at = 11;
  repeated Error errors = 12;
}
```

Use existing proto naming/style if local patterns differ.

Security requirements:
1. Metrics RPCs must be protected.
2. Customer users may read global market metrics.
3. Customer users may read only their own customer workflow metrics.
4. Agent/admin users may read global market metrics.
5. Do not expose private customer/application details in market metrics.
6. Do not trust browser-supplied customer ids.
7. Do not add public unauthenticated metrics endpoints unless explicitly approved.
8. Update `KnownGRPCMethods` and `DefaultRolePermissions`.
9. Update app/API routes to enforce authenticated session before metrics calls.

App requirements:
1. Update `apps-repo/apps/ceerat-customer-ui` home page to call the metrics API through its backend server.
2. Add a same-origin route such as:
   - `GET /api/customer/career/metrics`
3. Render KPI cards:
   - Available jobs
   - Companies
   - Job types
   - Remote roles
4. Render charts:
   - Jobs by month
   - Jobs by type
5. Use existing customer UI style conventions.
6. Do not compute global counts from paginated `/api/customer/career/jobs` results.
7. Keep charts lightweight and dependency-free unless the app already has a charting library.
8. Ensure the page works on mobile and desktop.

AI requirements:
1. If AI agent tools need market metrics, add a read-only tool that calls the metrics API.
2. The tool should return aggregate metrics only.
3. Do not let model text supply user/customer ids for ownership.

Documentation requirements:
Update docs/inventories:

- `contracts-repo/docs/contract-inventory.json`
- `services-repo/docs/grpc-service-inventory.json`
- `services-repo/services/ceerat-user-service/docs/api.md`
- `services-repo/services/ceerat-user-service/docs/grpc-security.md`
- `apps-repo/docs/app-surface-inventory.json` if customer UI routes change
- `ceerat-platform-builder-agent/.ceerat-agent/service-standards.md` only if this becomes a durable standard:
  - KPI dashboards should use service-owned aggregate tables/read models, not app-side broad count queries.

Testing requirements:
1. Add service tests for:
   - global market metric refresh after imported jobs
   - jobs by type/month/location/company/source aggregation
   - customer role can read global market metrics
   - unauthenticated metrics calls are rejected
   - customer workflow metrics derive customer id from JWT
2. Add app tests for:
   - metrics route requires session
   - metrics route forwards authenticated token
   - home page includes metrics containers
3. Avoid real network calls.

Verification:
Run and report:

In `contracts-repo/packages/ceerat-contracts`:
- proto generation command
- `go test ./...`
- `go build ./...`

In `services-repo/services/ceerat-user-service`:
- `go test ./...`
- `go build ./...`

In `apps-repo/apps/ceerat-customer-ui`:
- `go test ./...`
- `go build ./...`

Builder checks:
- `ceerat-builder rbac check --output json`
- `ceerat-builder check drift --output json`
- `ceerat-builder check apps --output json`

Expected outcome:
- Customer UI displays KPI cards and charts using precomputed service-owned metrics.
- Metrics are not computed from paginated job search results.
- Global market metrics are safe for customers to read.
- Customer workflow metrics are scoped to the authenticated customer.
- Imports can refresh aggregate metrics after job upserts.  Make sure to update the atscrawler so after each import KPI data is renewed / updated.
- Tests/builds and builder checks pass.
```
