Below is a Ceerat-style **Career Site domain architecture**.

# Career Domain Architecture

## Existing foundation

we already have:

```text
User
Customer
Auth/JWT/RBAC
AI Agent
Dashboard/Web UI
gRPC service architecture
```

For this career site:

```text
User = login identity
Customer = job seeker profile owner
```

A customer can:

```text
create multiple skill profiles
search jobs
save jobs to cart
apply to jobs using a selected skill profile / targeted resume
```

---

# Core Domain Model

```text
Customer
 ├── SkillProfiles
 │     ├── Skills
 │     ├── Experience
 │     ├── Education
 │     └── TargetedResume
 │
 ├── JobCart
 │     └── JobCartItems
 │
 └── JobApplications
       ├── Job
       ├── SkillProfile
       └── ResumeSnapshot
```

---

# Main Objects

## 1. Company

Represents employer/company posting jobs.

```text
Company
- id
- name
- website
- industry
- size
- description
- address
- created_at
- updated_at
```

Relationship:

```text
Company has many Jobs
```

---

## 2. Job

Represents a job posting.

```text
Job
- id
- company_id
- title
- description
- category
- employment_type
- location
- remote_type
- salary_min
- salary_max
- status
- posted_date
- closing_date
- created_at
- updated_at
```

Status:

```text
draft
active
closed
archived
```

Relationship:

```text
Job belongs to Company
Job has many JobApplications
Job can be saved in many JobCarts
```

---

## 3. Skill

Reusable skill object.

```text
Skill
- id
- name
- category
- description
```

Examples:

```text
Go
React
PostgreSQL
gRPC
AWS
Project Management
```

---

## 4. SkillProfile

Customer-created profile for a specific job target.

Example:

```text
Backend Engineer Profile
Frontend Engineer Profile
Project Manager Profile
```

```text
SkillProfile
- id
- customer_id
- name
- summary
- years_of_experience
- target_role
- is_default
- created_at
- updated_at
```

Relationship:

```text
Customer has many SkillProfiles
SkillProfile has many Skills
SkillProfile has many ResumeVersions
```

---

## 5. SkillProfileSkill

Join table between profile and skills.

```text
SkillProfileSkill
- id
- skill_profile_id
- skill_id
- proficiency
- years_experience
```

Proficiency:

```text
beginner
intermediate
advanced
expert
```

---

## 6. Resume

Resume attached to a skill profile.

```text
Resume
- id
- customer_id
- skill_profile_id
- name
- file_url
- content_text
- version
- is_active
- created_at
- updated_at
```

Important: when applying to a job, take a snapshot.

---

## 7. JobCart

Temporary saved jobs before applying.

```text
JobCart
- id
- customer_id
- status
- created_at
- updated_at
```

Status:

```text
active
submitted
abandoned
```

---

## 8. JobCartItem

```text
JobCartItem
- id
- cart_id
- job_id
- selected_skill_profile_id
- selected_resume_id
- notes
- created_at
```

Relationship:

```text
Customer adds many Jobs to cart
Each cart item can optionally select a skill profile/resume
```

---

## 9. JobApplication

Final submitted application.

```text
JobApplication
- id
- customer_id
- job_id
- skill_profile_id
- resume_id
- resume_snapshot_text
- cover_letter
- status
- applied_at
- created_at
- updated_at
```

Status:

```text
draft
submitted
reviewing
interview
rejected
offered
withdrawn
```

---

# Recommended Proto Files

Use separate protos:

```text
career_company.proto
career_job.proto
career_skill.proto
career_resume.proto
career_cart.proto
career_application.proto
```

Or one first version:

```text
career.proto
```

For early development, I recommend one:

```text
protos/career.proto
```

Then split later if it grows.

---

# gRPC Services

## CareerProfileService

For customer-owned skill profiles and resumes.

```proto
service CareerProfileService {
  rpc CreateSkillProfile(CreateSkillProfileRequest) returns (CreateSkillProfileResponse);
  rpc ListMySkillProfiles(ListMySkillProfilesRequest) returns (ListMySkillProfilesResponse);
  rpc GetMySkillProfile(GetMySkillProfileRequest) returns (GetMySkillProfileResponse);
  rpc UpdateMySkillProfile(UpdateMySkillProfileRequest) returns (UpdateMySkillProfileResponse);
  rpc DeleteMySkillProfile(DeleteMySkillProfileRequest) returns (DeleteMySkillProfileResponse);

  rpc AddSkillToProfile(AddSkillToProfileRequest) returns (AddSkillToProfileResponse);
  rpc RemoveSkillFromProfile(RemoveSkillFromProfileRequest) returns (RemoveSkillFromProfileResponse);

  rpc UploadResume(UploadResumeRequest) returns (UploadResumeResponse);
  rpc ListMyResumes(ListMyResumesRequest) returns (ListMyResumesResponse);
}
```

Important:

```text
All "My" methods derive customer_id from JWT/user_id.
Do not trust customer_id from request.
```

---

## JobService

For searching and managing jobs.

```proto
service JobService {
  rpc SearchJobs(SearchJobsRequest) returns (SearchJobsResponse);
  rpc GetJob(GetJobRequest) returns (GetJobResponse);

  rpc CreateCompany(CreateCompanyRequest) returns (CreateCompanyResponse);
  rpc CreateJob(CreateJobRequest) returns (CreateJobResponse);
  rpc UpdateJob(UpdateJobRequest) returns (UpdateJobResponse);
  rpc CloseJob(CloseJobRequest) returns (CloseJobResponse);
}
```

Customer can:

```text
SearchJobs
GetJob
```

Admin/agent can:

```text
CreateCompany
CreateJob
UpdateJob
CloseJob
```

---

## JobCartService

```proto
service JobCartService {
  rpc GetMyActiveCart(GetMyActiveCartRequest) returns (GetMyActiveCartResponse);
  rpc AddJobToCart(AddJobToCartRequest) returns (AddJobToCartResponse);
  rpc RemoveJobFromCart(RemoveJobFromCartRequest) returns (RemoveJobFromCartResponse);
  rpc UpdateCartItemProfile(UpdateCartItemProfileRequest) returns (UpdateCartItemProfileResponse);
  rpc ClearCart(ClearCartRequest) returns (ClearCartResponse);
}
```

Ownership:

```text
Customer can only access their own cart.
```

---

## JobApplicationService

```proto
service JobApplicationService {
  rpc ApplyToJob(ApplyToJobRequest) returns (ApplyToJobResponse);
  rpc ApplyToCartJobs(ApplyToCartJobsRequest) returns (ApplyToCartJobsResponse);
  rpc ListMyApplications(ListMyApplicationsRequest) returns (ListMyApplicationsResponse);
  rpc GetMyApplication(GetMyApplicationRequest) returns (GetMyApplicationResponse);
  rpc WithdrawApplication(WithdrawApplicationRequest) returns (WithdrawApplicationResponse);

  rpc ListApplicationsForJob(ListApplicationsForJobRequest) returns (ListApplicationsForJobResponse);
  rpc UpdateApplicationStatus(UpdateApplicationStatusRequest) returns (UpdateApplicationStatusResponse);
}
```

Customer can:

```text
ApplyToJob
ApplyToCartJobs
ListMyApplications
GetMyApplication
WithdrawApplication
```

Admin/agent can:

```text
ListApplicationsForJob
UpdateApplicationStatus
```

---

# Key Relationships

```text
users.id
  ↓ one-to-one for customer role
customers.user_id

customers.id
  ↓ one-to-many
skill_profiles.customer_id

skill_profiles.id
  ↓ one-to-many
resumes.skill_profile_id

companies.id
  ↓ one-to-many
jobs.company_id

customers.id
  ↓ one-to-one active cart
job_carts.customer_id

job_carts.id
  ↓ one-to-many
job_cart_items.cart_id

jobs.id
  ↓ one-to-many
job_cart_items.job_id

customers.id
  ↓ one-to-many
job_applications.customer_id

jobs.id
  ↓ one-to-many
job_applications.job_id

skill_profiles.id
  ↓ one-to-many
job_applications.skill_profile_id
```

---

# Customer Flow

## 1. Customer logs in

Already handled by your platform.

```text
User logs in
JWT contains user_id + role=customer
Customer profile found by customers.user_id
```

---

## 2. Customer creates skill profiles

Example:

```text
Backend Engineer Profile
Cloud Engineer Profile
Project Manager Profile
```

Each profile can have:

```text
skills
experience
resume
summary
target role
```

---

## 3. Customer searches jobs

```text
SearchJobs(keyword="golang", location="remote")
```

Returns matching active jobs.

---

## 4. Customer adds jobs to cart

```text
AddJobToCart(job_id, selected_skill_profile_id, selected_resume_id)
```

---

## 5. Customer applies

Customer can apply one job:

```text
ApplyToJob(job_id, skill_profile_id, resume_id)
```

Or all cart jobs:

```text
ApplyToCartJobs(cart_id)
```

Application saves snapshot:

```text
resume_snapshot_text
skill_profile_id
resume_id
job_id
customer_id
```

This matters because the resume/profile may change later.

---

# RBAC Design

## Customer role

Allowed:

```text
/career.CareerProfileService/CreateSkillProfile
/career.CareerProfileService/ListMySkillProfiles
/career.CareerProfileService/GetMySkillProfile
/career.CareerProfileService/UpdateMySkillProfile
/career.CareerProfileService/DeleteMySkillProfile
/career.CareerProfileService/AddSkillToProfile
/career.CareerProfileService/RemoveSkillFromProfile
/career.CareerProfileService/UploadResume

/career.JobService/SearchJobs
/career.JobService/GetJob

/career.JobCartService/GetMyActiveCart
/career.JobCartService/AddJobToCart
/career.JobCartService/RemoveJobFromCart
/career.JobCartService/UpdateCartItemProfile
/career.JobCartService/ClearCart

/career.JobApplicationService/ApplyToJob
/career.JobApplicationService/ApplyToCartJobs
/career.JobApplicationService/ListMyApplications
/career.JobApplicationService/GetMyApplication
/career.JobApplicationService/WithdrawApplication
```

Denied:

```text
CreateCompany
CreateJob
UpdateJob
CloseJob
ListApplicationsForJob
UpdateApplicationStatus
```

---

## Agent role

Allowed:

```text
CreateCompany
CreateJob
UpdateJob
CloseJob
SearchJobs
GetJob
ListApplicationsForJob
UpdateApplicationStatus
```

Optional:

```text
View customer profiles if business allows it
```

---

## Admin role

Allowed:

```text
*
```

---

# Web UI Pages

## Customer portal

```text
/career
/career/profile
/career/skills
/career/resumes
/career/jobs
/career/cart
/career/applications
```

Pages:

```text
Skill Profiles page
Resume page
Job Search page
Job Cart page
Applications page
```

---

## Admin/agent dashboard

```text
/admin/career/companies
/admin/career/jobs
/admin/career/applications
```

Admin/agent can:

```text
create company
create job
close job
review applications
update application status
```

---

# AI Agent Tools

Add career tools to your existing Ceerat AI agent.

## Customer-facing tools

```text
create_skill_profile
list_my_skill_profiles
add_skill_to_profile
search_jobs
add_job_to_cart
list_cart_jobs
apply_to_job
apply_to_cart_jobs
list_my_applications
```

Example prompts:

```text
Create a backend engineer skill profile with Go, PostgreSQL, gRPC and AWS.
```

```text
Find me remote Go developer jobs.
```

```text
Add the first three jobs to my cart.
```

```text
Apply to all jobs in my cart using my Backend Engineer profile.
```

---

## Admin/agent tools

```text
create_company
create_job
close_job
list_applications_for_job
update_application_status
```

---

# Suggested First Proto Skeleton

```proto
syntax = "proto3";

package career;

option go_package = "github.com/ceerat/contracts/gen/careerpb;careerpb";

message Company {
  string id = 1;
  string name = 2;
  string website = 3;
  string industry = 4;
  string description = 5;
  string created_at = 6;
  string updated_at = 7;
}

message Job {
  string id = 1;
  string company_id = 2;
  string title = 3;
  string description = 4;
  string category = 5;
  string employment_type = 6;
  string location = 7;
  string remote_type = 8;
  double salary_min = 9;
  double salary_max = 10;
  string status = 11;
  string posted_date = 12;
  string closing_date = 13;
  Company company = 14;
}

message Skill {
  string id = 1;
  string name = 2;
  string category = 3;
}

message SkillProfile {
  string id = 1;
  string customer_id = 2;
  string name = 3;
  string summary = 4;
  string target_role = 5;
  int32 years_of_experience = 6;
  repeated SkillProfileSkill skills = 7;
  repeated Resume resumes = 8;
}

message SkillProfileSkill {
  string id = 1;
  string skill_profile_id = 2;
  string skill_id = 3;
  string skill_name = 4;
  string proficiency = 5;
  int32 years_experience = 6;
}

message Resume {
  string id = 1;
  string customer_id = 2;
  string skill_profile_id = 3;
  string name = 4;
  string file_url = 5;
  string content_text = 6;
  int32 version = 7;
  bool is_active = 8;
}

message JobCart {
  string id = 1;
  string customer_id = 2;
  string status = 3;
  repeated JobCartItem items = 4;
}

message JobCartItem {
  string id = 1;
  string cart_id = 2;
  string job_id = 3;
  string selected_skill_profile_id = 4;
  string selected_resume_id = 5;
  Job job = 6;
}

message JobApplication {
  string id = 1;
  string customer_id = 2;
  string job_id = 3;
  string skill_profile_id = 4;
  string resume_id = 5;
  string resume_snapshot_text = 6;
  string cover_letter = 7;
  string status = 8;
  string applied_at = 9;
  Job job = 10;
  SkillProfile skill_profile = 11;
}
```

---

# Suggested Services to Build First

Build in this order:

```text
1. CareerProfileService
2. JobService
3. JobCartService
4. JobApplicationService
5. Career AI tools
6. Admin/agent career dashboard
```

Do not start with applications first. Applications depend on:

```text
customer
skill profile
resume
job
cart
```

---

# MVP Scope

For MVP, build only:

```text
SkillProfile
Skill
Company
Job
JobCart
JobApplication
```

Skip initially:

```text
interview scheduling
messages
recruiter portal
resume parsing
job recommendations
payment/billing
```

---

# Acceptance Criteria

```text
Customer can log in.
Customer can create multiple skill profiles.
Customer can attach skills to each profile.
Customer can search active jobs.
Customer can add jobs to cart.
Customer can select a skill profile/resume per cart job.
Customer can apply to one job.
Customer can apply to all cart jobs.
Customer can view own applications.
Customer cannot view other customers' applications.
Admin/agent can create companies.
Admin/agent can create jobs.
Admin/agent can review applications.
RBAC protects all career methods.
AI agent can help customer search/apply to jobs.
```

---

# Gap Analysis After Backend First Pass

This section compares the implemented backend Career services against `infra/requirement/ceerat-web-ui-req.md`.

Implemented backend foundation:

```text
- career.proto exists.
- CareerProfileService exists.
- JobService exists.
- JobCartService exists.
- JobApplicationService exists.
- ceerat-user-service owns the Career database objects.
- JWT/RBAC entries exist for customer, agent, and admin flows.
- Customer-owned methods derive customer_id from JWT/customers.user_id.
```

Known gaps before building the agent-facing `ceerat-web-ui` Career pages:

```text
Company API gaps:
- Company currently supports CreateCompany only.
- Agent UI needs list/search/get/update company.
- Company model is missing industry, location/address, source, external_id, source_url.

Job API/model gaps:
- Job currently supports create/search/update/close, but not GetJob or ReopenJob.
- Agent UI needs job detail and reopen support.
- Job model is missing category, remote_type, posted_date, closing_date, source, source_url, external_job_id.
- Status values should be normalized to draft/open/closed/archived for the agent UI.

Application API/model gaps:
- ListApplications can filter by job_id, so it can support applications for a job.
- There is no explicit GetApplication/GetMyApplication method for detail views.
- JobApplication does not store resume_snapshot_text yet.
- Application status should be normalized to submitted/reviewing/interview/rejected/offered/withdrawn.

Skill/profile/resume gaps:
- SkillProfile is missing years_of_experience, target_role, is_default.
- Skill is missing description.
- Resume is missing version/is_active and currently uses title/content/file_url instead of name/content_text/file_url.

Job cart gaps:
- JobCart has no status.
- JobCartItem does not store selected_skill_profile_id, selected_resume_id, or per-item notes for targeted apply flow.
- There is no UpdateCartItemProfile method.

Batch/import gaps:
- CareerImportRun, CareerImportItem, and CareerJobSource are not implemented.
- No import/scraper gRPC service exists yet.
- career-batch-service is not implemented. This can be phase two.

AI tooling gaps:
- AI agent Career tools were not implemented in the backend-first pass.
- Needed tools include create_company, create_job, search_jobs, get_job, close_job, list_applications_for_job, and update_application_status.

App/UI gaps:
- No ceerat-web-ui Career routes or API bridge endpoints exist yet.
- Admin UI should not receive Career pages.
```

Recommended next backend step before UI:

```text
Extend Career backend contracts and services with the missing company/job detail, source/import-friendly fields, normalized statuses, cart item profile selection, resume snapshot, and read/detail methods. Then build ceerat-web-ui Career pages and AI tools on top of that stable API.
```

---

# Recommended Codex Prompt

```text
Design and implement a new Career domain in the Ceerat platform.

The platform already has User, Customer, Auth/JWT, RBAC, web dashboard, and AI agent. A customer logs in through the existing customer portal.

Add a Career domain where a customer can:
- create multiple skill profiles
- add skills to each skill profile
- upload or create resumes for skill profiles
- search jobs
- add jobs to a cart
- apply to jobs using a selected skill profile and targeted resume
- view only their own applications

Admin and agent users can:
- create companies
- create jobs
- update jobs
- close jobs
- review applications
- update application status

Create a career.proto with:
- Company
- Job
- Skill
- SkillProfile
- SkillProfileSkill
- Resume
- JobCart
- JobCartItem
- JobApplication

Create gRPC services:
- CareerProfileService
- JobService
- JobCartService
- JobApplicationService

All customer methods must derive customer_id from authenticated JWT context by looking up customers.user_id. Do not trust customer_id from customer request payloads.

Add database migrations for:
- companies
- jobs
- skills
- skill_profiles
- skill_profile_skills
- resumes
- job_carts
- job_cart_items
- job_applications

Add RBAC permissions:
Customer can manage own skill profiles, own resumes, own cart, own applications, and search jobs.
Customer cannot create companies, create jobs, review all applications, or update another customer's data.
Agent can create/manage jobs and review applications based on RBAC.
Admin can access all.



Add AI agent tools:
- create_skill_profile
- list_my_skill_profiles
- add_skill_to_profile
- search_jobs
- add_job_to_cart
- apply_to_job
- apply_to_cart_jobs
- list_my_applications
- create_company
- create_job
- update_application_status

Add tests for:
- customer ownership
- RBAC permissions
- job search
- cart behavior
- applying to job
- applying to cart jobs
- admin/agent job creation
- application status updates
- AI tool permission errors

Preserve Ceerat architecture:
- proto first
- service layer
- repository layer
- gRPC handlers
- JWT/RBAC interceptors
- structured logs
- web UI uses APIs/gRPC clients
- AI agent uses platform APIs and never touches database directly.
```
