```text
Use ceerat-platform-builder-agent as your discovery and consistency tool before implementing.

I want you to integrate the existing backend resume download capability into the Ceerat apps and AI chat surfaces.

Business context:
- The backend-only resume download capability has already been implemented in the Career domain.
- `career.CareerProfileService/DownloadResume` returns PDF bytes and metadata for an authenticated customer's own resume.
- Resume records are customer-owned Career records.
- Resume download ownership is enforced by the backend from authenticated JWT context by resolving `customers.user_id`.
- ceerat-web-ui owns the agent-facing operational app and full-page `/chatgpt-client/` surface.
- ceerat-customer-ui owns customer-facing Career self-service and customer chat.
- ceerat-agent-service owns AI/tool orchestration and must call backend services through platform gRPC clients.
- Apps and AI agents must not read resumes directly from the database.

Business requirements:
- Allow customers in `ceerat-customer-ui` to download their own resumes from the Career resume UX.
- Allow agent-facing users in `ceerat-web-ui` to trigger resume download only through existing, authorized Career/customer workflows. Do not bypass backend ownership or RBAC.
- Add AI tool support in `apps-repo/ai/ceerat-agent-service` so chat can initiate a resume download.
- Add the download capability to both agent and customer chat tool surfaces where it is allowed by backend RBAC and ownership rules.
- Update the chat client so a chat response can present a downloadable resume file action/link.
- The chat client must not display raw base64 PDF bytes in the conversation.
- The browser should download a PDF file with the backend-provided filename and `application/pdf` content type.
- Keep TXT download out of scope unless the backend contract already supports it; this requirement is PDF-first.

Before coding, run:

- `ceerat-builder codex-context --output json`
- `ceerat-builder docs all --output json`
- `ceerat-builder inventory services --output json`
- `ceerat-builder inventory contracts --output json`
- `ceerat-builder inventory apps --output json`
- `ceerat-builder app-context --output json`
- `ceerat-builder app-context ceerat-web-ui --output json`
- `ceerat-builder app-context ceerat-customer-ui --output json`
- `ceerat-builder app-context ceerat-agent-service --output json`
- `ceerat-builder app-surface ceerat-web-ui --output json`
- `ceerat-builder app-surface ceerat-customer-ui --output json`
- `ceerat-builder app-surface ceerat-agent-service --output json`
- `ceerat-builder app-match "integrate Career resume PDF download in web UI customer UI and AI chat tools" --output json`
- `ceerat-builder app-impact ceerat-web-ui --surface "Career resume PDF download and chat download action" --output json`
- `ceerat-builder app-impact ceerat-customer-ui --surface "customer Career resume PDF download and chat download action" --output json`
- `ceerat-builder app-impact ceerat-agent-service --surface "AI tool download_resume calling CareerProfileService DownloadResume" --output json`
- `ceerat-builder evidence request "integrate Career resume PDF download in ceerat-web-ui ceerat-customer-ui ceerat-agent-service and chat client" --output json`
- `ceerat-builder patterns apps --output json`
- `ceerat-builder patterns service --output json`
- `ceerat-builder patterns grpc-security --output json`
- `ceerat-builder patterns testing --output json`
- `ceerat-builder rbac check --output json`
- `ceerat-builder check drift --output json`
- `ceerat-builder check apps --output json`
- `ceerat-builder plan --output json "integrate Career resume PDF download in web UI customer UI and AI chat tools"`

Use builder output as factual context, not final design.

Backend capability already available:
- Contract owner: `contracts-repo/packages/ceerat-contracts/proto/career/career.proto`
- Service owner: `services-repo/services/ceerat-user-service/careers`
- RPC: `/career.CareerProfileService/DownloadResume`
- Request: `DownloadResumeRequest`
- Response: `DownloadResumeResponse`
- Supported format: `RESUME_DOWNLOAD_FORMAT_PDF`
- Content type: `application/pdf`
- Response includes:
  - `file`
  - `file_name`
  - `content_type`
  - `format`
  - `resume_id`

Ownership expectation:
- `ceerat-customer-ui` owns customer-facing resume download UI and customer app HTTP download route.
- `ceerat-web-ui` owns agent-facing Career/chat surfaces and any agent-facing HTTP bridge route needed for authorized download workflows.
- `ceerat-agent-service` owns AI tool orchestration and must call `CareerProfileService/DownloadResume` through its platform gRPC client.
- `ceerat-agent-service` must not persist or log PDF bytes.
- `ceerat-agent-service` must not read resumes from the database.
- `ceerat-agent-service` must not invent resume ids; it should resolve or ask for a resume id using existing list/get resume context where available.
- If an existing app route or UI component already owns Career resume actions, extend it instead of creating a duplicate surface.

App route/API requirements:
- Add authenticated same-origin app routes that stream/download the PDF returned by the backend.
- Suggested customer route, adapt to existing conventions:
  - `GET /api/customer/career/resumes/{id}/download`
- Suggested agent/web route, adapt to existing conventions and existing Career route ownership:
  - `GET /api/agent/career/resumes/{id}/download`
- Routes must:
  - require an authenticated app session
  - forward the existing JWT to backend gRPC
  - call `career.CareerProfileService/DownloadResume`
  - set `Content-Type` from backend response
  - set a safe `Content-Disposition: attachment; filename="<file_name>"`
  - write raw PDF bytes to the HTTP response
  - avoid logging PDF bytes or auth headers
- If agent-facing download requires selecting a specific customer's resume, follow existing Career/customer ownership and RBAC patterns. Do not add arbitrary customer id trust unless the backend supports and authorizes it.

Frontend UX requirements:
- In `ceerat-customer-ui`, add a download control for each resume in the customer Career resumes view.
- In `ceerat-web-ui`, add a download control only in the existing authorized Career/resume context if that UI exposes resumes.
- Use existing UI style, route conventions, and JavaScript patterns.
- The button/link should trigger a normal browser download.
- Show loading/disabled state while download starts if the existing UI pattern supports it.
- Show a concise error when download fails.
- Do not expose raw base64 bytes in HTML, JavaScript state, local storage, or chat text.
- Do not implement a marketing page or new standalone app.

AI tool requirements:
- Add a `download_resume` tool in `apps-repo/ai/ceerat-agent-service`.
- Include the tool in the customer tool registry when the customer can download their own resume.
- Include the tool in the agent tool registry only if the agent-facing workflow is authorized by existing backend RBAC and ownership rules.
- The tool input should include:
  - `resume_id`
  - optional `format`, defaulting to PDF if omitted
- The tool should call `CareerProfileService/DownloadResume` through the existing platform client.
- The tool result should not include raw PDF bytes in the model-visible text.
- Prefer returning an action/attachment object such as:
  - `type: "download"`
  - `label`
  - `file_name`
  - `content_type`
  - `resume_id`
  - `download_url`
- If the current chat response schema only supports text/actions, extend it carefully to support download actions using existing response/action patterns.
- If binary bytes must temporarily pass through ceerat-agent-service, keep them out of persisted AI thread history and logs.
- Prefer a browser-facing app download URL over embedding base64 file bytes in JSON.

Chat client requirements:
- Update the full-page chat client in both relevant app surfaces:
  - `apps-repo/apps/ceerat-web-ui/web/chatgpt-client`
  - `apps-repo/apps/ceerat-customer-ui/web/chatgpt-client`
- Render download actions from chat responses as a clear file download control.
- The control should call the authenticated same-origin app download route.
- Do not render raw JSON/base64 to the user.
- Persisted chat history should store only sanitized user and assistant text, not PDF bytes.
- If the assistant says it prepared a resume download, the UI should show the download action beside or below that assistant message.
- Keep agent and customer chat behavior isolated.

Security and ownership requirements:
- Do not trust `customer_id`, `user_id`, or ownership fields from browser or model/tool text.
- Identity must come from the authenticated app session/JWT.
- Backend Career service remains the final authority for resume ownership.
- Customers can download only their own resumes.
- Agent/admin access must be explicit and RBAC-protected; do not create a broad resume download bypass for agents.
- Do not make `DownloadResume` public.
- Do not leak PDF bytes into logs, AI thread history, tool traces, browser local storage, or analytics.
- Do not store auth headers, JWTs, or generated download URLs containing secrets in AI history.
- Download routes must require session auth.
- Download URLs should be same-origin app routes, not direct database/file URLs.

Implementation steps:
1. Tell me the ownership decision and why.
2. Tell me exact files you will create, edit, or remove before changing them.
3. Inspect current Career resume UI/API routes in `ceerat-web-ui` and `ceerat-customer-ui`.
4. Inspect current chat response schema and action rendering in both chat clients.
5. Inspect current ceerat-agent-service tool registry and platform Career client.
6. Add or reuse app server methods to call `CareerProfileService/DownloadResume`.
7. Add authenticated HTTP download routes in the affected app servers.
8. Add resume download buttons/links in customer Career resume UX and authorized web UI resume UX.
9. Add `download_resume` tool support in ceerat-agent-service.
10. Update chat response/action schema only if needed to represent download actions safely.
11. Update chat client rendering to show download actions.
12. Update inventories:
    - `apps-repo/docs/app-surface-inventory.json`
    - `services-repo/docs/grpc-service-inventory.json` only if service-visible surfaces change
    - `contracts-repo/docs/contract-inventory.json` only if contract surfaces change
13. Update docs:
    - app route/docs for resume download
    - AI tool docs if present
    - chat client docs/setup only if response schema changes
    - builder-agent docs only after tests/builds pass and human validation confirms the behavior

Tests required:
- Customer app route requires authentication.
- Customer app route calls `DownloadResume` and streams `application/pdf`.
- Customer app route sets a safe attachment filename.
- Customer cannot download another customer's resume through route/tool flow.
- Customer Career resume UI renders a download control when resumes exist.
- Download click uses the same-origin authenticated route.
- Chat response with a download action renders a download control.
- Chat response does not render raw PDF/base64.
- `download_resume` tool calls backend gRPC with the user's forwarded JWT.
- `download_resume` tool rejects blank resume id.
- `download_resume` tool result does not include raw PDF bytes in model-visible text or persisted history.
- Agent/customer tool surfaces remain isolated.
- Existing chat send/receive still works.
- Existing thread history persistence still excludes raw tool results/PDF bytes.

Run verification:
- `ceerat-builder verify contract-and-service career.CareerProfileService --output json`
- run affected ceerat-agent-service tests/builds
- run affected app tests/builds
- in `apps-repo/ai/ceerat-agent-service`:
  - `go test ./...`
  - `go build ./...`
- in `apps-repo/apps/ceerat-web-ui`:
  - repo/app normal test command
  - repo/app normal build command
- in `apps-repo/apps/ceerat-customer-ui`:
  - repo/app normal test command
  - repo/app normal build command
- run browser/manual smoke tests if frontend behavior changed:
  - customer resume list download
  - chat-triggered resume download action
  - failed download error state
- `ceerat-builder rbac check --output json`
- `ceerat-builder check drift --output json`
- `ceerat-builder check apps --output json`

Acceptance criteria:
- Customer UI users can download their own resume PDF from the resume list/details UX.
- Agent-facing UI exposes resume download only where authorized by existing Career workflows.
- Chat agent can initiate a resume download without exposing raw PDF bytes in text/history.
- Chat client renders a usable download control from assistant/tool actions.
- Download routes are authenticated, same-origin, and stream PDF bytes with correct headers.
- ceerat-agent-service uses backend Career gRPC APIs and does not read the database directly.
- AI history remains sanitized and does not persist PDF bytes/tool raw results.
- App inventories/docs are updated.
- Relevant tests/builds and builder checks pass.

Important constraints:
- Preserve Ceerat architecture: apps call app/backend APIs, ceerat-agent-service orchestrates AI tools, Career service owns resume data and PDF generation.
- Apps and agents must not write directly to PostgreSQL.
- Do not add direct browser-to-gRPC calls.
- Do not make resume download public.
- Do not refactor unrelated auth, Career, or chat surfaces.
- Do not introduce a separate generic download service for this app integration.
- If any agent-facing ownership or route decision is ambiguous, state assumptions before coding.
```
