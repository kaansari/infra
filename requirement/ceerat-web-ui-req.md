# Agent UI + AI Agent Career Tooling Document

## Goal

Career administration should live in the **agent-facing application**, not the admin/security UI.

The admin UI should stay focused on:

```text
User management
Roles
RBAC
Security
System administration
```

The agent-facing app `ceerat-web-ui` and `ceerat-agent-service` should support Career operations:

```text
Create companies
Create jobs
Search jobs
Close jobs
List applications for a job
Update application status
Support future batch job imports/scraping
```

---

# 1. Application Boundary

## Admin UI

Admin UI should only manage platform/security concerns:

```text
Users
Roles
RBAC permissions
Security settings
Cache refresh
```

Do not add Career pages here.

---

## Agent-facing UI: `ceerat-web-ui`

This is where agents work with Career data.

Add Career routes here:

```text
/agent/career
/agent/career/companies
/agent/career/jobs
/agent/career/applications
/agent/career/imports
```

Visible to:

```text
admin
agent
```

Backend RBAC remains the real security boundary.

---

# 2. Career Data Ownership

Companies and jobs are universal.

```text
companies are global
jobs are global
```

They are not owned by a single agent.

Agents can create and manage shared companies/jobs if RBAC allows.

Customers can later search/apply to global jobs.

---

# 3. Agent UI Navigation

Add a new section:

```text
Agent Dashboard
  Career
    Companies
    Jobs
    Applications
    Imports
```

Suggested home route:

```text
/agent/career
```

Cards:

```text
Companies
Jobs
Applications
Batch Imports
AI Assistant
```

---

# 4. Agent Career Companies Page

Route:

```http
GET /agent/career/companies
```

## Features

```text
Create company
Search companies
View company details
View company jobs
Edit company if backend supports it
```

## Fields

```text
Company name
Website
Industry
Description
Location
Source
External ID
```

Add source fields for future scraping/imports:

```text
source = manual | scraper | import | api
external_id
source_url
```

## API bridge endpoints

```http
GET  /api/agent/career/companies
POST /api/agent/career/companies
GET  /api/agent/career/companies/:id
PATCH /api/agent/career/companies/:id
```

If backend does not yet support list/get/update company, add TODOs or implement backend extensions later.

---

# 5. Agent Career Jobs Page

Route:

```http
GET /agent/career/jobs
```

## Features

```text
Create job
Search jobs
View job detail
Update job
Close job
Reopen job if backend supports status update
Filter by company/status/source
```

## Job fields

```text
Company
Title
Description
Category
Employment type
Location
Remote type
Salary min
Salary max
Status
Posted date
Closing date
Source
Source URL
External job ID
```

Status values:

```text
draft
open
closed
archived
```

Source values:

```text
manual
scraper
import
api
```

## API bridge endpoints

```http
GET   /api/agent/career/jobs
POST  /api/agent/career/jobs
GET   /api/agent/career/jobs/:id
PATCH /api/agent/career/jobs/:id
POST  /api/agent/career/jobs/:id/close
POST  /api/agent/career/jobs/:id/reopen
```

---

# 6. Agent Career Applications Page

Route:

```http
GET /agent/career/applications
```

## Features

```text
Search jobs
Select job
List applications for selected job
Filter applications by status
View application detail
View skill profile snapshot
View resume snapshot
Update application status
```

## Application statuses

```text
submitted
reviewing
interview
rejected
offered
withdrawn
```

## API bridge endpoints

```http
GET   /api/agent/career/jobs/:jobId/applications
PATCH /api/agent/career/applications/:id/status
```

---

# 7. Batch Import / Scraper Service

Since jobs may be created by batch scraping/imports, add a separate batch capability.

Recommended service:

```text
career-batch-service
```

or inside existing backend initially:

```text
services/ceerat-user-service/careers/batch
```

For clean architecture, long term use:

```text
services/career-batch-service
```

## Responsibilities

```text
Import jobs from CSV
Import jobs from external API
Scrape jobs from configured sources
Normalize companies
Deduplicate companies
Deduplicate jobs
Create/update jobs through Career gRPC service
Track import runs
Track failed records
```

Do not write directly to DB if possible.

Preferred:

```text
batch service -> career gRPC APIs -> database
```

This keeps RBAC/logging/service logic consistent.

For internal trusted batch processing, use a service account JWT or internal service credential.

---

# 8. Batch Import Domain Objects

Add later if not already present:

```text
CareerImportRun
CareerImportItem
CareerJobSource
```

## CareerImportRun

```text
id
source
source_type
status
started_at
completed_at
created_by_user_id
total_items
successful_items
failed_items
error_message
```

Status:

```text
pending
running
completed
failed
partial
```

## CareerImportItem

```text
id
import_run_id
external_id
source_url
company_name
job_title
status
error_message
created_company_id
created_job_id
raw_payload_json
```

## CareerJobSource

```text
id
name
type
base_url
enabled
schedule_cron
last_run_at
```

---

# 9. Imports UI Page

Route:

```http
GET /agent/career/imports
```

## Features

```text
View import runs
Start CSV import
Start configured scrape/import
View import errors
View created jobs
Retry failed items
```

## API endpoints

```http
GET  /api/agent/career/imports
POST /api/agent/career/imports/csv
POST /api/agent/career/imports/run
GET  /api/agent/career/imports/:id
POST /api/agent/career/imports/:id/retry-failed
```

This can be a second phase after manual agent UI is working.

---

# 10. Web UI gRPC Bridge

Add career agent routes in `ceerat-web-ui`.

Suggested structure:

```text
apps/ceerat-web-ui/internal/career/
  client.go
  agent_routes.go
  agent_handlers.go
  templates.go
```

Connect to career gRPC services through:

```env
USER_SERVICE_ADDR=ceerat-user-service:50051
```

Because Career services are registered inside `ceerat-user-service`.

All gRPC calls must forward JWT:

```go
metadata.AppendToOutgoingContext(
    ctx,
    "authorization",
    "Bearer "+token,
)
```

The web UI should not enforce final authorization itself. It can hide links, but backend RBAC decides.

---

# 11. AI Agent Career Tooling

Update:

```text
ai/ceerat-agent-service
```

Add career clients:

```go
type PlatformClient struct {
    CareerJobs          careerpb.JobServiceClient
    CareerApplications  careerpb.JobApplicationServiceClient
}
```

If batch service exists later:

```go
CareerImports careerpb.CareerImportServiceClient
```

---

# 12. Agent AI Tools

Add these tools first:

```text
create_company
create_job
search_jobs
get_job
close_job
list_applications_for_job
update_application_status
```

Later batch tools:

```text
start_job_import
list_job_imports
get_job_import_status
retry_failed_job_import_items
```

---

# 13. AI Tool Details

## create_company

Creates a global company.

Required:

```text
name
```

Optional:

```text
website
industry
description
location
source
source_url
external_id
```

Example:

```text
Create a company called Acme Health in healthcare.
```

---

## create_job

Creates a global job.

Required:

```text
company_id
title
description
```

Optional:

```text
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
source_url
external_job_id
```

If user gives company name, resolve the company first if list/search exists. Otherwise ask for company ID.

---

## search_jobs

Searches global jobs.

Inputs:

```text
keyword
company_id
location
remote_type
employment_type
status
source
```

---

## get_job

Gets job detail.

Input:

```text
job_id
```

---

## close_job

Closes a job.

Input:

```text
job_id
```

If title is given, search first.

---

## list_applications_for_job

Lists applications submitted to a job.

Input:

```text
job_id
status optional
```

---

## update_application_status

Updates applicant status.

Required:

```text
application_id
status
```

Allowed statuses:

```text
submitted
reviewing
interview
rejected
offered
withdrawn
```

---

# 14. AI System Prompt Update

Add this to the GPTAgent system prompt:

```text
Career agent capabilities:

You help agent and admin users manage global career data.

You can:
- create companies
- create jobs
- search jobs
- view job details
- close jobs
- list applications for a job
- update application status

Companies and jobs are global across all agents.

Rules:
- Never invent company IDs, job IDs, or application IDs.
- If the user gives a company name, resolve it using available tools or ask for company ID.
- If the user gives a job title, search jobs first.
- If multiple jobs match, ask the user to choose.
- If permission is denied, explain the user's role cannot perform that action.
- Do not perform customer-owned actions unless customer-specific tools are implemented.
- Do not bypass gRPC APIs.
- Do not access the database directly.
```

---

# 15. Agent Web Chat UI Suggestions

In `ceerat-web-ui`, update AI Agent panel suggestion chips for agent/admin users:

```text
Create company
Create job
Search jobs
Close job
Review applications
Update application status
```

Example chips:

```text
Create a company called Acme Health.
Create a remote backend engineer job for Acme Health.
Show me open remote jobs.
Close the Backend Engineer job.
Show applications for job ID abc123.
Move application xyz789 to interview.
```

---

# 16. RBAC

Agent role should allow:

```text
/career.JobService/CreateCompany
/career.JobService/CreateJob
/career.JobService/SearchJobs
/career.JobService/GetJob
/career.JobService/UpdateJob
/career.JobService/CloseJob
/career.JobApplicationService/ListApplicationsForJob
/career.JobApplicationService/UpdateApplicationStatus
```

Admin role:

```text
*
```

Customer role should not allow these agent operations.

---

# 17. Logging

Add UI/API logs:

```json
{
  "event": "career.agent.company.create.requested",
  "user_id": "user-id"
}
```

```json
{
  "event": "career.agent.job.create.requested",
  "user_id": "user-id",
  "company_id": "company-id"
}
```

AI tool logs:

```json
{
  "event": "ai.tool.career.create_job",
  "user_id": "user-id"
}
```

Never log:

```text
JWT token
password
authorization header
resume content unless explicitly needed
```

---

# 18. Tests

## Agent UI tests

```text
Agent can open /agent/career.
Agent can create company.
Agent can create job.
Agent can search jobs.
Agent can close job.
Agent can list applications for a job.
Agent can update application status.
Customer cannot access /agent/career routes.
PermissionDenied from backend shows friendly message.
```

## API bridge tests

```text
JWT is forwarded to gRPC.
CreateCompany maps to career proto.
CreateJob maps to career proto.
SearchJobs maps query params correctly.
CloseJob maps route param correctly.
UpdateApplicationStatus maps status correctly.
gRPC PermissionDenied maps to HTTP 403.
```

## AI agent tests

```text
create_company tool calls Career JobService.
create_job tool calls Career JobService.
search_jobs tool calls Career JobService.
get_job tool calls Career JobService.
close_job tool calls Career JobService.
list_applications_for_job calls Career JobApplicationService.
update_application_status calls Career JobApplicationService.
PermissionDenied returns friendly response.
Tools forward JWT metadata.
```

---

# 19. Acceptance Criteria

```text
Admin UI remains security/RBAC only.
Career pages are added to agent-facing ceerat-web-ui.
Agent/admin users can manage global companies and jobs.
Agent/admin users can review and update job applications.
Customer users cannot access agent Career pages.
AI agent can create companies.
AI agent can create jobs.
AI agent can search/get/close jobs.
AI agent can list applications for a job.
AI agent can update application status.
Jobs and companies are global across all agents.
Design supports future batch job imports/scraping.
All calls go through gRPC.
JWT metadata is forwarded.
RBAC remains backend source of truth.
```

---

# Codex Prompt

```text
Implement Agent UI + AI Agent Career Tooling for the Ceerat career domain.

Important architecture decision:
Do not add Career features to the admin/security UI. The admin UI should only manage users, roles, RBAC, and security.

Career operations belong in the agent-facing app:
apps/ceerat-web-ui

The associated AI service is:
ai/ceerat-agent-service

Backend already exists inside ceerat-user-service with these gRPC services:
- career.JobService
- career.JobApplicationService

Career contracts exist under:
contracts-repo/packages/ceerat-contracts/proto/career/

Companies and jobs are global across all agents. They are not owned by a single agent. Agents create companies and job entries for customers. Jobs may also be created later by batch services such as scraping/imports.

Implement agent-facing web routes:
- /agent/career
- /agent/career/companies
- /agent/career/jobs
- /agent/career/applications
- /agent/career/imports as placeholder only for future batch/import work

Add navigation under Agent Dashboard:
Career -> Companies, Jobs, Applications, Imports

Implement web API bridge endpoints:
- GET  /api/agent/career/companies
- POST /api/agent/career/companies
- GET  /api/agent/career/jobs
- POST /api/agent/career/jobs
- GET  /api/agent/career/jobs/:id
- PATCH /api/agent/career/jobs/:id
- POST /api/agent/career/jobs/:id/close
- GET  /api/agent/career/jobs/:jobId/applications
- PATCH /api/agent/career/applications/:id/status

If backend does not support company list/get/update yet, implement CreateCompany and document missing company list/get/update methods. Do not fake data.

The web app should connect to career gRPC services through USER_SERVICE_ADDR because the services are registered inside ceerat-user-service.

Every gRPC call must forward the logged-in JWT as:
authorization: Bearer <token>

Do not trust browser role as the final security boundary. Let backend JWT/RBAC enforce access.

Agent Career UI pages should support:
- create company
- create job
- search jobs
- view job detail
- close job
- list applications for a job
- update application status

Do not implement customer-facing Career pages in this task.

Update ai/ceerat-agent-service.

Add career gRPC clients:
- career.JobServiceClient
- career.JobApplicationServiceClient

Add AI tools:
- create_company
- create_job
- search_jobs
- get_job
- close_job
- list_applications_for_job
- update_application_status

Update GPTAgent prompt:
The agent can help agent/admin users manage global career data:
- create companies
- create jobs
- search jobs
- view job details
- close jobs
- list applications for a job
- update application status

Rules:
- companies and jobs are global across all agents
- never invent company IDs, job IDs, or application IDs
- resolve names using search/list tools where available
- ask clarification if multiple matches exist
- handle PermissionDenied with a friendly message
- do not bypass gRPC APIs
- do not access the database directly

Update web AI Agent UI prompt suggestions for agent/admin users:
- Create company
- Create job
- Search jobs
- Close job
- Review applications
- Update application status

Add placeholder design for future batch/import page:
- /agent/career/imports
- explain that future imports/scrapers will create companies/jobs through backend APIs
- do not implement scraping in this task

Add tests for:
- agent route access
- customer denial
- JWT metadata forwarding
- create company API bridge
- create job API bridge
- search jobs API bridge
- close job API bridge
- list applications API bridge
- update application status API bridge
- AI career tools
- PermissionDenied friendly handling

Preserve Ceerat architecture:
- UI calls web API bridge
- web API bridge calls gRPC
- AI agent calls gRPC
- backend RBAC remains source of truth
- no direct DB access from UI or AI agent
```
