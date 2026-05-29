Use this prompt:

```text
Use ceerat-platform-builder-agent as your discovery and consistency tool before implementing.

I want to split Ceerat AI assistant behavior by user surface without creating a separate service yet.

Goal:
Keep one `ceerat-agent-service` binary, but add a customer-specific assistant path for `ceerat-customer-ui`.

Current issue:
`ceerat-customer-ui` forwards customer chat to the same `/agent/chat` endpoint used by `ceerat-web-ui`. The agent service validates the customer JWT, but it uses the agent/admin-oriented prompt and tool list, so customer questions like “what is my name/email?” or “list jobs matching my Architect skill profile” do not work correctly.

Implementation requirements:
- Keep existing `/agent/chat` behavior for `ceerat-web-ui`.
- Add a new customer assistant endpoint:
  - `POST /customer/chat`
- Update `ceerat-customer-ui` so its chat routes forward to:
  - `ceerat-agent-service POST /customer/chat`
- Add customer-specific platform gRPC client methods for:
  - get my customer profile
  - update my customer profile
  - list my skill profiles
  - create skill profile
  - add skill to profile
  - list my resumes
  - create resume
  - search open jobs
  - get job
  - get job cart
  - add job to cart
  - update job cart item
  - remove job from cart
  - clear job cart
  - apply to job
  - apply to cart jobs
  - list my applications
  - get my application
- Add customer-safe AI tools only for the customer assistant route.
- Add a customer-specific system prompt.
- The customer assistant should help customers perform self-service tasks:
  - answer questions about their own profile
  - update their own address/contact fields
  - create skill profiles
  - add skills to profiles
  - create/list resumes
  - search open jobs
  - match jobs to named skill profiles when possible
  - add jobs to cart
  - apply to jobs using selected profile/resume
  - list/view their own applications
- The customer assistant must not expose agent/admin tools:
  - create customer
  - list all customers
  - create company
  - update company
  - create job
  - update job
  - close job
  - list all applications for a job
  - update application status
- Customer assistant must never ask for or trust `customer_id`.
- Customer ownership must still be enforced by backend JWT/RBAC/service logic.
- The assistant may use IDs returned from list/search/get tools, but must not invent IDs.
- If the user gives names/titles instead of IDs, the assistant should list/search first and ask the customer to choose if multiple matches exist.
- If permission is denied, explain that the account cannot perform that action.
- Browser apps must not call OpenAI directly.
- Apps and agents must not write directly to the database.

Before coding, run:

- `ceerat-builder codex-context --output json`
- `ceerat-builder docs all --output json`
- `ceerat-builder inventory apps --output json`
- `ceerat-builder inventory services --output json`
- `ceerat-builder inventory contracts --output json`
- `ceerat-builder app-context --output json`
- `ceerat-builder app-surface ceerat-customer-ui --output json`
- `ceerat-builder app-surface ceerat-web-ui --output json`
- `ceerat-builder app-surface ceerat-agent-service --output json`
- `ceerat-builder app-match "customer ai assistant career self service" --output json`
- `ceerat-builder patterns grpc-security --output json`
- `ceerat-builder evidence request "add customer-specific AI assistant route and customer-safe tools" --output json`
- `ceerat-builder plan --output json "add customer-specific AI assistant route and customer-safe tools"`

Use builder output as factual context, not final design.

Implementation expectations:
1. Identify the current AI route/tool/prompt wiring in:
   - `apps-repo/ai/ceerat-agent-service/internal/httpapi/server.go`
   - `apps-repo/ai/ceerat-agent-service/internal/agent/agent.go`
   - `apps-repo/ai/ceerat-agent-service/internal/agent/tools.go`
   - `apps-repo/ai/ceerat-agent-service/internal/platform/client.go`
2. Refactor agent service so `/agent/chat` and `/customer/chat` can use different:
   - system prompts
   - tool definitions
   - tool dispatch allowlists
3. Preserve existing `/agent/chat` behavior.
4. Add customer platform client methods using existing customer/career gRPC contracts.
5. Add customer tool definitions and dispatch handlers.
6. Update `ceerat-customer-ui` chat forwarding endpoints so customer chat calls `/customer/chat`.
7. Do not change `ceerat-web-ui` chat forwarding unless needed to preserve `/agent/chat`.
8. Add focused tests for:
   - `/agent/chat` still uses agent tool profile
   - `/customer/chat` uses customer tool profile
   - customer route does not expose admin/agent tools
   - customer profile tool forwards JWT and returns own profile
   - update my profile/address maps to `UpdateMyCustomerProfile`
   - customer career tools map to Career gRPC methods
   - permission denied returns friendly response
9. Update docs/inventory:
   - `apps-repo/docs/app-surface-inventory.json`
   - `apps-repo/ai/docs/agent-tools.md`
   - `apps-repo/ai/docs/ai-chat-architecture.md`
   - `ceerat-platform-builder-agent/.ceerat-agent/ai-tool-standard.md` only after tests pass
10. Run:
   - `go test ./...` from `apps-repo/ai/ceerat-agent-service`
   - `go build ./...` from `apps-repo/ai/ceerat-agent-service`
   - `go test ./...` from `apps-repo/apps/ceerat-customer-ui`
   - `go build ./...` from `apps-repo/apps/ceerat-customer-ui`
   - `ceerat-builder check apps --output json`
   - `ceerat-builder check drift --output json`

After implementation, summarize:
- routes added/changed
- customer-safe tools added
- agent/admin tools preserved
- files changed
- tests/builds passed
- remaining live validation risks
```