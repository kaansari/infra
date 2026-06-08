Copy/paste prompt for Codex:

```text
You are working in the Ceerat multi-repo workspace.

Goal:
Implement reusable customer employment records for the Career domain. Customers should create employment history once, then attach selected employment records to one or more resumes. Do not duplicate employment records inside each resume.

Important:
Use the Ceerat builder agent first for security, ownership, API consistency, and architectural integrity. Treat builder output as guidance for service ownership, contract boundaries, RBAC/security updates, and UI surface inventory.

Run builder-agent discovery from the Ceerat workspace root, not from an individual repo:

- Decide owner for: "customer-owned employment records that can attach to resumes"
- Generate a local implementation plan
- Inspect grpc-security patterns
- Inspect ceerat-customer-ui app context

Expected architecture:
1. Employment records are customer-owned Career domain records.
2. Employment records are not skills.
3. Employment records are not embedded directly in each resume.
4. Resumes attach employment records through an association/join model.
5. Skill profiles may later reference employment records for matching/curation, but they should not own employment history.
6. Browser/customer UI must call Ceerat APIs only.
7. Backend must derive customer identity from auth/JWT context, not request customer_id.
8. Repository methods must enforce ownership of both the resume and the employment record.
9. Update RBAC/KnownGRPCMethods/DefaultRolePermissions for any new protected RPCs.
10. Add focused tests.

Backend implementation:
- Contracts live at:
  ../contracts-repo/packages/ceerat-contracts

- Career service lives at:
  ../services-repo/services/ceerat-user-service

Add contract/API support under the Career domain, preferably extending the existing career profile/resume service boundary unless builder agent recommends a cleaner existing owner.

Suggested proto/RPCs:
- CreateEmploymentRecord
- ListMyEmploymentRecords
- GetEmploymentRecord
- UpdateEmploymentRecord
- DeleteEmploymentRecord or ArchiveEmploymentRecord
- AttachEmploymentRecordToResume
- DetachEmploymentRecordFromResume
- UpdateResumeEmploymentRecord

Suggested data model:
employment_records:
- id
- customer_id
- company_name
- title
- location
- start_date
- end_date
- is_current
- summary
- employment_type
- created_at
- updated_at

resume_employment_records:
- id
- resume_id
- employment_record_id
- sort_order
- include
- tailored_title
- tailored_summary
- created_at
- updated_at

Implementation requirements:
- Add database migration(s).
- Add models/repository methods.
- Add gRPC handler methods.
- Add RBAC/security method registration.
- Regenerate protobufs.
- Ensure all mutations are scoped to the authenticated customer.
- Ensure attaching a record checks ownership of both the resume and the employment record.
- Preserve existing resume/profile behavior.
- Do not break existing career routes or tests.

Customer UI implementation:
Customer UI lives at:
../apps-repo/apps/ceerat-customer-ui

Follow the established Ceerat UI navigation standard:
- List page: /customer/career/employment
- Create page: /customer/career/employment/new
- Detail page: /customer/career/employment/{id}
- Edit page: /customer/career/employment/{id}/edit

Update Career navigation so Employment Records appears consistently with:
- Overview
- Skill Profiles
- Resumes
- Employment Records
- Jobs
- Job Cart
- Applications

Resume detail page:
- Show attached employment records.
- Add an action to attach existing employment records.
- Allow ordering/include/tailoring of attached employment records.
- Do not force users to retype employment per resume.
- Keep mobile UX simple: one primary task per page, cards over wide tables.

Tests:
Add focused tests for:
- creating employment records
- listing only the authenticated customer’s employment records
- getting/updating only owned employment records
- rejecting access to another customer’s employment record
- attaching an owned employment record to an owned resume
- rejecting attach when resume or employment record is not owned by the customer
- detaching employment from resume
- preserving per-resume ordering/include/tailored fields
- customer UI route/render tests for list/create/detail/edit pages

Docs:
Update customer UI rendering/navigation standard docs if needed.
Update API docs to explain:
- employment records are reusable customer-owned career records
- resumes attach employment records
- skills are competencies, not employment history
- customer identity comes from auth context

Verification:
Run relevant tests in:
- contracts repo
- ceerat-user-service
- ceerat-customer-ui

Also run protobuf generation/build steps required by the repo.

Deliverables:
1. Summarize builder-agent findings.
2. Summarize final architecture decision.
3. List changed files.
4. List tests/build commands run and results.
5. Mention any gaps or follow-up work.
```