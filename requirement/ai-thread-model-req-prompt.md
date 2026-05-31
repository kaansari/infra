```text
Use ceerat-platform-builder-agent as your discovery and consistency tool before implementing.

I want you to design and implement an AI thread persistence backend in the Ceerat platform.

Business context:
- Ceerat already has User, Customer, Auth/JWT, RBAC, customer portal, web/admin UI, and ceerat-agent-service.
- ceerat-agent-service currently keeps chat history in memory.
- OpenAI Threads are no longer the desired dependency for conversation persistence.
- The AI thread backend must provide a local Ceerat-owned replacement for thread/conversation history.
- The AI thread backend must follow existing Ceerat contract, service, repository, RBAC, logging, inventory, testing, and documentation patterns.
- For this req, do not make frontend changes. The requirements are only for the backend service and contracts.
- ceerat-agent-service integration can be prepared by exposing the gRPC contract and service, but do not implement frontend thread list/history UX in this task.

Business requirements:
- Persist AI chat threads for authenticated users.
- Support separate thread profiles for agent chat and customer chat.
- Thread identity must always include authenticated user + profile + external/session thread id.
- Store thread metadata such as title, created_at, updated_at, and message_count.
- Store sanitized chat messages.
- Store only user and final assistant messages for now.
- Do not store system prompts.
- Do not store assistant tool-call protocol messages.
- Do not store `tool` role messages.
- Do not store raw tool results or raw platform data returned by tools.
- Allow a caller to get or create a thread.
- Allow a caller to get one thread with recent messages.
- Allow a caller to list their own threads.
- Allow a caller to append one message.
- Allow a caller to replace a thread's sanitized messages.
- Allow a caller to delete one of their own threads.

Before coding, run:

- `ceerat-builder codex-context --output json`
- `ceerat-builder docs all --output json`
- `ceerat-builder inventory services --output json`
- `ceerat-builder inventory contracts --output json`
- `ceerat-builder inventory apps --output json`
- `ceerat-builder decide-owner "create AI thread persistence backend for agent and customer chat history" --output json`
- `ceerat-builder evidence request "create AI thread persistence backend for agent and customer chat history" --output json`
- `ceerat-builder patterns service --output json`
- `ceerat-builder patterns grpc-security --output json`
- `ceerat-builder patterns repository --output json`
- `ceerat-builder patterns testing --output json`
- `ceerat-builder cookbook service --output json`
- `ceerat-builder rbac check --output json`
- `ceerat-builder check drift --output json`
- `ceerat-builder plan --output json "create AI thread persistence backend for agent and customer chat history"`

Use builder output as factual context, not final design.

Ownership expectation:
- Decide whether AI threads should be a new gRPC service/module or an extension inside `ceerat-user-service`.
- Prefer the existing backend service boundary if builder inventory shows that user-owned persistence and JWT/RBAC enforcement already live there.
- If existing inventory shows a better owner, explain it.
- If creating a new contract package, create `ai.proto`.
- Do not put thread persistence directly inside ceerat-agent-service if the platform pattern says apps and agents must not write directly to the database.

Contract requirements:
Create an `ai` proto package with these core objects:
- `Thread`
- `ThreadMessage`
- `ThreadProfile`
- `ThreadMessageRole`

Create gRPC service:
- `AIThreadService`

Create RPCs:
- `GetOrCreateThread`
- `GetThread`
- `ListThreads`
- `AppendMessage`
- `ReplaceThreadMessages`
- `DeleteThread`

Use `infra/requirement/ai-thread-model-req.md` as the source of truth for the proto/model shape, but adapt naming, response wrappers, pagination fields, and error patterns to match existing Ceerat proto conventions.

Security and ownership requirements:
- Do not trust `user_id` from client request payloads.
- Resolve the effective user id from authenticated JWT/auth context.
- Request `user_id` may only be used for validation or admin-internal flows if that pattern already exists.
- A customer can access only their own customer-profile threads.
- An agent can access only their own agent-profile threads unless an existing admin/internal service pattern explicitly supports broader access.
- Admin access must still be intentionally scoped; do not accidentally allow admins to read every user's AI history unless the requirement is explicit.
- Agent and customer profiles must be isolated.
- Two users using the same `external_thread_id` must not share history.
- Apps and AI tools must not write directly to the database.
- ceerat-agent-service must call platform APIs/gRPC clients when later integrated.

Database requirements:
Add models/migrations for:
- `ai_threads`
- `ai_thread_messages`

Expected `ai_threads` fields:
- `id` UUID primary key
- `user_id` UUID not null
- `profile` text not null, values `agent` or `customer`
- `external_thread_id` text not null
- `title` text not null default empty string
- `created_at` timestamptz
- `updated_at` timestamptz
- unique index on `(user_id, profile, external_thread_id)`
- index for listing by `(user_id, profile, updated_at desc)`

Expected `ai_thread_messages` fields:
- `id` UUID primary key
- `thread_id` UUID references `ai_threads(id)` on delete cascade
- `user_id` UUID not null
- `profile` text not null, values `agent` or `customer`
- `role` text not null, values `user` or `assistant`
- `content` text not null
- `metadata_json` JSON/JSONB text or JSONB using existing service DB conventions, default empty JSON
- `created_at` timestamptz
- index for loading by `(thread_id, created_at asc)`
- index for auditing/listing by `(user_id, profile, created_at desc)`

Implementation steps:
1. Tell me the ownership decision and why.
2. Tell me exact files you will create, edit, or remove before changing them.
3. Implement proto/contract changes.
4. Regenerate protobuf files.
5. Implement service models, repository layer, gRPC handlers, and startup registration.
6. Add JWT/RBAC method entries and default role permissions.
7. Add authenticated-user ownership enforcement in backend handlers/repositories.
8. Keep the service ready for ceerat-agent-service to call later, but do not wire frontend UX in this task.
9. Update inventories:
   - `contracts-repo/docs/contract-inventory.json`
   - `services-repo/docs/grpc-service-inventory.json`
   - `apps-repo/docs/app-surface-inventory.json` only if app/AI surfaces change
10. Update docs:
   - service API docs
   - API testing docs
   - gRPC security docs
   - logging docs if new business events are logged
   - architecture docs if a new service/domain boundary is introduced

Tests required:
- thread identity isolation by `user_id + profile + external_thread_id`
- appending user messages
- appending assistant messages
- rejecting unsupported message roles
- loading recent messages with `message_limit`
- listing only the authenticated user's threads
- replacing sanitized thread messages
- deleting a thread cascades messages
- caller cannot access another user's thread
- agent and customer profiles are isolated
- unauthenticated caller is denied
- RBAC permission denied paths

Run verification:
- `ceerat-builder verify contract-and-service ai.AIThreadService --output json`
- run the returned contract/service test and build commands
- run affected ceerat-agent-service tests/builds only if any shared contract or client changes require it
- `ceerat-builder rbac check --output json`
- `ceerat-builder check drift --output json`
- `ceerat-builder check apps --output json`

Acceptance criteria:
- The new proto files and generated Go files are checked in.
- The backend service starts with the new AI thread service registered.
- The database schema is created through the existing service migration pattern.
- Relevant Go tests pass.
- `make build` or the repo's equivalent build command passes for changed repos.
- Service enforces authenticated-user isolation.
- Service enforces agent/customer profile isolation.
- The implementation is ready for ceerat-agent-service to call later.
- No frontend thread list/history UX is implemented in this task.
- Keep changes scoped. Do not refactor unrelated services.

Important constraints:
- Preserve Ceerat architecture: proto first, service layer, repository layer, gRPC handlers, JWT/RBAC interceptors, structured logs.
- Customer UI, web UI, admin UI, and AI agent must use APIs/gRPC clients.
- No frontend UI unless explicitly requested in a later requirement.
- Do not update `.ceerat-agent` standards until tests/builds pass and human validation confirms the behavior.
- If any ownership or service-boundary decision is ambiguous, state assumptions before coding.
```
