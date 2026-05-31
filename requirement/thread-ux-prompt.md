```text
Use ceerat-platform-builder-agent as your discovery and consistency tool before implementing.

I want you to wire ceerat-agent-service to the AIThreadService backend and implement thread list/history UX in the Ceerat chat surfaces.

Business context:
- Ceerat already has User, Customer, Auth/JWT, RBAC, ceerat-agent-service, ceerat-web-ui, and ceerat-customer-ui.
- AIThreadService is the Ceerat-owned replacement for OpenAI Threads.
- AIThreadService persists sanitized AI chat history by authenticated user, profile, and external/session thread id.
- ceerat-agent-service currently keeps chat history in memory and must move to AIThreadService-backed history.
- The frontend should let users list previous chats, open a previous chat, continue a previous chat, and start a new chat.
- The implementation must follow existing Ceerat contract, service, app proxy, authentication, frontend, inventory, testing, and documentation patterns.

Business requirements:
- ceerat-agent-service must load previous thread history from AIThreadService before calling OpenAI.
- ceerat-agent-service must persist only sanitized user/final-assistant messages after a completed chat turn.
- ceerat-agent-service must not persist system prompts, assistant tool-call protocol messages, `tool` role messages, or raw tool results.
- `/agent/chat` history must use the agent profile.
- `/customer/chat` history must use the customer profile.
- Thread identity must always include authenticated user + profile + external/session thread id.
- If the frontend sends a `session_id`, use it as AIThreadService `external_thread_id`.
- If the frontend starts a new chat, generate or receive a new stable `session_id` following existing frontend/backend conventions.
- The frontend must show a thread/history list.
- The frontend must allow selecting a previous thread and loading its messages.
- The frontend must allow continuing a selected thread.
- The frontend must allow starting a new chat.
- The frontend should show a useful thread title if available, otherwise a fallback from the first user message or timestamp.
- Empty, loading, and error states must be handled.

Before coding, run:

- `ceerat-builder codex-context --output json`
- `ceerat-builder docs all --output json`
- `ceerat-builder inventory services --output json`
- `ceerat-builder inventory contracts --output json`
- `ceerat-builder inventory apps --output json`
- `ceerat-builder app-context --output json`
- `ceerat-builder app-context ceerat-web-ui --output json`
- `ceerat-builder app-context ceerat-customer-ui --output json`
- `ceerat-builder app-surface ceerat-web-ui --output json`
- `ceerat-builder app-surface ceerat-customer-ui --output json`
- `ceerat-builder app-match "add AI chat thread history UX" --output json`
- `ceerat-builder app-impact ceerat-web-ui --route "GET /chatgpt-client/" --surface "AI chat thread history" --output json`
- `ceerat-builder app-impact ceerat-web-ui --route "POST /api/agent/chat" --surface "AI chat thread history" --output json`
- `ceerat-builder app-impact ceerat-customer-ui --surface "customer AI chat thread history" --output json`
- `ceerat-builder evidence request "wire ceerat-agent-service to AIThreadService and add AI chat thread history UX" --output json`
- `ceerat-builder patterns service --output json`
- `ceerat-builder patterns grpc-security --output json`
- `ceerat-builder patterns testing --output json`
- `ceerat-builder rbac check --output json`
- `ceerat-builder check drift --output json`
- `ceerat-builder check apps --output json`
- `ceerat-builder plan --output json "wire ceerat-agent-service to AIThreadService and add AI chat thread history UX"`

Use builder output as factual context, not final design.

Ownership expectation:
- ceerat-agent-service owns OpenAI/tool orchestration and should call AIThreadService through the platform gRPC client.
- AIThreadService owns persistence. ceerat-agent-service, web UI, and customer UI must not write thread data directly to the database.
- ceerat-web-ui owns agent-facing chat frontend and any existing full-page chat UI it already serves.
- ceerat-customer-ui owns customer-facing chat frontend if it has a separate chat surface.
- If existing inventory shows a better owner or route, explain it before coding.

Contract/client requirements:
- Use the generated `ai.AIThreadService` client from the contracts package.
- Do not redefine AI thread models locally when generated proto types are available.
- Add AIThreadService to ceerat-agent-service platform client wiring.
- Forward the authenticated JWT to AIThreadService using existing gRPC metadata patterns.
- Add HTTP routes/proxies only through existing app/server patterns.

Suggested ceerat-agent-service behavior:
1. Receive chat request.
2. Validate JWT as it does today.
3. Resolve profile:
   - `/agent/chat` -> agent thread profile
   - `/customer/chat` -> customer thread profile
4. Resolve `external_thread_id` from request `session_id`.
5. If `session_id` is missing, generate a stable new thread id and return it in the response.
6. Call AIThreadService `GetOrCreateThread`.
7. Load recent sanitized messages, likely limit 20.
8. Build OpenAI messages:
   - system prompt
   - persisted user/assistant history
   - current user message
9. Run the existing tool-calling loop.
10. Persist the completed turn through AIThreadService:
   - current user message
   - final assistant reply
11. Return `reply`, `actions`, and `session_id`.

Security and ownership requirements:
- Do not trust `user_id` from frontend requests.
- User identity must come from authenticated JWT/session context.
- Two users using the same `session_id` must not share history.
- Agent and customer profiles must be isolated.
- Agent chat history must not appear in customer chat history.
- Customer chat history must not appear in agent chat history.
- The frontend must only call authenticated app routes.
- Apps must forward the existing user JWT to ceerat-agent-service or backend services using existing patterns.
- Do not expose raw tool outputs in frontend history APIs.
- Do not leak another user's thread title or message content.

API/route requirements:
- Preserve existing chat routes:
  - `POST /agent/chat`
  - `POST /customer/chat`
  - existing app proxy routes such as `POST /api/agent/chat`
- Add backend/app routes needed by the frontend to:
  - list authenticated user's threads
  - load one selected thread's messages
  - delete one selected thread if consistent with existing UI patterns
- Suggested app route shapes, adapt to existing conventions:
  - `GET /api/agent/threads`
  - `GET /api/agent/threads/{session_id}`
  - `DELETE /api/agent/threads/{session_id}`
  - customer equivalents only if the customer UI has a separate chat surface

Frontend UX requirements:
- Use existing Ceerat frontend layout, navigation, styling, and component conventions.
- Build a work-tool UI, not a marketing page.
- Add a thread/history list sidebar or equivalent existing-layout pattern.
- Show the selected thread's persisted user/assistant messages.
- Let the user continue a selected thread.
- Let the user start a new chat.
- Show an empty state when no history exists.
- Show loading states while fetching thread list or thread messages.
- Show concise error states when fetch or chat send fails.
- Keep agent-facing and customer-facing history separate.
- Avoid visible explanatory feature text unless it matches existing product UI style.

Implementation steps:
1. Tell me the ownership decision and why.
2. Tell me exact files you will create, edit, or remove before changing them.
3. Update ceerat-agent-service platform client to include AIThreadService.
4. Replace in-memory history usage in ceerat-agent-service with AIThreadService-backed history.
5. Preserve sanitized history behavior.
6. Update ceerat-agent-service chat response/request structs if `session_id` must be returned.
7. Add app proxy routes/handlers for thread list, get, and delete using existing auth/session patterns.
8. Update frontend chat UI to list, open, continue, and start threads.
9. Update inventories:
   - `apps-repo/docs/app-surface-inventory.json`
   - `services-repo/docs/grpc-service-inventory.json` only if service surfaces change
   - `contracts-repo/docs/contract-inventory.json` only if contract surfaces change
10. Update docs:
   - AI chat architecture docs
   - AI chat setup docs if config/env changes
   - app docs for new routes

Tests required:
- ceerat-agent-service loads prior messages from AIThreadService.
- ceerat-agent-service persists only user/final-assistant messages.
- ceerat-agent-service does not persist tool protocol messages.
- missing `session_id` produces a usable returned `session_id`.
- same `session_id` from two users remains isolated by backend identity.
- agent/customer profiles remain isolated.
- app thread-list route requires authentication.
- app get-thread route requires authentication.
- frontend can render empty thread list.
- frontend can render selected thread messages.
- frontend can start a new chat.
- frontend can continue an existing chat.

Run verification:
- `ceerat-builder verify contract-and-service ai.AIThreadService --output json`
- run affected ceerat-agent-service tests/builds
- run affected app tests/builds
- `ceerat-builder rbac check --output json`
- `ceerat-builder check drift --output json`
- `ceerat-builder check apps --output json`
- run the repo's standard frontend build/test commands returned by builder or documented in the app README/Makefile

Acceptance criteria:
- Existing chat still works.
- Chat history survives ceerat-agent-service restart because history is loaded from AIThreadService.
- Two users using the same `session_id` cannot see each other's history.
- Agent and customer chat profiles remain isolated.
- Tool messages/results are not persisted.
- Frontend can list, open, continue, and start chats.
- Relevant backend and frontend tests pass.
- Changed apps/services build successfully.
- Changes are scoped to ceerat-agent-service, affected app chat surfaces, docs, and inventories.

Important constraints:
- Preserve Ceerat architecture: apps call app/backend APIs, ceerat-agent-service orchestrates AI, persistence lives in AIThreadService.
- Apps and agents must not write directly to the database.
- Do not refactor unrelated service, auth, or UI areas.
- Do not update `.ceerat-agent` standards until tests/builds pass and human validation confirms the behavior.
- If any ownership, route, or UX-surface decision is ambiguous, state assumptions before coding.
```
