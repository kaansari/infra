Use ceerat-platform-builder-agent as your discovery and consistency tool before implementing.

I want to extend the existing Career backend so it is ready for the agent-facing ceerat-web-ui Career pages and future AI Career tools.

Context:
- Career backend already exists in ceerat-user-service.
- career.proto already exists.
- Existing registered services:
  - career.CareerProfileService
  - career.JobService
  - career.JobCartService
  - career.JobApplicationService
- Do not create admin UI Career pages.
- Do not build ceerat-web-ui pages yet in this pass.
- This pass is backend/API readiness only.

Before coding, run:

- `ceerat-builder codex-context --output json`
- `ceerat-builder docs all --output json`
- `ceerat-builder inventory services --output json`
- `ceerat-builder inventory contracts --output json`
- `ceerat-builder patterns service --output json`
- `ceerat-builder patterns grpc-security --output json`
- `ceerat-builder patterns repository --output json`
- `ceerat-builder patterns testing --output json`
- `ceerat-builder cookbook service --output json`
- `ceerat-builder evidence request "extend career backend for agent web ui career pages" --output json`
- `ceerat-builder plan --output json "extend career backend for company job application cart resume detail and source fields"`

Use builder output as factual context, not final design.

Requirements:

1. Extend Company model/API:
   - Add fields:
     - industry
     - location or address
     - source
     - external_id
     - source_url
   - Add gRPC methods:
     - ListCompanies
     - GetCompany
     - UpdateCompany
   - Keep CreateCompany admin/agent only.

2. Extend Job model/API:
   - Add fields:
     - category
     - remote_type
     - posted_date
     - closing_date
     - source
     - source_url
     - external_job_id
   - Normalize statuses:
     - draft
     - open
     - closed
     - archived
   - Add gRPC methods:
     - GetJob
     - ReopenJob
   - SearchJobs should support filters where reasonable:
     - query
     - company_id
     - location
     - remote_type
     - employment_type
     - status
     - source
   - Customer callers must only see open jobs.

3. Extend Application model/API:
   - Add resume_snapshot_text to JobApplication.
   - When ApplyToJob or ApplyToCartJobs runs, copy resume content into resume_snapshot_text.
   - Normalize application statuses:
     - submitted
     - reviewing
     - interview
     - rejected
     - offered
     - withdrawn
   - Add gRPC methods:
     - GetMyApplication
     - GetApplication or GetApplicationForReview
   - ListApplications should continue to support filtering by job_id/status/customer_id for admin/agent.

4. Extend Skill/Profile/Resume:
   - SkillProfile fields:
     - years_of_experience
     - target_role
     - is_default
   - Skill fields:
     - description
   - Resume fields:
     - name
     - content_text
     - version
     - is_active
   - Preserve backward compatibility if existing fields are already named title/content.

5. Extend Job Cart:
   - Add status to JobCart.
   - Add to JobCartItem:
     - selected_skill_profile_id
     - selected_resume_id
     - notes
   - Add method:
     - UpdateCartItemProfile
   - Customer can only update their own cart item.
   - Admin/agent behavior should follow existing ownership/RBAC patterns.

6. RBAC/security:
   - Update KnownGRPCMethods.
   - Update DefaultRolePermissions:
     - Customer can use customer self-service methods.
     - Agent can manage companies/jobs and review applications.
     - Admin wildcard remains.
   - Do not make any Career method public.

7. Persistence:
   - Update GORM models.
   - Update AutoMigrate.
   - Avoid destructive migrations.
   - Existing records should remain usable with sensible zero/default values.

8. Tests:
   - Add focused tests for:
     - customer can only see open jobs
     - customer cannot access another customer’s cart/application
     - resume_snapshot_text is saved on apply
     - agent can list/get/update companies
     - agent can get/reopen/close jobs
     - invalid job status is rejected
     - invalid application status is rejected
     - UpdateCartItemProfile enforces ownership
     - RBAC denied paths for customer management actions

9. Docs/inventories:
   - Update contract inventory.
   - Update service inventory.
   - Update service docs:
     - api.md
     - api-testing.md
     - grpc-security.md
     - architecture.md
     - logging.md if relevant
   - Do not update .ceerat-agent standards until after tests pass and human validation confirms this is the durable platform pattern.

10. Verification:
   - Run:
     - `make proto` in contracts-repo/packages/ceerat-contracts
     - `go test ./...` in contracts-repo/packages/ceerat-contracts
     - `go build ./...` in contracts-repo/packages/ceerat-contracts
     - `go test ./...` in services-repo/services/ceerat-user-service
     - `go build ./...` in services-repo/services/ceerat-user-service
     - `ceerat-builder check drift --output json`
     - `ceerat-builder check apps --output json`

Important constraints:
- Apps and agents must not write directly to the database.
- Keep business operations behind gRPC service APIs.
- Do not build frontend UI in this pass.
- Do not add Career pages to ceerat-admin-ui.
- Keep ceerat-admin-ui focused on users, roles, RBAC, security, and system administration.