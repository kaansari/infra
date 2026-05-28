# Customer UI Career Job Application Document

## Goal

Add customer-facing Career workflows to `ceerat-customer-ui`.

Customers already register and log in through the customer portal. The next step is to let authenticated customers manage their own career profile data, search global jobs, save jobs to a cart, and apply to jobs using a selected skill profile and resume.

The customer UI should support:

```text
Create and manage skill profiles
Add skills to skill profiles
Create or upload resumes for skill profiles
Search open jobs
Add jobs to a job cart
Update selected skill profile/resume/notes on cart items
Remove jobs from cart
Clear job cart
Apply to a single job
Apply to cart jobs
View own applications
View own application detail
```

---

# 1. Application Boundary

## Customer-facing UI: `ceerat-customer-ui`

Career self-service belongs in:

```text
apps-repo/apps/ceerat-customer-ui
```

Add customer Career routes here:

```text
/customer/career
/customer/career/profiles
/customer/career/resumes
/customer/career/jobs
/customer/career/cart
/customer/career/applications
```

Visible to:

```text
customer
```

Backend JWT/RBAC/ownership remains the real security boundary.

Do not add these customer Career pages to:

```text
ceerat-admin-ui
ceerat-web-ui
```

---

# 2. Career Data Ownership

Companies and jobs are global records created by agent/admin workflows.

Customers do not create companies or jobs.

Customers own:

```text
skill profiles
profile skills
resumes
job cart
job cart items
job applications
```

Customer-owned methods must derive customer identity from the authenticated JWT by looking up:

```text
customers.user_id
```

The UI may send profile, resume, job, cart item, and application IDs, but it must not send or trust arbitrary `customer_id` values for ownership.

---

# 3. Customer Navigation

Add a new section to the customer portal:

```text
Customer Portal
  Career
    Skill Profiles
    Resumes
    Jobs
    Job Cart
    Applications
```

Suggested home route:

```http
GET /customer/career
```

Cards:

```text
Skill Profiles
Resumes
Search Jobs
Job Cart
Applications
AI Assistant
```

---

# 4. Career Home Page

Route:

```http
GET /customer/career
```

## Features

```text
Show quick summary of career readiness
Show skill profile count
Show resume count
Show cart item count
Show application count
Provide quick links to profiles, jobs, cart, applications
```

This page should be lightweight. It can load summary data from existing list endpoints rather than requiring a new backend summary RPC.

---

# 5. Skill Profiles Page

Route:

```http
GET /customer/career/profiles
```

## Features

```text
Create skill profile
List my skill profiles
Add skill to a profile
Show skills under each profile
Mark profile as default if backend supports it
```

## Skill profile fields

```text
name
summary
years_of_experience
target_role
is_default
```

## Skill fields

```text
skill_name
skill_category
level
years_experience
skill_description
```

## API bridge endpoints

```http
GET  /api/customer/career/profiles
POST /api/customer/career/profiles
POST /api/customer/career/profiles/:id/skills
```

## gRPC mapping

```text
GET  /api/customer/career/profiles      -> career.CareerProfileService/ListMySkillProfiles
POST /api/customer/career/profiles      -> career.CareerProfileService/CreateSkillProfile
POST /api/customer/career/profiles/:id/skills -> career.CareerProfileService/AddSkillToProfile
```

---

# 6. Resumes Page

Route:

```http
GET /customer/career/resumes
```

## Features

```text
Create resume text
Attach resume to selected skill profile
List my resumes
Filter resumes by skill profile
Show active/default resume indicator if backend supports it
```

## Resume fields

```text
skill_profile_id
title
name
content
content_text
file_url
version
is_active
```

For the first implementation, text-based resume creation is enough. File upload can be a later phase unless existing customer UI upload patterns already exist.

## API bridge endpoints

```http
GET  /api/customer/career/resumes
POST /api/customer/career/resumes
```

## gRPC mapping

```text
GET  /api/customer/career/resumes -> career.CareerProfileService/ListMyResumes
POST /api/customer/career/resumes -> career.CareerProfileService/CreateResume
```

---

# 7. Jobs Search Page

Route:

```http
GET /customer/career/jobs
```

## Features

```text
Search jobs
Filter by keyword
Filter by location
Filter by remote type
Filter by employment type
View job detail
Add job to cart
Apply to job directly
```

Customers must only see open jobs.

The UI can include a status filter for future use, but customer backend behavior should force active/open jobs regardless of browser input.

## Job fields to display

```text
company name
title
description
category
employment_type
location
remote_type
salary_min
salary_max
status
posted_date
closing_date
source
```

Do not expose internal source details unless helpful for the customer experience.

## API bridge endpoints

```http
GET  /api/customer/career/jobs
GET  /api/customer/career/jobs/:id
POST /api/customer/career/jobs/:id/cart
POST /api/customer/career/jobs/:id/apply
```

## gRPC mapping

```text
GET  /api/customer/career/jobs       -> career.JobService/SearchJobs
GET  /api/customer/career/jobs/:id   -> career.JobService/GetJob
POST /api/customer/career/jobs/:id/cart  -> career.JobCartService/AddJobToCart
POST /api/customer/career/jobs/:id/apply -> career.JobApplicationService/ApplyToJob
```

---

# 8. Job Cart Page

Route:

```http
GET /customer/career/cart
```

## Features

```text
View current job cart
Update selected skill profile on cart item
Update selected resume on cart item
Update cart item notes
Remove job from cart
Clear cart
Apply to all cart jobs with selected profile/resume
```

## Cart item fields

```text
job_id
job title/company
notes
selected_skill_profile_id
selected_resume_id
```

## API bridge endpoints

```http
GET    /api/customer/career/cart
PATCH  /api/customer/career/cart/items/:id
DELETE /api/customer/career/cart/items/:id
DELETE /api/customer/career/cart
POST   /api/customer/career/cart/apply
```

## gRPC mapping

```text
GET    /api/customer/career/cart          -> career.JobCartService/GetJobCart
PATCH  /api/customer/career/cart/items/:id -> career.JobCartService/UpdateCartItemProfile
DELETE /api/customer/career/cart/items/:id -> career.JobCartService/RemoveJobFromCart
DELETE /api/customer/career/cart           -> career.JobCartService/ClearJobCart
POST   /api/customer/career/cart/apply     -> career.JobApplicationService/ApplyToCartJobs
```

---

# 9. Applications Page

Route:

```http
GET /customer/career/applications
```

## Features

```text
List my applications
Filter by status
View application detail
Show job details
Show selected skill profile
Show resume snapshot or resume summary
```

Customers can only view their own applications.

## Application statuses

```text
submitted
reviewing
interview
rejected
offered
withdrawn
```

Customer UI should display status read-only unless customer withdrawal is later implemented.

## API bridge endpoints

```http
GET /api/customer/career/applications
GET /api/customer/career/applications/:id
```

## gRPC mapping

```text
GET /api/customer/career/applications     -> career.JobApplicationService/ListMyApplications
GET /api/customer/career/applications/:id -> career.JobApplicationService/GetMyApplication
```

---

# 10. Web UI gRPC Bridge

Suggested code structure:

```text
apps/ceerat-customer-ui/internal/apiclient/client.go
apps/ceerat-customer-ui/internal/server/server.go
apps/ceerat-customer-ui/web/templates/career.html
apps/ceerat-customer-ui/web/static/app.js
apps/ceerat-customer-ui/web/static/app.css
```

The customer UI should connect to Career gRPC services through the existing user-service gRPC address:

```text
CEERAT_API_BASE_URL or API_BASE_URL
```

Every protected gRPC call must forward JWT metadata:

```text
authorization: Bearer <token>
```

The browser should call only same-origin customer UI endpoints. The browser must not call gRPC directly.

---

# 11. AI Customer Assistant

The customer portal already has a chat surface through `ceerat-agent-service`.

Customer-facing Career AI tools can be added after the customer UI is working, or in the same pass if the existing AI tool architecture is already ready.

Recommended customer Career AI tools:

```text
create_skill_profile
list_my_skill_profiles
add_skill_to_profile
create_resume
list_my_resumes
search_jobs
get_job
add_job_to_cart
get_job_cart
update_job_cart_item
remove_job_from_cart
clear_job_cart
apply_to_job
apply_to_cart_jobs
list_my_applications
get_my_application
```

Customer AI rules:

```text
Never ask for or trust customer_id.
Use authenticated customer context.
Never invent skill_profile_id, resume_id, job_id, cart_item_id, or application_id.
Search/list first when user gives names or titles.
If multiple jobs/profiles/resumes match, ask the customer to choose.
If permission is denied, explain that the account cannot perform the action.
Do not bypass gRPC APIs.
Do not access the database directly.
```

---

# 12. RBAC

Customer role should allow:

```text
/career.CareerProfileService/CreateSkillProfile
/career.CareerProfileService/ListMySkillProfiles
/career.CareerProfileService/AddSkillToProfile
/career.CareerProfileService/CreateResume
/career.CareerProfileService/ListMyResumes
/career.JobService/SearchJobs
/career.JobService/GetJob
/career.JobCartService/GetJobCart
/career.JobCartService/AddJobToCart
/career.JobCartService/UpdateCartItemProfile
/career.JobCartService/RemoveJobFromCart
/career.JobCartService/ClearJobCart
/career.JobApplicationService/ApplyToJob
/career.JobApplicationService/ApplyToCartJobs
/career.JobApplicationService/ListMyApplications
/career.JobApplicationService/GetMyApplication
```

Customer role should not allow:

```text
/career.JobService/CreateCompany
/career.JobService/UpdateCompany
/career.JobService/CreateJob
/career.JobService/UpdateJob
/career.JobService/CloseJob
/career.JobService/ReopenJob
/career.JobApplicationService/ListApplications
/career.JobApplicationService/GetApplication
/career.JobApplicationService/UpdateApplicationStatus
```

Admin role:

```text
*
```

Agent role should keep agent-facing permissions in the `ceerat-web-ui` Career requirements.

---

# 13. Logging

Add customer UI/API logs:

```json
{
  "event": "career.customer.profile.create.requested",
  "user_id": "user-id"
}
```

```json
{
  "event": "career.customer.job.cart.add.requested",
  "user_id": "user-id",
  "job_id": "job-id"
}
```

```json
{
  "event": "career.customer.application.submit.requested",
  "user_id": "user-id",
  "job_id": "job-id"
}
```

Never log:

```text
JWT token
password
authorization header
full resume content
cover letter content unless explicitly needed and redacted
```

---

# 14. Tests

## Customer UI route tests

```text
Customer can open /customer/career.
Customer can open /customer/career/profiles.
Customer can open /customer/career/resumes.
Customer can open /customer/career/jobs.
Customer can open /customer/career/cart.
Customer can open /customer/career/applications.
Unauthenticated users are redirected to login.
```

## API bridge tests

```text
JWT is forwarded to gRPC.
CreateSkillProfile maps to career proto.
AddSkillToProfile maps profile id and skill payload correctly.
CreateResume maps to career proto.
SearchJobs maps query params correctly.
AddJobToCart maps route job id correctly.
UpdateCartItemProfile maps cart item id/profile/resume/notes correctly.
RemoveJobFromCart maps cart item id correctly.
ClearJobCart calls backend clear RPC.
ApplyToJob maps job id/profile/resume/cover letter correctly.
ApplyToCartJobs maps profile/resume/cover letter correctly.
ListMyApplications maps status query correctly.
GetMyApplication maps application id correctly.
gRPC PermissionDenied maps to HTTP 403.
gRPC Unauthenticated maps to HTTP 401.
```

## Customer ownership/security tests

```text
Customer cannot pass another customer_id.
Customer cannot create companies.
Customer cannot create jobs.
Customer cannot review all applications.
Customer only sees open jobs.
Customer can only access own cart.
Customer can only access own applications.
```

## UI behavior tests

```text
Skill profile form validates name.
Resume form requires a skill profile and resume content/name.
Job search shows empty state.
Job cart shows empty state.
Apply flow requires selected skill profile and resume.
Application list shows status and job details.
PermissionDenied from backend shows friendly message.
```

## AI customer Career tests, if tools are implemented

```text
create_skill_profile tool calls CareerProfileService.
search_jobs tool calls JobService and only returns open jobs for customer.
add_job_to_cart tool calls JobCartService.
apply_to_job tool calls JobApplicationService.
list_my_applications tool calls JobApplicationService.
Tools forward JWT metadata.
Tools never send customer_id from the model.
PermissionDenied returns friendly response.
```

---

# 15. Acceptance Criteria

```text
Customer Career pages are added to ceerat-customer-ui.
Customer can create skill profiles.
Customer can add skills to profiles.
Customer can create/list resumes.
Customer can search open jobs.
Customer can add jobs to cart.
Customer can update/remove/clear cart items.
Customer can apply to a job with selected skill profile and resume.
Customer can apply to cart jobs.
Customer can list/view only their own applications.
All customer-owned operations derive customer identity from JWT.
All calls go through same-origin customer UI APIs and backend gRPC.
JWT metadata is forwarded.
RBAC and ownership remain backend source of truth.
Admin UI remains security/RBAC only.
Agent Career administration remains in ceerat-web-ui.
Apps and agents do not write directly to the database.
```

---

# Codex Prompt

```text
Use ceerat-platform-builder-agent as your discovery and consistency tool before implementing.

Implement customer-facing Career job search, job cart, skill profile, resume, and job application workflows for Ceerat.

Important architecture decision:
Do not add customer Career features to the admin/security UI.
Do not add customer Career features to the agent-facing ceerat-web-ui.

Customer Career operations belong in:
apps/ceerat-customer-ui

Backend already exists inside ceerat-user-service with these gRPC services:
- career.CareerProfileService
- career.JobService
- career.JobCartService
- career.JobApplicationService

Career contracts exist under:
contracts-repo/packages/ceerat-contracts/proto/career/

Business requirements:
- Customer can create multiple skill profiles.
- Customer can add skills to skill profiles.
- Customer can create/list resumes for skill profiles.
- Customer can search open jobs.
- Customer can view job detail.
- Customer can add jobs to a cart.
- Customer can update selected skill profile/resume/notes for cart items.
- Customer can remove jobs from cart.
- Customer can clear cart.
- Customer can apply to a job using selected skill profile and resume.
- Customer can apply to all cart jobs using selected skill profile and resume.
- Customer can list/view only their own applications.
- Customer must not be able to create companies or jobs.
- Customer must not be able to review all applications or update application status.
- Customer identity must be derived from JWT/backend context, not browser-supplied customer_id.

Before coding, run:

- `ceerat-builder codex-context --output json`
- `ceerat-builder docs all --output json`
- `ceerat-builder inventory services --output json`
- `ceerat-builder inventory contracts --output json`
- `ceerat-builder inventory apps --output json`
- `ceerat-builder app-context --output json`
- `ceerat-builder app-surface ceerat-customer-ui --output json`
- `ceerat-builder app-match "customer career job application portal" --output json`
- `ceerat-builder patterns service --output json`
- `ceerat-builder patterns grpc-security --output json`
- `ceerat-builder patterns repository --output json`
- `ceerat-builder patterns testing --output json`
- `ceerat-builder cookbook service --output json`
- `ceerat-builder evidence request "add customer career job application workflows to ceerat-customer-ui" --output json`
- `ceerat-builder plan --output json "add customer career skill profile resume job search cart and application workflows"`

Use builder output as factual context, not final design.

Implement customer-facing routes:
- /customer/career
- /customer/career/profiles
- /customer/career/resumes
- /customer/career/jobs
- /customer/career/cart
- /customer/career/applications

Add navigation under Customer Portal:
Career -> Skill Profiles, Resumes, Jobs, Job Cart, Applications

Implement web API bridge endpoints:
- GET  /api/customer/career/profiles
- POST /api/customer/career/profiles
- POST /api/customer/career/profiles/:id/skills
- GET  /api/customer/career/resumes
- POST /api/customer/career/resumes
- GET  /api/customer/career/jobs
- GET  /api/customer/career/jobs/:id
- POST /api/customer/career/jobs/:id/cart
- POST /api/customer/career/jobs/:id/apply
- GET  /api/customer/career/cart
- PATCH /api/customer/career/cart/items/:id
- DELETE /api/customer/career/cart/items/:id
- DELETE /api/customer/career/cart
- POST /api/customer/career/cart/apply
- GET /api/customer/career/applications
- GET /api/customer/career/applications/:id

The customer UI should connect to Career gRPC services through the existing user-service gRPC address.

Every gRPC call must forward the logged-in JWT as:
authorization: Bearer <token>

Do not trust browser role or browser customer_id as the security boundary.
Let backend JWT/RBAC/ownership enforce access.

Do not implement company/job management in customer UI.
Do not implement admin UI changes.
Do not write directly to the database.

Add tests for:
- customer route access
- unauthenticated redirect
- JWT metadata forwarding
- create skill profile API bridge
- add skill to profile API bridge
- create/list resume API bridge
- search jobs API bridge
- add job to cart API bridge
- update/remove/clear cart API bridge
- apply to job API bridge
- apply to cart jobs API bridge
- list/get my applications API bridge
- PermissionDenied friendly handling

Update docs and inventory:
- apps-repo/docs/app-surface-inventory.json
- apps/ceerat-customer-ui/README.md
- apps/ceerat-customer-ui/docs/customer-ui-architecture.html if appropriate
- apps-repo/ai/docs only if customer AI Career tools are added

Run:
- `go test ./...` from apps/ceerat-customer-ui
- `go build ./...` from apps/ceerat-customer-ui
- `ceerat-builder check apps --output json`
- `ceerat-builder check drift --output json`

After implementation, summarize:
- ownership decision
- files changed
- routes/endpoints added
- verification results
- remaining live validation risks
```
