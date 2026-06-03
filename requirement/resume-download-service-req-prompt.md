```text
Use ceerat-platform-builder-agent as your discovery and consistency tool before implementing.

I want you to design and implement a backend-only resume download service capability in the Ceerat platform.

Business context:
- Ceerat already has User, Customer, Auth/JWT, RBAC, customer portal, web/admin UI, ceerat-agent-service, and Career domain services.
- Resume records already exist in the Career domain and are customer-owned.
- Existing resume data is stored on `Resume` / `ResumeEntity` with fields such as `title`, `name`, `content`, `content_text`, `file_url`, `version`, and `is_active`.
- The first required capability is backend-only: pull an authenticated customer's resume and return it as a downloadable PDF.
- Do not implement frontend UI in this task.
- Do not implement TXT download in this task unless it falls out naturally as a contract enum; the first functional requirement is PDF only.
- Do not introduce a separate document-storage service unless builder evidence shows an existing document/export boundary that should own it.

Business requirements:
- Allow an authenticated customer to download one of their own resumes as a PDF.
- The service must load the resume from the local Ceerat database through the existing Career service/repository patterns.
- The service must render the resume's available text content into a PDF response.
- Prefer `content_text` as the source body when present; fall back to `content`.
- Use a safe filename derived from resume `name` or `title`, falling back to `resume-<id>.pdf`.
- Return bytes and metadata needed by callers to serve a browser download:
  - file bytes
  - file name
  - content type
  - format
  - resume id
- The first supported format is PDF.
- A future TXT format may be added later, but this task should not require frontend UX.

Before coding, run:

- `ceerat-builder codex-context --output json`
- `ceerat-builder docs all --output json`
- `ceerat-builder inventory services --output json`
- `ceerat-builder inventory contracts --output json`
- `ceerat-builder inventory apps --output json`
- `ceerat-builder decide-owner "download authenticated customer resume as PDF from Career resume data" --output json`
- `ceerat-builder evidence request "download authenticated customer resume as PDF from Career resume data" --output json`
- `ceerat-builder patterns service --output json`
- `ceerat-builder patterns grpc-security --output json`
- `ceerat-builder patterns repository --output json`
- `ceerat-builder patterns testing --output json`
- `ceerat-builder cookbook service --output json`
- `ceerat-builder rbac check --output json`
- `ceerat-builder check drift --output json`
- `ceerat-builder plan --output json "download authenticated customer resume as PDF from Career resume data"`

Use builder output as factual context, not final design.

Ownership expectation:
- Prefer extending the existing Career contract/service boundary if builder inventory confirms resumes already belong to `career.CareerProfileService` in `ceerat-user-service`.
- Expected contract owner: `contracts-repo/packages/ceerat-contracts/proto/career/career.proto`.
- Expected implementation owner: `services-repo/services/ceerat-user-service/careers`.
- Do not put resume export logic directly in `ceerat-customer-ui`, `ceerat-web-ui`, or `ceerat-agent-service`.
- Do not create a new gRPC service unless builder evidence clearly says Career should not own this capability.

Contract requirements:
Extend the existing `career` proto package.

Add a request message similar to:

```proto
message DownloadResumeRequest {
  string resume_id = 1;
  ResumeDownloadFormat format = 2;
}
```

Add a response message similar to:

```proto
message DownloadResumeResponse {
  bytes file = 1;
  string file_name = 2;
  string content_type = 3;
  ResumeDownloadFormat format = 4;
  string resume_id = 5;
  repeated Error errors = 6;
}
```

Add an enum similar to:

```proto
enum ResumeDownloadFormat {
  RESUME_DOWNLOAD_FORMAT_UNSPECIFIED = 0;
  RESUME_DOWNLOAD_FORMAT_PDF = 1;
}
```

Add an RPC to the existing owner service:

```proto
rpc DownloadResume(DownloadResumeRequest) returns (DownloadResumeResponse) {}
```

Naming may be adapted to match existing Ceerat proto conventions, but keep the behavior backend-owned and customer-owned.

Security and ownership requirements:
- Do not trust `customer_id`, `user_id`, or ownership information from the client request.
- Resolve the effective customer by authenticated JWT/auth context using the existing `customers.user_id` pattern.
- Customers can download only their own resumes.
- Agent/admin access is not required for this first version unless the existing Career service pattern requires it; if supported, it must be explicit and RBAC-protected.
- Reject unauthenticated callers.
- Reject unsupported formats.
- Reject blank or unknown resume ids.
- Do not return another customer's resume even if the resume id is known.
- Do not leak raw JWTs, auth headers, or full request metadata in logs.
- The response must not include password/token secrets.

Implementation requirements:
1. Tell me the ownership decision and why.
2. Tell me exact files you will create, edit, or remove before changing them.
3. Update `career.proto`.
4. Regenerate protobuf Go files with the repo's normal proto generation command.
5. Add the new RPC to known gRPC methods and default role permissions.
   - Customer role should be allowed to download its own resume.
   - Agent/admin role support should match existing Career profile service policy.
6. Add repository support to load a resume by authenticated customer id and resume id.
7. Add handler logic in `services-repo/services/ceerat-user-service/careers`.
8. Implement PDF generation in the backend service.
   - Prefer a small, well-contained implementation or existing dependency already present in the repo.
   - If adding a new dependency, justify it and keep it service-local.
   - Render readable plain text into PDF; do not attempt a complex resume layout in this first version.
   - Escape/sanitize text so generated PDF structure cannot be broken by resume content.
9. Return:
   - `application/pdf`
   - a safe `.pdf` file name
   - file bytes
   - requested/actual format
   - resume id
10. Keep changes backend-only. Do not add frontend routes, buttons, or pages in this task.
11. Update inventories:
   - `contracts-repo/docs/contract-inventory.json`
   - `services-repo/docs/grpc-service-inventory.json`
   - `apps-repo/docs/app-surface-inventory.json` only if app/AI surfaces change, which they should not in this task.
12. Update docs:
   - service API docs
   - API testing docs
   - gRPC security docs if method/RBAC docs list Career methods
   - architecture docs only if a new service/domain boundary is introduced

PDF behavior requirements:
- PDF output must be non-empty.
- PDF output must start with a valid PDF header.
- Include resume title/name when present.
- Include resume content text.
- Preserve line breaks reasonably.
- For very long resumes, paginate or otherwise avoid truncating content silently.
- Do not fetch `file_url` from the network in this first version.
- If both `content_text` and `content` are empty, return a validation error rather than an empty PDF.

Tests required:
- Customer can download their own resume as PDF.
- Response includes `application/pdf`, `.pdf` filename, resume id, and non-empty PDF bytes.
- PDF bytes begin with `%PDF`.
- Blank resume id is rejected.
- Unknown resume id is rejected.
- Unsupported/unspecified format behavior is explicit:
  - either unspecified defaults to PDF, or unspecified is rejected; choose the pattern that best matches Ceerat conventions and test it.
- Another customer's resume id is denied/not found through customer ownership scoping.
- Resume with empty content is rejected.
- Repository method scopes by authenticated customer id.
- Unauthenticated caller is denied.
- RBAC permission denied path is covered if testing pattern exists.

Run verification:
- `ceerat-builder verify contract-and-service career.CareerProfileService --output json`
- run the returned contract/service test and build commands
- in `contracts-repo/packages/ceerat-contracts`:
  - proto generation command
  - `go test ./...`
  - `go build ./...`
- in `services-repo/services/ceerat-user-service`:
  - `go test ./...`
  - `go build ./...`
- run affected app/agent tests only if shared generated contracts require compile updates
- `ceerat-builder rbac check --output json`
- `ceerat-builder check drift --output json`
- `ceerat-builder check apps --output json`

Acceptance criteria:
- The Career proto exposes a resume download RPC.
- The backend service returns PDF bytes for an authenticated customer's own resume.
- Ownership is enforced from authenticated user context, not client-supplied ids.
- Relevant Go tests pass.
- Contract and service builds pass.
- RBAC and builder drift checks pass.
- Inventories and docs are updated.
- No frontend UI is implemented in this task.
- No direct database access is added to apps or agents.

Important constraints:
- Preserve Ceerat architecture: proto first, service layer, repository layer, gRPC handlers, JWT/RBAC interceptors, structured logs.
- Customer UI, web UI, admin UI, and AI agent must use APIs/gRPC clients.
- Do not make resume download public.
- Do not add browser-facing download routes until a later frontend requirement asks for them.
- Do not update `.ceerat-agent` standards until tests/builds pass and human validation confirms the behavior.
- If ownership, PDF dependency, or format behavior is ambiguous, state assumptions before coding.
```
