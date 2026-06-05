# Applying Jobs: Proposal And Codex Prompt

## Proposal

### Summary

Ceerat should support applying to imported ATS jobs through a service-owned application workflow, not directly from the crawler, browser, or AI model.

The current platform already has:

- universal company/job records imported by `atscrawler`
- customer skill profiles and resumes
- internal Ceerat job application records
- authenticated customer UI and AI customer tools

The missing capability is external ATS application submission. Greenhouse is the first provider, but the design should support Lever, Ashby, Workday, SmartRecruiters, and provider-specific form schemas later.

### Recommended Architecture

```text
Customer UI / Customer AI Tool
  -> ceerat-customer-ui / ceerat-agent-service
  -> career.JobApplicationService
  -> ATS Application Adapter
  -> Greenhouse public application endpoint
  -> persisted application/submission audit records
```

Do not submit applications from `atscrawler`. The crawler should continue importing universal jobs only. Application submission is customer-owned, authenticated, consent-based, and should be handled by the Career service.

### Why Service-Owned

Application submission touches private customer data:

- name
- email
- phone
- resume PDF/text
- cover letter
- optional links
- custom question answers
- submission status and provider response

So the backend service must own:

- auth/RBAC/ownership checks
- resume/profile validation
- provider field discovery
- required-question validation
- submission audit trail
- rate limiting / retry policy
- provider-specific adapters
- sensitive response sanitization

Apps and AI tools should only call service APIs. They must not call Greenhouse directly and must not trust model-supplied `customer_id`.

### Proposed Capability Phases

#### Phase 1: Discover And Draft

Add a service API that discovers provider application fields for an imported job and returns a normalized application form.

Example:

- customer selects a job
- service reads the universal job record
- service inspects `job.source`, `job.source_url`, `job.external_job_id`
- Greenhouse adapter fetches:
  - job detail
  - questions/form fields
- service returns a sanitized normalized form

This lets UI/AI tell the customer what is required before submitting.

#### Phase 2: Submit With Explicit Confirmation

Add a service API that submits a completed application to the provider.

Submission should require:

- authenticated customer
- open job
- selected resume owned by the customer
- selected skill profile owned by the customer when required
- all required provider questions answered
- explicit customer confirmation from UI or AI flow

The service should create/update an internal application record and persist a provider submission record.

#### Phase 3: Provider Expansion

Introduce provider adapters behind a common interface:

```text
ApplicationProvider
  Discover(ctx, job) -> ApplicationForm
  Submit(ctx, application) -> ProviderSubmissionResult
```

Greenhouse is the first adapter. Other providers can follow without changing app/AI behavior.

### Proposed Contract Shape

Extend the existing Career boundary. Prefer `career.JobApplicationService` because this is an application workflow, not a new service process.

Suggested RPCs:

```proto
rpc DiscoverJobApplication(DiscoverJobApplicationRequest) returns (DiscoverJobApplicationResponse) {}
rpc SubmitJobApplication(SubmitJobApplicationRequest) returns (JobApplicationResponse) {}
```

Suggested messages:

```proto
message DiscoverJobApplicationRequest {
  string job_id = 1;
}

message ApplicationQuestion {
  string key = 1;
  string label = 2;
  string type = 3;
  bool required = 4;
  repeated string options = 5;
  string provider_field_id = 6;
}

message DiscoverJobApplicationResponse {
  string job_id = 1;
  string provider = 2;
  string provider_job_id = 3;
  string application_url = 4;
  repeated ApplicationQuestion questions = 5;
  repeated string required_fields = 6;
  repeated Error errors = 7;
}

message ApplicationAnswer {
  string key = 1;
  string value = 2;
}

message SubmitJobApplicationRequest {
  string job_id = 1;
  string skill_profile_id = 2;
  string resume_id = 3;
  string cover_letter = 4;
  repeated ApplicationAnswer answers = 5;
  bool confirmed = 6;
}
```

Remove the existing `ApplyToJob` internal-only workflow unless builder evidence shows it should be kept. Safer path: add explicit external-submission RPCs first, then decide whether customer UI buttons should call the new submit flow instead of the current internal apply flow.

Wire the existing KPI number and KPI display to the new job submission.



### Persistence Proposal

Add a provider submission table owned by `ceerat-user-service`:

```text
job_application_submissions
- id
- job_application_id
- customer_id
- job_id
- provider
- provider_job_id
- provider_submission_id
- provider_status
- application_url
- request_summary_json
- response_summary_json
- error_summary
- submitted_at
- created_at
- updated_at
```

Do not store raw provider response bodies if they may contain sensitive or unnecessary data. Store sanitized summaries and provider ids/statuses.

### Greenhouse Adapter Notes

Greenhouse has a public Job Board API for job discovery. Application forms are provider/company/job-specific and may require:

- multipart resume upload
- custom questions
- consent fields
- EEOC/demographic fields
- anti-spam or validation behavior

Implementation should not assume every Greenhouse job is submittable with only name/email/phone/resume. Discovery must inspect questions dynamically.

If a Greenhouse job cannot be submitted through the public endpoint, the service should return a clear `manual_application_required` status with the `source_url`.

### AI Tool Proposal

Add customer AI tools only after service APIs exist:

- `discover_job_application`
- `submit_job_application`

Rules:

- AI may discover requirements.
- AI may prepare a submission summary.
- AI must ask for explicit confirmation before submit.
- AI must never submit based only on ambiguous user text.
- AI must never invent answers to required questions.
- AI must not accept `customer_id`.

### Security Requirements

- Customer identity must come from JWT.
- Resume and skill profile must belong to authenticated customer.
- Customers can apply only to open jobs visible to customers.
- Provider requests must not include password/session/token secrets.
- Submit RPC must require `confirmed=true`.
- Store sanitized audit data only.
- Avoid raw provider response logging.
- Add rate limiting or submission throttle if builder/service standards support it.
- Do not make external submit APIs public.

### Recommended MVP

Build in this order:

1. Contract messages/RPCs for discovery and submit.
2. Repository table for provider submissions.
3. Greenhouse adapter for `Discover`.
4. Submit validation and internal application record creation.
5. Greenhouse `Submit` only for forms whose required fields are supported.
6. Customer UI discovery/submit flow.
7. Customer AI tool integration with explicit confirmation.
8. Docs/inventories/builder standards.

## Codex Prompt

Use this prompt with Codex:

```md
Use the builder agent for consistency, architecture integrity, security, documentation, and service standards before making any code changes.

Task:
Implement a service-owned external ATS job application workflow for imported Career jobs, starting with Greenhouse discovery and a guarded submission path.

Context:
`atscrawler` imports universal companies and jobs into the Career domain. Imported jobs may include:

- `source`
- `source_url`
- `external_job_id`

Greenhouse has separate public job board APIs and provider-specific application forms. The crawler can fetch jobs, but it should not submit applications. Application submission is customer-owned and must be authenticated, audited, and consent-based.

Current platform already has:

- `career.JobService` for companies/jobs/imports
- `career.CareerProfileService` for skill profiles/resumes
- `career.JobApplicationService` for internal application records
- customer UI career pages
- customer AI tools for resumes/jobs/applications

Required builder-agent workflow:
Run builder discovery first:

- `ceerat-builder codex-context --output json`
- `ceerat-builder docs all --output json`
- `ceerat-builder inventory contracts --output json`
- `ceerat-builder inventory services --output json`
- `ceerat-builder inventory apps --output json`
- `ceerat-builder evidence request "external ATS job application submission workflow for Greenhouse jobs using authenticated customer resumes and explicit confirmation" --output json`
- `ceerat-builder patterns service --output json`
- `ceerat-builder patterns grpc-security --output json`
- `ceerat-builder patterns testing --output json`
- `ceerat-builder rbac check --output json`
- `ceerat-builder check drift --output json`

Use builder output as factual context, not final design.

Architecture requirements:
1. Keep the capability inside the existing Career domain owned by `ceerat-user-service`.
2. Prefer extending `career.JobApplicationService`.
3. Do not create a new service process unless builder evidence clearly requires it.
4. Do not submit applications from `atscrawler`.
5. Apps and AI tools must call backend service APIs only.
6. Customer identity must come from the authenticated JWT, not request params or model text.
7. Treat external ATS submission as different from the current internal Ceerat application record.

Contract requirements:
1. Update `contracts-repo/packages/ceerat-contracts/proto/career/career.proto`.
2. Add protected RPCs, preferably:
   - `DiscoverJobApplication`
   - `SubmitJobApplication`
3. Add normalized application form messages:
   - `ApplicationQuestion`
   - `ApplicationAnswer`
   - discovery response with provider, provider job id, application url, questions, required fields, and errors
4. Add submit request with:
   - `job_id`
   - `skill_profile_id`
   - `resume_id`
   - `cover_letter`
   - repeated answers
   - `confirmed`
5. Regenerate protobuf Go files with the normal proto command.
6. Update `KnownGRPCMethods` and `DefaultRolePermissions`.
7. Customer role may call discovery and submit for self-service.
8. Agent/admin may review/list applications through existing review methods, but do not broaden submit permissions unless explicitly needed.

Persistence requirements:
1. Add a service-owned provider submission model/table:
   - `job_application_submissions`
2. Store:
   - internal job application id
   - customer id
   - job id
   - provider
   - provider job id
   - provider submission id/status when available
   - application url
   - sanitized request summary JSON
   - sanitized response summary JSON
   - error summary
   - submitted timestamp
3. Do not store raw provider response bodies or secrets.
4. Keep records idempotent where practical. Prevent accidental duplicate submissions for the same customer/job unless explicitly supported.

Greenhouse adapter requirements:
1. Add a provider adapter package inside `ceerat-user-service`, under the Career implementation boundary.
2. Implement discovery for Greenhouse job forms using job `source`, `source_url`, and `external_job_id`.
3. Fetch Greenhouse job detail with questions when possible.
4. Normalize provider questions into `ApplicationQuestion`.
5. Implement submit only for supported field sets.
6. If a job cannot be submitted programmatically, return a clear manual-application-required result with the job `source_url`.
7. Avoid real network calls in unit tests; use an injectable HTTP client or provider interface.

Submission requirements:
1. `SubmitJobApplication` must:
   - require authenticated customer
   - derive `customer_id` from JWT
   - require `confirmed=true`
   - verify job is open/customer-visible
   - verify selected resume belongs to the customer
   - verify selected skill profile belongs to the customer when provided/required
   - validate required provider questions
   - create or update the internal Ceerat application record
   - submit to provider when supported
   - persist sanitized provider submission audit
2. Do not invent answers for required provider questions.
3. Do not leak raw resume bytes into logs/model output.
4. If provider submit fails, persist sanitized failure state and return a clear error/status.

Customer UI requirements:
1. Add same-origin API routes in `apps-repo/apps/ceerat-customer-ui`:
   - `GET /api/customer/career/jobs/{id}/application-form`
   - `POST /api/customer/career/jobs/{id}/submit-application`
2. Use existing session/JWT forwarding pattern.
3. Update career job/application UX so customers can:
   - discover required application fields
   - choose a resume/profile
   - answer custom questions
   - review summary
   - explicitly confirm submit
4. Preserve existing internal application list behavior.
5. Do not submit without a confirmation action.

AI customer tool requirements:
1. Add customer tools only after backend service APIs exist:
   - `discover_job_application`
   - `submit_job_application`
2. AI may discover requirements and prepare a summary.
3. AI must ask for explicit confirmation before calling submit.
4. AI must not accept or pass `customer_id`.
5. AI must not invent required question answers.
6. Update customer system prompt and tests.

Documentation requirements:
Update:

- `contracts-repo/docs/contract-inventory.json`
- `services-repo/docs/grpc-service-inventory.json`
- `services-repo/services/ceerat-user-service/docs/api.md`
- `services-repo/services/ceerat-user-service/docs/grpc-security.md`
- `apps-repo/docs/app-surface-inventory.json`
- `apps-repo/ai/docs/agent-tools.md` if AI tools are added
- builder-agent docs only if the external ATS application adapter pattern becomes durable

Testing requirements:
Add tests for:

- discovery requires authenticated customer
- discovery normalizes Greenhouse questions
- submit rejects unauthenticated calls
- submit rejects `confirmed=false`
- submit derives customer id from JWT
- submit rejects resume/profile not owned by customer
- submit rejects missing required answers
- submit records sanitized provider success/failure
- duplicate-submission behavior
- app routes require session and forward JWT
- AI tools are customer-safe and require confirmation

Avoid real network calls.

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

In `apps-repo/ai/ceerat-agent-service` if AI tools are added:
- `go test ./...`
- `go build ./...`

Builder checks:
- `ceerat-builder rbac check --output json`
- `ceerat-builder check drift --output json`
- `ceerat-builder check apps --output json`

Expected outcome:
- Customers can discover ATS application requirements for imported jobs.
- Customers can submit supported Greenhouse applications through a guarded service API.
- Submissions are authenticated, consent-based, audited, and sanitized.
- Existing internal application behavior remains compatible.
- Apps and AI tools do not call ATS providers directly.
```
