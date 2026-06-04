Use this prompt with Codex:

```md
Use the builder agent for consistency, architecture integrity, security, and documentation before making any code changes.

Task:
Implement a service-based ATS job import path using a new `ImportATSJobs` API. The crawler must import companies and jobs through platform services, not direct database writes.

Business goal:
`atscrawler` pulls jobs from external ATS providers like Greenhouse. Those jobs should become universal platform career-domain companies and jobs, shared across the system. We must avoid duplicate companies/jobs and preserve service-owned validation, security, timestamps, and future business rules.

Required architecture:
1. Add a bulk import RPC named `ImportATSJobs`.
2. The importer should authenticate as an `agent` user, not admin.
3. The crawler should call the service API over gRPC.
4. Do not write directly to the database from `atscrawler`.
5. Import should be batch-oriented, not one RPC per job.

Required builder-agent workflow:
Run builder discovery first:

- `ceerat-builder codex-context --output json`
- `ceerat-builder docs all --output json`
- `ceerat-builder inventory contracts --output json`
- `ceerat-builder inventory services --output json`
- `ceerat-builder inventory apps --output json`
- `ceerat-builder evidence request "service based ATS import using ImportATSJobs with agent authentication and batch company job upsert" --output json`
- `ceerat-builder patterns service --output json`
- `ceerat-builder patterns grpc-security --output json`
- `ceerat-builder patterns testing --output json`
- `ceerat-builder rbac check --output json`
- `ceerat-builder check drift --output json`

Use builder output as factual context, not final design.

Scope:
- Contract owner:
  - `contracts-repo/packages/ceerat-contracts/proto/career/career.proto`
- Service implementation owner:
  - `services-repo/services/ceerat-user-service/careers`
- Crawler client owner:
  - `atscrawler`
- Documentation/inventory owners:
  - `contracts-repo/docs/contract-inventory.json`
  - `services-repo/docs/grpc-service-inventory.json`
  - `services-repo/services/ceerat-user-service/docs/api.md`
  - `services-repo/services/ceerat-user-service/docs/grpc-security.md`
  - builder-agent docs if this becomes a durable platform standard

Contract requirements:
Add an import API to the Career service. Prefer something like:

```proto
message ImportATSJobsRequest {
  string provider = 1;              // greenhouse, lever, workday, etc.
  string company_name = 2;
  string external_company_id = 3;   // Greenhouse board token like stripe
  repeated ATSJob jobs = 4;
}

message ATSJob {
  string title = 1;
  string description = 2;
  string location = 3;
  string employment_type = 4;
  string status = 5;
  double salary_min = 6;
  double salary_max = 7;
  string category = 8;
  string remote_type = 9;
  string posted_date = 10;
  string closing_date = 11;
  string source_url = 12;
  string external_job_id = 13;
}

message ImportATSJobsResponse {
  Company company = 1;
  int32 jobs_received = 2;
  int32 jobs_created = 3;
  int32 jobs_updated = 4;
  int32 jobs_skipped = 5;
  repeated ImportATSJobResult results = 6;
}

message ImportATSJobResult {
  string external_job_id = 1;
  string job_id = 2;
  string action = 3; // created, updated, skipped
  repeated string errors = 4;
}
```

Use existing naming/style if builder evidence shows a better local pattern.

Security requirements:
1. `ImportATSJobs` must require authenticated `agent` role.
2. Do not allow anonymous import.
3. Do not require admin role.
4. Do not trust request-supplied user ids.
5. Use existing JWT/auth interceptor patterns.
6. Validate caller role from service context.
7. Enforce batch limits to prevent abuse:
   - reasonable max jobs per request, for example 500 or builder-recommended value
   - reject empty provider/company/jobs
   - reject missing job title
   - reject missing external_job_id when source/provider requires it
8. Sanitize imported text fields using existing service mapping/validation conventions.
9. Do not store secrets or tokens in company/job records.
10. Do not weaken existing customer/admin/agent RBAC.

Deduplication/upsert requirements:
1. Companies are universal career-domain records.
2. Jobs are universal career-domain records.
3. Company matching should use:
   - normalized company name
   - provider/source
   - external_company_id where available
4. Job matching should use:
   - company_id
   - source/provider
   - external_job_id
5. If company exists, reuse it.
6. If company does not exist, create it.
7. If job exists, update mutable fields:
   - title
   - description
   - location
   - employment_type
   - status
   - salary_min/salary_max
   - category
   - remote_type
   - posted_date
   - closing_date
   - source_url
8. If job does not exist, create it.
9. Preserve existing IDs and created_at for updates.
10. Set/update `updated_at` through existing repository/service patterns.
11. Avoid duplicate jobs when the same Greenhouse feed is imported multiple times.
12. If the existing company does not have matching fields from the ATS then exten the company schema at both DB and services layer to make it accomodating to ATS.  For your current Job model, the natural idempotency keys are:

companies:
  normalized(name)
  source
  external_company_id / board token if you add one

jobs:
  company_id
  source
  external_job_id
I would add external_company_id or ats_board_token to Company if it does not already exist. Otherwise Stripe from Greenhouse and Stripe from another source may be hard to reconcile cleanly.

Repository/service requirements:
1. Add repository methods only where needed, for example:
   - find company by normalized name/source/external id
   - create company
   - find job by source/external_job_id/company_id
   - create job
   - update job from ATS import
2. Keep SQL in the service repository layer, not in the crawler.
3. Prefer transactions for the batch import if local patterns support them.
4. If full transaction support is not established, make the import idempotent and safe to retry.
5. Return per-job results so partial failures are visible.
6. Follow existing model mapping style.

Crawler requirements:
1. Extend `atscrawler` so it can either:
   - print pulled jobs, or
   - import pulled jobs into Ceerat via `ImportATSJobs`.
2. Add flags such as:
   - `-import`
   - `-ceerat-service-addr`
   - `-auth-token`
   - `-greenhouse-board`
   - `-company`
3. The crawler should call the gRPC Career service with the agent user JWT token.
4. Do not embed credentials in code.
5. Token should come from env var or CLI flag:
   - env: `CEERAT_AGENT_TOKEN`
   - flag: `-auth-token`
6. If `-import` is not set, preserve current print behavior.
7. If `-import` is set, print a concise import summary:
   - company id/name
   - received
   - created
   - updated
   - skipped
8. Keep provider logic separate from service client logic.

Testing requirements:
1. Add service tests for:
   - unauthenticated import rejected
   - customer role rejected
   - agent role accepted
   - empty provider/company/jobs rejected
   - batch limit enforced
   - company create on first import
   - company reuse on second import
   - job create on first import
   - job update on repeated import with same external_job_id
   - no duplicate jobs on repeated import
2. Add crawler tests where practical:
   - import payload mapping
   - auth token metadata attached
   - print mode remains unchanged if existing tests support it
3. Tests should avoid real network calls.

Documentation requirements:
Update docs/inventories if they describe Career service APIs, RBAC, or ATS import:
- contract inventory
- service inventory
- Career API docs
- gRPC security docs
- builder-agent docs if this is now a durable standard:
  - external data ingestion must go through services
  - crawlers/importers must not write direct SQL
  - bulk import APIs should be idempotent and RBAC-protected

Verification:
Run and report results:

In `contracts-repo/packages/ceerat-contracts`:
- proto generation command
- `go test ./...`
- `go build ./...`

In `services-repo/services/ceerat-user-service`:
- `go test ./...`
- `go build ./...`

In `atscrawler`:
- `go test ./...`
- `go build ./...`
- `go build -o bin/ceerat-ats-crawler ./cmd/ceerat-ats-crawler`

Builder checks:
- `ceerat-builder rbac check --output json`
- `ceerat-builder check drift --output json`
- `ceerat-builder check apps --output json`

Expected outcome:
- `ImportATSJobs` exists and is protected for authenticated `agent` role.
- `atscrawler` can pull Greenhouse jobs and import them in a single batch request.
- Companies and jobs are imported as universal career-domain records.
- Re-importing the same feed updates existing records and does not create duplicates.
- No direct database writes happen from `atscrawler`.
- Tests/builds and builder checks pass.
```