```text
Use ceerat-platform-builder-agent as your discovery and consistency tool before implementing.

I want you to design and implement a new Career domain in the Ceerat platform.



Business context:
- Ceerat already has User, Customer, Auth/JWT, RBAC, customer portal, web/admin UI, and AI agent service.
- A customer logs in through the existing customer portal.
- The Career domain must follow existing Ceerat contract, service, repository, RBAC, logging, inventory, testing, and documentation patterns.
- For this req, do not make any updates to the apps.  THe requirements are only for the backend services.

Business requirements:
- Customer can create multiple skill profiles.
- Customer can add skills to each skill profile.
- Customer can upload or create resumes for skill profiles.
- Customer can search jobs.
- Customer can add jobs to a job cart.
- Customer can apply to jobs using a selected skill profile and targeted resume.
- Customer can apply to all jobs in their job cart.
- Customer can view only their own applications.
- Admin and agent users can create companies.
- Admin and agent users can create jobs.
- Admin and agent users can update jobs.
- Admin and agent users can close jobs.
- Admin and agent users can review applications.
- Admin and agent users can update application status.

Before coding, run:

- `ceerat-builder codex-context --output json`
- `ceerat-builder docs all --output json`
- `ceerat-builder inventory services --output json`
- `ceerat-builder inventory contracts --output json`
- `ceerat-builder inventory apps --output json`
- `ceerat-builder decide-owner "create career domain with companies jobs skill profiles resumes job cart and applications" --output json`
- `ceerat-builder evidence request "create career domain with companies jobs skill profiles resumes job cart and applications" --output json`
- `ceerat-builder patterns service --output json`
- `ceerat-builder patterns grpc-security --output json`
- `ceerat-builder patterns repository --output json`
- `ceerat-builder patterns testing --output json`
- `ceerat-builder cookbook service --output json`
- `ceerat-builder rbac check --output json`
- `ceerat-builder check drift --output json`
- `ceerat-builder plan --output json "create career domain with companies jobs skill profiles resumes job cart and applications"`

Use builder output as factual context, not final design.

Ownership expectation:
- Decide whether Career should be a new gRPC service/module or an extension inside `ceerat-user-service`.
- If existing inventory shows a better owner, explain it.
- If creating a new contract package, create `career.proto`.

Contract requirements:
Create `career.proto` with these core objects:
- `Company`
- `Job`
- `Skill`
- `SkillProfile`
- `SkillProfileSkill`
- `Resume`
- `JobCart`
- `JobCartItem`
- `JobApplication`

Create gRPC services:
- `CareerProfileService`
- `JobService`
- `JobCartService`
- `JobApplicationService`

Security and ownership requirements:
- All customer methods must derive `customer_id` from authenticated JWT context by looking up `customers.user_id`.
- Do not trust `customer_id` from customer request payloads.
- Customer can manage only their own skill profiles, resumes, job cart, and applications.
- Customer can search jobs.
- Customer cannot create companies.
- Customer cannot create jobs.
- Customer cannot review all applications.
- Customer cannot update another customer’s career data.
- Agent can create/manage jobs and review applications based on RBAC.
- Admin can access all.
- Apps and AI tools must not write directly to the database.

Database requirements:
Add models/migrations for:
- `companies`
- `jobs`
- `skills`
- `skill_profiles`
- `skill_profile_skills`
- `resumes`
- `job_carts`
- `job_cart_items`
- `job_applications`

AI agent tools:
Add AI agent tools that call platform APIs/gRPC clients, never the database directly:
- `create_skill_profile`
- `list_my_skill_profiles`
- `add_skill_to_profile`
- `search_jobs`
- `add_job_to_cart`
- `apply_to_job`
- `apply_to_cart_jobs`
- `list_my_applications`
- `create_company`
- `create_job`
- `update_application_status`

Implementation steps:
1. Tell me the ownership decision and why.
2. Tell me exact files you will create, edit, or remove before changing them.
3. Implement proto/contract changes.
4. Regenerate protobuf files.
5. Implement service models, repository layer, gRPC handlers, and startup registration.
6. Add JWT/RBAC method entries and default role permissions.
7. Add customer ownership enforcement in backend handlers/repositories.
8. Add AI agent tools through existing agent-service tool patterns.
9. Update inventories:
   - `contracts-repo/docs/contract-inventory.json`
   - `services-repo/docs/grpc-service-inventory.json`
   - `apps-repo/docs/app-surface-inventory.json` if app/AI surfaces change
10. Update docs:
   - service API docs
   - API testing docs
   - gRPC security docs
   - logging docs if new business events are logged
   - architecture docs if a new service/domain boundary is introduced

Tests required:
- customer ownership enforcement
- RBAC permission denied paths
- job search
- job cart add/remove/list behavior
- applying to one job
- applying to cart jobs
- admin/agent company and job creation
- admin/agent application status update
- customer cannot update another customer’s data
- AI tool permission errors

Run verification:
- `ceerat-builder verify contract-and-service career.CareerProfileService --output json`
- `ceerat-builder verify contract-and-service career.JobService --output json`
- `ceerat-builder verify contract-and-service career.JobCartService --output json`
- `ceerat-builder verify contract-and-service career.JobApplicationService --output json`
- run the returned contract/service test and build commands
- run affected AI agent tests/builds
- `ceerat-builder rbac check --output json`
- `ceerat-builder check drift --output json`
- `ceerat-builder check apps --output json`

Important constraints:
- Preserve Ceerat architecture: proto first, service layer, repository layer, gRPC handlers, JWT/RBAC interceptors, structured logs.
- Customer UI, web UI, admin UI, and AI agent must use APIs/gRPC clients.
- No frontend UI unless explicitly required by existing patterns or needed for minimal admin/customer route support.
- Do not update `.ceerat-agent` standards until tests/builds pass and human validation confirms the behavior.
- If any ownership or service-boundary decision is ambiguous, state assumptions before coding.
```