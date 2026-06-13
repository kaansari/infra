Copy/paste prompt for Codex:

```text
You are working in the Ceerat multi-repo workspace.

Goal:
Add a customer-facing resume upload/import feature to the ceerat-customer-ui resume pages. The AI chat upload flow already works, but customers also need a clear upload/import button directly in the Career Resumes UI.

Important:
Use ceerat-platform-builder-agent first for security, consistency, and architectural integrity. Run builder-agent discovery from the Ceerat workspace root, not from an individual repo.

Builder-agent commands/context:
- cd /Users/kaansari/go/src/github.com/kaansari/ceerat-platform-builder-agent
- ceerat-builder plan --output json "customer resume upload import UI for Career resumes"
- ceerat-builder inventory services --output json
- ceerat-builder app-context --output json
- ceerat-builder patterns grpc-security --output json
- ceerat-builder requirements career --output json
- ceerat-builder rbac check --output json
- ceerat-builder check drift --output json

Existing backend/service support:
- Contracts live at:
  ../contracts-repo/packages/ceerat-contracts
- Career service lives at:
  ../services-repo/services/ceerat-user-service
- Customer UI lives at:
  ../apps-repo/apps/ceerat-customer-ui

Use the existing service-owned Career APIs:
- career.CareerProfileService/ParseResumeText
- career.CareerProfileService/ImportResumeDraft

Do not create direct browser/database writes.
Do not trust or send customer_id from the browser.
The customer UI must call same-origin Ceerat API routes only.
The backend/app server must forward the logged-in JWT to Career gRPC.
Raw uploaded resume text must not be logged or stored in chat/thread history.

UI requirements:
1. Add a resume upload/import entry point on the customer resumes list page:
   - Route: /customer/career/resumes
   - Add a clear button/action such as "Import resume"
   - Keep the page mobile-friendly.

2. Add a separate import page:
   - Route: /customer/career/resumes/import
   - This follows the Ceerat UI standard:
     - list page: /customer/career/resumes
     - create page: /customer/career/resumes/new
     - import page can be a separate task page
     - detail page: /customer/career/resumes/{id}
     - edit page: /customer/career/resumes/{id}/edit

3. Import page behavior:
   - Accept .txt and .md only.
   - Max upload size should match service parser limit, currently 200 KB.
   - Show selected file name and size.
   - Provide a preview/review step after ParseResumeText.
   - Show parsed:
     - profile name
     - target role
     - summary/profile text
     - skills
     - employment records
     - resume content/title
     - warnings
   - Let the customer edit reviewed fields before import where practical.
   - Add an explicit "Create profile and resume" confirmation button before ImportResumeDraft.
   - On success, redirect to /customer/career/resumes/{id}.

4. API bridge requirements in ceerat-customer-ui:
   - Add same-origin endpoints, for example:
     - POST /api/customer/career/resumes/parse-upload
     - POST /api/customer/career/resumes/import-draft
   - These endpoints call:
     - CareerProfileService/ParseResumeText
     - CareerProfileService/ImportResumeDraft
   - They must use the session JWT and not accept customer_id.
   - Validate file/text input server-side too:
     - required text
     - allowed extension/content type
     - max size
   - Do not log raw resume text.

5. UX details:
   - Keep the import page focused on one task.
   - Do not crowd the resumes list with parsing UI.
   - Use existing Career nav, breadcrumbs, and back button patterns.
   - Breadcrumb should respect hierarchy:
     Career / Resumes / Import
   - On successful import, show a success message or redirect to the created resume detail page.
   - On parser warnings, show them clearly but do not block import unless the service returns an error.
   - Do not invent missing employment dates, titles, companies, or skills in frontend code.

6. Tests:
   Add focused customer-ui tests for:
   - /customer/career/resumes/import renders as a separate protected page
   - unauthenticated import page redirects to login
   - parse-upload rejects unsupported file types
   - parse-upload rejects oversized resume text
   - parse-upload forwards to CareerProfileService/ParseResumeText with authenticated JWT
   - import-draft forwards to CareerProfileService/ImportResumeDraft with authenticated JWT
   - import success redirects or returns created resume id
   - raw uploaded resume text is not included in logs/test-visible activity metadata

7. Docs:
   Update:
   - apps-repo/apps/ceerat-customer-ui/README.md
   - apps-repo/apps/ceerat-customer-ui/docs/customer-ui-architecture.html
   - apps-repo/docs/app-surface-inventory.json
   - ceerat-platform-builder-agent docs if needed:
     - .ceerat-agent/platform-overview.html
     - .ceerat-agent/ui-standard.md
     - .ceerat-agent/service-standards.md if API ownership guidance changes

8. Verification:
   Run:
   - go test ./... in apps-repo/apps/ceerat-customer-ui
   - go build ./... in apps-repo/apps/ceerat-customer-ui
   - ceerat-builder rbac check --output json
   - ceerat-builder check drift --output json

Deliverables:
1. Summarize builder-agent findings.
2. Summarize final UI/API flow.
3. List changed files.
4. List tests/build/checks run and results.
5. Mention any gaps or follow-up work.
```