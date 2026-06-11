You are working in the Ceerat multi-repo workspace.

Goal:
Implement an AI-assisted resume import flow for the customer Career domain.  Customers will perform this task by uploading their resume in txt or .md file format.  The system should parse the file into relevent sections and present the findings in summary back to the customer, the customer will then ask the system to create skill/skills, employment records and resume. A customer should upload a resume text file in the customer AI agent, and the platform should use service-owned parsing plus AI-assisted structuring to create:
- a skill profile
- multiple skills
- multiple employment records
- a resume
- resume-to-employment attachments

Important:
Use the Ceerat builder agent first for security, consistency, and architectural integrity. Run builder-agent discovery from the Ceerat workspace root, not from an individual repo.

Workspace root:
 /Users/kaansari/go/src/github.com/kaansari

Relevant repos:
- infra/
- services-repo/services/ceerat-user-service
- contracts-repo/packages/ceerat-contracts
- apps-repo/ai/ceerat-agent-service
- apps-repo/apps/ceerat-customer-ui
- ceerat-platform-builder-agent

Builder-agent commands:
1. From workspace root, inspect ownership and standards:
   - ceerat-builder plan --output json "customer AI resume text upload import flow creates career profile skills employment records and resume"
   - ceerat-builder inspect grpc-service-inventory
   - ceerat-builder inspect app-surface-inventory
   - ceerat-builder inspect grpc-security
   - ceerat-builder inspect ai-tool-standard
   - ceerat-builder inspect service-standards
   - ceerat-builder check drift
   - ceerat-builder rbac check

Use builder output as guidance. Do not treat builder as a code generator.

Architecture requirements:
1. The service layer must own resume parsing/import orchestration.
2. The browser must not parse resumes into database records directly.
3. The AI agent must not write directly to PostgreSQL.
4. All customer identity must come from authenticated JWT context, not request customer_id.
5. Resume text is sensitive. Do not store raw uploaded text outside the intended resume/content records unless there is an explicit service-owned audit requirement.
6. Do not log raw resume text, extracted PII, file bytes, or AI prompts containing full resume content.
7. The AI may help structure extracted resume text, but backend services must validate ownership, required fields, sizes, and allowed mutations.
8. The flow must be idempotent enough to avoid duplicate skills/employment records on retry where practical.
9. Implement batch APIs first so the AI tool layer does not need to call one skill/employment insert per item.
10. Keep existing career/profile/resume/employment behavior working.

Service/API design:
Contracts live at:
 ../contracts-repo/packages/ceerat-contracts

Career service lives at:
 ../services-repo/services/ceerat-user-service

AI service lives at:
 ../apps-repo/ai/ceerat-agent-service

Customer UI lives at:
 ../apps-repo/apps/ceerat-customer-ui

Add or extend Career domain RPCs. Prefer extending CareerProfileService unless builder-agent recommends a different existing owner.

Suggested contract additions:
- ParseResumeText
  Input:
  - file_name
  - content_type
  - text
  Output:
  - parsed_resume_draft

- ImportResumeDraft
  Input:
  - parsed_resume_draft
  - import_options
  Output:
  - skill_profile
  - skills
  - employment_records
  - resume
  - resume_employment_records
  - warnings

- BatchAddSkillsToProfile
  Input:
  - skill_profile_id
  - skills[]
  Output:
  - skills[]

- BatchCreateEmploymentRecords
  Input:
  - employment_records[]
  Output:
  - employment_records[]

- BatchAttachEmploymentRecordsToResume
  Input:
  - resume_id
  - attachments[]
  Output:
  - resume_employment_records[]

Parsed resume draft shape:
- profile_name
- target_role
- summary
- skills[]
  - name
  - category
  - level
  - years_experience
  - description
- employment_records[]
  - company_name
  - title
  - location
  - start_date
  - end_date
  - is_current
  - summary
  - employment_type
  - sort_order
- resume
  - title
  - name
  - content
  - is_active

Backend implementation requirements:
- Add proto messages/RPCs.
- Regenerate protobufs.
- Add handler methods.
- Add repository methods.
- Add DB support only if needed.
- Add RBAC/KnownGRPCMethods/DefaultRolePermissions for new RPCs.
- Enforce customer ownership from JWT context.
- Batch insert skills and employment records transactionally where practical.
- Attach employment records to resume only after verifying ownership of both resume and employment records.
- Validate uploaded text size and content type.
- Reject empty or oversized resume text.
- Normalize duplicate skills by customer/profile where practical.
- Avoid duplicate employment records on retry using a reasonable matching rule, such as company/title/start_date/customer_id, unless builder-agent recommends another approach.
- Return warnings instead of silently dropping unsupported fields.

Resume parsing approach:
- Start with a deterministic text parsing service in ceerat-user-service that:
  - cleans plain text
  - extracts likely sections
  - preserves original resume text for resume.content
  - returns a draft suitable for AI structuring
- The AI agent can call a service-owned parse/import tool.
- If AI structuring is used, keep the final write behind ImportResumeDraft so backend validates before persistence.
- Do not let the browser or AI agent directly call batch repository methods.

AI tool changes:
In ceerat-agent-service:
- Add customer-safe tools such as:
  - parse_resume_text
  - import_resume_draft
  - import_resume_text
- Prefer one high-level tool if safe:
  - import_resume_text(file_name, content_type, text, confirmed)
- Require explicit customer confirmation before creating records if the AI has inferred or transformed content.
- Tool descriptions must say:
  - do not invent employment history
  - do not invent degrees/certifications
  - only infer skill names from explicit resume content
  - ask the customer before creating records when confidence is low
- Keep tool calls under the platform API boundary.
- Allow AI to do the above in multiple steps for content integritiy.

Customer UI changes:
In ceerat-customer-ui:
- Allow resume text file upload in the customer AI chat or a Career import page.
- Accept text-like files only initially:
  - .txt
  - .md
otherwise defer
- Read text client-side only to send it to the same-origin Ceerat AI/API route.
- Do not call OpenAI or backend gRPC directly from browser code.
- Show a confirmation step before import writes records.
- After successful import, link to:
  - created skill profile
  - created resume
  - created employment records

Tests:
Add focused tests for:
- ParseResumeText rejects empty text.
- ParseResumeText rejects oversized text.
- ParseResumeText does not require request customer_id.
- ImportResumeDraft creates profile, batch skills, employment records, resume, and attachments for authenticated customer.
- ImportResumeDraft rejects access to another customer’s profile/resume/employment records.
- BatchAddSkillsToProfile creates multiple skills in one call.
- BatchCreateEmploymentRecords creates multiple customer-owned employment records in one call.
- BatchAttachEmploymentRecordsToResume verifies ownership of resume and employment records.
- Duplicate retry does not create obvious duplicate skills/employment records where idempotency is implemented.
- AI tool definitions expose customer-safe import tools only.
- AI import tool requires confirmation for mutations.
- Customer UI upload rejects unsupported files and routes through same-origin API.

Docs:
Update:
- ceerat-agent-service README/tool docs
- ceerat-customer-ui docs if applicable
- ceerat-platform-builder-agent docs:
  - ai-tool-standard.md
  - service-standards.md
  - domain-requirements.json
  - platform-overview.html

Verification:
Run relevant commands:
- contracts proto generation/build/tests
- ceerat-user-service tests
- ceerat-agent-service tests
- ceerat-customer-ui tests
- builder-agent checks:
  - ceerat-builder check drift
  - ceerat-builder rbac check

Deliverables:
1. Summarize builder-agent findings.
2. Summarize final architecture.
3. List changed files.
4. List tests/build commands run and results.
5. Note any deferred parser support, such as PDF/DOCX, if not implemented.