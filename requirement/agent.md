# Ceerat Full Verification Agent

## Delivery status

The verification program is being delivered in three ordered phases:

1. **Phase 1 — deep code and platform-reference verification:** implemented.
2. **Phase 2 — live API, gRPC, HTTP, and AI-tool boundary verification:** implemented; provider-backed nondeterministic AI prompts remain an explicit optional follow-up.
3. **Phase 3 — deterministic and exploratory real-browser verification:** not started.

The original design proposal remains below this delivery plan as background and long-term direction.

## Phase 1 — implemented

Phase 1 is a code-only verification gate built around `ceerat-platform-builder-agent` and the repository-owned Go verification tools. It does not start the local stack, invoke Kubernetes or Docker directly, execute live API mutations, or open a browser.

### Canonical command

Run from `infra`:

```bash
make verify-platform
```

This is the complete Phase 1 entry point:

```text
make verify-platform
  |
  +-- make verify-builder
  |     +-- ceerat-builder check drift --output json
  |     +-- ceerat-builder check apps --output json
  |
  +-- make verify-code
        +-- formatting inspection
        +-- go test ./...
        +-- go build ./...
        +-- go vet ./...
        +-- go test -race ./...
        +-- go test -cover ./...
        +-- pinned Staticcheck
```

Focused diagnostic targets are also available:

```bash
make verify-builder
make verify-tools
make verify-coverage
make verify-staticcheck
make verify-code
```

### Phase 1 implementation

- `infra/Makefile` owns the aggregate and focused verification targets.
- `infra/verify-code.sh` runs the deterministic gates across all six active Go modules.
- Verification tools are cached under ignored `infra/.tools/<go-version>` paths.
- Staticcheck is pinned to `v0.8.1` instead of depending on an arbitrary binary from `PATH`.
- The active Go distributions omit the `covdata` executable, so the verification script builds it from the exact selected Go toolchain source and uses an isolated `GOTOOLDIR`. It does not modify the system Go installation.
- Generated protobuf packages are checked by generation/build/test/vet. Staticcheck runs against handwritten contract packages to avoid generated-code deprecation noise.
- `ceerat-platform-verification-agent` emits the Phase 1 deep-code review instructions and requires evidence, cross-layer tracing, security review, test-quality review, explicit gaps, and a final verdict.

### Builder-agent role

`ceerat-platform-builder-agent` is the platform consistency and reference layer. Phase 1 uses it to verify:

- contract proto RPCs against `KnownGRPCMethods`;
- default RBAC permissions against known and public methods;
- contract inventory methods against service inventory methods;
- contract services against implemented service inventory;
- duplicate app routes and referenced app assets;
- live `toolDefinitions()` and `customerToolDefinitions()` against `apps-repo/docs/app-surface-inventory.json`.

The builder references were synchronized with the current implementation:

- 21 agent/admin AI tools;
- 25 customer-safe AI tools;
- current contract and service inventories;
- current app routes/assets and AI tool profiles;
- the canonical `make verify-platform` workflow.

Future changes to contracts, RBAC, services, app surfaces, or AI tool catalogs must update their inventories and must pass both builder checks.

### Current Phase 1 coverage baseline

The gate now produces real package coverage. Important current results include:

| Package | Coverage |
| --- | ---: |
| Contract security | 69.9% |
| Product search | 50.3% |
| User service user package | 43.4% |
| Customer UI server | 40.4% |
| Career job search | 37.7% |
| Careers | 36.2% |
| Web UI server | 33.6% |
| AI agent core | 24.7% |

Coverage is evidence for prioritizing tests, not proof of correctness. Packages reporting 0% remain explicit test gaps.

### Phase 1 completion criteria

Phase 1 is complete when `make verify-platform` exits successfully and the review agent has also examined the relevant change for requirement completeness, boundary cases, error semantics, concurrency, persistence, RBAC/ownership, configuration, callers, and missing tests. A successful build alone is not a Phase 1 pass.

## Phase 2 — live API verification

### Current implementation

The repository now owns a data-driven Phase 2 runner at `verification/api/verify_api.py`, invoked through `verify-api.sh` and these Make targets:

```bash
make verify-api-tools
make verify-api-read
make verify-api-security
make verify-api-write
make verify-api
```

The implementation:

- uses `curl` for HTTP scenarios and `grpcurl` with the checked-in protobuf contracts for gRPC scenarios;
- tests health, anonymous and invalid-token HTTP rejection, anonymous gRPC rejection, credentialed read boundaries, and wrong-role gRPC rejection;
- accepts admin, agent, and customer bearer tokens only through environment variables and redacts them from diagnostics;
- automatically acquires local credentials through the real authentication APIs, reusing the seeded admin and stable dedicated agent/customer verification identities when explicit tokens are absent;
- probes gRPC readiness by TCP rather than assuming protected server reflection is public;
- attempts authenticated reflection discovery when a token is available and reports an explicit skip otherwise;
- starts an unhealthy stack only when `VERIFY_API_START_STACK=true`, only through `make start-stack`, and stops only a stack that run started;
- keeps mutation execution behind `VERIFY_API_MUTATIONS=true` and verifies a customer-profile update, read-back, restoration, and restoration read-back;
- writes sanitized evidence and an explicit `PASS`, `FAIL`, `BLOCKED`, or `INCONCLUSIVE` verdict under ignored `.verification/<run-id>/summary.json`.

Credential variables are `CEERAT_ADMIN_TOKEN`, `CEERAT_AGENT_TOKEN`, and `CEERAT_CUSTOMER_TOKEN`; `CEERAT_TOKEN` remains an agent-token compatibility fallback. Local credential acquisition uses `VERIFY_API_*_EMAIL` and `VERIFY_API_*_PASSWORD` overrides, the local seeded admin settings, and stable Phase 2 identities. Credentials and tokens are never written to artifacts.

The aggregate `make verify-api` runs `make verify-platform` first, so `ceerat-platform-builder-agent` continues to validate the contract, RBAC, implementation, app, and AI-tool inventories before any live boundary test runs.

### Objective

Phase 2 will verify the running platform through its real HTTP and gRPC boundaries using `curl` and `grpcurl`. It will prove request/response behavior, authentication, RBAC, ownership, validation, persistence, and error semantics without adding browser behavior yet.

Phase 2 must always run Phase 1 first:

```text
make verify-platform
  -> start local stack if needed
  -> API discovery and health
  -> read-only scenarios
  -> authorized mutation scenarios
  -> negative/security scenarios
  -> persistence and log evidence
  -> structured report and cleanup
```

### Startup boundary

- Do not use Kubernetes commands.
- Do not invoke Docker commands directly from the verification agent.
- If the platform is not already healthy, the only permitted startup entry point is:

```bash
make start-stack
```

- The verifier must record whether it found an existing stack or started one itself.
- It may stop only processes that the same verification run started.
- Startup failure is an environment failure, not automatically a product defect.

### Commands

Phase 2 provides these `infra/Makefile` targets:

```bash
make verify-api-tools    # validate curl/grpcurl and scenario prerequisites
make verify-api-read     # public and authenticated read-only scenarios
make verify-api-write    # explicitly authorized disposable mutation scenarios
make verify-api-security # unauthenticated, role, and ownership denials
make verify-api          # aggregate Phase 1 + all authorized Phase 2 checks
```

The implementation uses one repository-owned entry point:

```text
infra/verify-api.sh
```

Scenario definitions and sanitized expected results should be data-driven rather than embedded as a large shell case statement:

```text
infra/verification/api/scenarios.json
infra/verification/api/expected-schemas/
```

### Credentials and test data

- Use dedicated test identities for admin, agent, and customer roles.
- Accept credentials or tokens only through environment variables or an approved secret provider.
- Never commit credentials, print raw JWTs, echo authorization headers, or persist cookies/tokens in artifacts.
- Prefer short-lived tokens acquired at run time.
- Mutation scenarios require an explicit opt-in such as `VERIFY_API_MUTATIONS=true`.
- All created records must use a unique run identifier and be disposable.
- Cleanup must be explicit and ownership-safe. If a safe delete API does not exist, retain a manifest of created IDs instead of modifying the database directly.
- The verifier must never write directly to PostgreSQL to manufacture a passing result.

### Scenario matrix

Every affected API should be evaluated against the applicable rows:

| Scenario | Expected evidence |
| --- | --- |
| Public success | Correct gRPC/HTTP status and response schema |
| Authenticated success | Correct role and identity are propagated |
| Missing token | `Unauthenticated` or HTTP 401 |
| Invalid/expired token | `Unauthenticated` or HTTP 401 without token disclosure |
| Wrong role | `PermissionDenied` or HTTP 403 |
| Cross-customer ownership | Denied without revealing protected records |
| Invalid input | Stable validation error and no persistence |
| Not found | Stable not-found semantics |
| Duplicate/retry | Defined idempotency or duplicate behavior |
| Timeout/cancellation | Bounded failure with context propagation |
| Mutation success | Correct response and observable persisted state |
| Partial dependency failure | No false success or inconsistent partial state |

### gRPC verification

The runner should discover the live service surface with `grpcurl` and compare it with builder inventories. For protected methods, it must attach a redacted bearer token from environment state.

Coverage should include:

- public auth methods;
- `auth.Auth/ValidateToken`;
- customer profile and ownership methods;
- service/product/catalog/cart methods;
- order and pricing methods;
- Career profile, company, job, cart, application, and metrics methods;
- AI thread methods;
- calendar methods;
- admin methods with admin-only enforcement.

For each method, record:

- full gRPC method;
- role/profile used;
- sanitized request fixture;
- expected and actual gRPC code;
- response schema assertions;
- created/read-back entity identifiers in a private run manifest;
- correlated service-log evidence when a failure occurs.

### HTTP and AI-agent verification

Use `curl` for:

- service and agent health endpoints;
- `/agent/chat` authorization and validation behavior;
- `/customer/chat` authorization and customer-role boundaries;
- agent/customer thread list/get/delete routes;
- app same-origin proxy routes relevant to API behavior.

The source catalog currently contains 21 agent/admin tools and 25 customer-safe tools. Phase 2 should maintain a tool coverage matrix that traces each tool through:

```text
tool schema
  -> ToolRunner dispatch
  -> platform client method
  -> protobuf RPC
  -> backend handler/repository
  -> RBAC/ownership
  -> sanitized result or expected error
```

Live AI calls are nondeterministic and can create business records. Therefore:

- statically require complete coverage of every tool mapping;
- live-test read-only tools with controlled prompts;
- live-test mutation tools only with explicit authorization and disposable data;
- assert invoked action names and backend effects rather than exact assistant prose;
- separate OpenAI/provider failure from Ceerat API failure.

### Artifacts and reporting

Each run should produce a sanitized, ignored artifact directory such as:

```text
infra/.verification/<run-id>/
  summary.json
  grpc-results.json
  http-results.json
  tool-coverage.json
  created-resources.json
  failures/
```

The final report must distinguish:

- product failure;
- security/RBAC/ownership failure;
- contract or response-shape drift;
- environment/startup failure;
- unavailable tool or missing credential;
- skipped mutation requiring authorization;
- inconclusive result.

The final verdict remains one of `PASS`, `FAIL`, `BLOCKED`, or `INCONCLUSIVE`.

### Optional Phase 2 extensions

1. Add provider-backed controlled prompt scenarios behind a separate cost-bearing opt-in; static AI-tool coverage remains mandatory in the builder gate.
2. Add additional disposable business-record lifecycles where APIs provide ownership-safe deletion.
3. Add a second customer fixture for direct cross-customer ownership probes.
4. Add failure-log correlation and split artifacts if CI consumers require them.

### Decisions required for optional Phase 2 extensions

- Where dedicated admin, agent, and customer test credentials will come from.
- Whether API mutation runs use a dedicated local database or a namespaced shared development database.
- Which APIs support safe cleanup and which created records must be retained in a run manifest.
- Whether OpenAI-backed live tool tests run on every invocation or only when a separate provider-test flag is enabled.
- Artifact retention duration and whether sanitized summaries should be committed, uploaded by CI, or kept locally.

### Phase 2 exit criteria

- `make verify-platform` passes first.
- The stack is reached or started only through `make start-stack`.
- The live gRPC service inventory matches builder references.
- Read-only API scenarios pass for public, agent, customer, and admin boundaries.
- Opted-in mutation scenarios verify persistence and cleanup/retention behavior.
- Negative authentication, authorization, and ownership scenarios pass.
- Every AI tool has static end-to-end mapping coverage; selected authorized live scenarios pass.
- No artifact contains raw credentials, JWTs, cookies, or sensitive response data.
- The report is reproducible and ends with an explicit verdict.

## Original long-term proposal

The target system automates **four verification layers**: Go/compiler checks, API/backend testing, browser/client testing, and AI-based exploratory verification. The browser layer is especially valuable because it lets an agent verify the application the same way a human would.

### 1. Go/compiler layer

Before any AI reviewer looks at the PR, run deterministic tools:

```bash
gofmt -w .
go test ./...
go test -race ./...
go vet ./...
staticcheck ./...
golangci-lint run
govulncheck ./...
```

`staticcheck` adds 150+ static-analysis checks, while `golangci-lint` can combine checks such as `errcheck`, `govet`, `staticcheck`, `unused`, and others into one CI gate. ([Staticcheck][1])

`govulncheck` is also worth making mandatory because it checks whether your Go code actually reaches known vulnerable dependencies rather than merely saying a vulnerable module exists. ([Go][2])

For code that handles parsers, API input, JSON, URLs, authentication data, etc., add **native Go fuzzing**:

```bash
go test -fuzz=Fuzz -fuzztime=30s ./...
```

Go's built-in fuzzing is coverage-guided and is specifically useful for finding strange inputs, crashes, and security bugs that normal unit tests miss. ([Go][3])

So your backend gate becomes:

```text
compile
   ↓
gofmt
   ↓
unit tests
   ↓
race detector
   ↓
go vet
   ↓
staticcheck
   ↓
golangci-lint
   ↓
govulncheck
   ↓
fuzz tests
```

### 2. API/integration verification

Your next agent should start the actual services and test them rather than merely inspect source code.

For example:

```text
Go services
   ↓
Postgres
Redis
MongoDB
etc.
   ↓
integration-test agent
```

That agent can test:

```text
POST /login
GET /users/:id
POST /jobs/search
POST /applications
...
```

and verify:

```text
HTTP status
response schema
database changes
authorization
invalid input
timeouts
duplicate requests
concurrency
```

I'd also introduce contract/schema testing if you have REST APIs.

For OpenAPI:

```text
implementation
      ↕
openapi.yaml
      ↕
API tests
```

That stops an agent from accidentally changing something like:

```json
{
  "userId": "123"
}
```

into:

```json
{
  "user_id": "123"
}
```

and silently breaking the frontend.

---

## 3. Yes — absolutely use a real browser for verification

This is probably the biggest improvement you can make.

Instead of your current workflow:

```text
Codex writes frontend
      ↓
you open browser
      ↓
click around
      ↓
notice something broken
      ↓
tell Codex
```

make it:

```text
Codex writes frontend
      ↓
Browser QA Agent
      ↓
opens real browser
      ↓
clicks around
      ↓
looks at console
      ↓
looks at network calls
      ↓
verifies UI
      ↓
reports bugs
      ↓
Fix Agent
```

### I would use Playwright

Playwright runs real Chromium, Firefox and WebKit browsers, supports assertions, screenshots and execution traces, and is explicitly designed for CI. ([Playwright][4])

For example:

```typescript
test('user can search for jobs', async ({ page }) => {
    await page.goto('http://localhost:3000');

    await page.getByLabel('Search').fill('golang developer');

    await page.getByRole('button', {
        name: 'Search'
    }).click();

    await expect(
        page.getByText('Search Results')
    ).toBeVisible();

    await expect(
        page.locator('.job-card')
    ).not.toHaveCount(0);
});
```

Now you no longer have to manually verify that feature.

---

# But take it one step further

Don't only use predefined Playwright tests.

Give one agent **interactive browser access**.

Playwright now has tooling specifically for coding agents, including its CLI and MCP server, allowing agents to navigate pages, click elements, fill forms, inspect pages, take screenshots, run browser code, and interact with application state. ([Playwright][4])

That means you can give your QA agent a prompt like:

```text
You are the frontend QA agent.

Start the application.

Using the browser:

1. Login as test user.
2. Search for "Go developer".
3. Open the first result.
4. Add it to cart.
5. Navigate to cart.
6. Click Apply.
7. Verify the application appears in My Applications.

While testing:

- Watch browser console errors.
- Watch failed network requests.
- Look for 4xx and 5xx responses.
- Verify loading states.
- Verify buttons aren't duplicated.
- Check layout problems.
- Check obvious accessibility problems.
- Check browser navigation.
- Check refresh behavior.

If anything fails, produce a bug report containing:
page
steps
expected
actual
console errors
network errors
screenshot
```

That is much closer to having an actual QA engineer.

---

# Browser DevTools: yes

You specifically asked about DevTools.

**Yes.**

Chrome exposes its debugging capabilities through the **Chrome DevTools Protocol (CDP)**. That includes JavaScript debugging, breakpoints, stack inspection and much more. ([Chrome DevTools][5])

Playwright can connect to an existing Chromium browser through CDP as well. ([Playwright][6])

Your QA agent can therefore inspect things like:

```text
Console
Network
DOM
JavaScript exceptions
HTTP requests
HTTP responses
cookies
localStorage
sessionStorage
performance
screenshots
page state
```

This is extremely valuable.

Suppose the UI looks correct but clicking **Apply** doesn't work.

The agent might discover:

```text
Browser:
POST /api/applications

Response:
500

Console:
TypeError: Cannot read properties of undefined

Server:
panic: nil pointer dereference
```

Now it can send the exact failure back to the fix agent.

---

# Add console-error gates

I would literally make console errors fail the test.

Example:

```typescript
const errors: string[] = [];

page.on('console', msg => {
    if (msg.type() === 'error') {
        errors.push(msg.text());
    }
});

page.on('pageerror', err => {
    errors.push(err.message);
});

...

expect(errors).toEqual([]);
```

This catches a huge number of frontend regressions.

---

# And failed network requests

Same idea:

```typescript
const failedRequests: string[] = [];

page.on('requestfailed', request => {
    failedRequests.push(
        `${request.method()} ${request.url()}`
    );
});
```

You can also fail on unexpected:

```text
HTTP 400
HTTP 401
HTTP 403
HTTP 404
HTTP 500
```

depending on the scenario.

---

# Screenshots are useful, but traces are even better

On failure, save:

```text
screenshot
video
DOM snapshot
browser console
network requests
Playwright trace
```

Playwright's Trace Viewer records DOM snapshots, network activity, console messages and screenshots throughout the test, making debugging much easier. ([Playwright][4])

So the Fix Agent gets something like:

```text
FAILURE

Test:
Apply to job

Browser:
Chromium

Step:
Click "Apply"

Expected:
Application created

Actual:
Spinner remained visible for 30 seconds

Network:
POST /applications → 500

Console:
Uncaught TypeError

Trace:
artifacts/apply-job-trace.zip

Screenshot:
artifacts/apply-job-error.png
```

That is far more useful to Codex than:

```text
"The apply button doesn't work."
```

---

# Also test multiple browsers

Once the basic flow works:

```text
Chromium
Firefox
WebKit
```

Playwright supports all three. ([Playwright][7])

I wouldn't run every test against every browser initially.

Do:

```text
Every PR:
Chromium

Before merge:
Chromium

Nightly:
Chromium
Firefox
WebKit
```

That keeps CI fast.

---

# Mobile verification

You can also automatically test:

```text
desktop
tablet
mobile
```

For example:

```text
iPhone-ish viewport
390 × 844

tablet
768 × 1024

desktop
1440 × 900
```

Then your browser agent can detect things such as:

```text
button off-screen
horizontal scrolling
modal larger than viewport
menu inaccessible
text overlap
```

---

# Accessibility

Add automated accessibility verification too.

A browser test can run something like Axe against your page and catch:

```text
missing labels
bad ARIA
insufficient landmarks
duplicate IDs
incorrect button markup
missing alt text
```

This should probably be a warning initially rather than a hard blocker until your existing UI is cleaned up.

---

# Visual regression testing

Another powerful layer is:

```text
previous approved screenshot
             ↓
        comparison
             ↓
new PR screenshot
```

If your agent accidentally turns:

```text
nice card
```

into:

```text
card occupying entire page
```

the visual test fails even if all functional tests pass.

Playwright supports screenshot assertions such as:

```typescript
await expect(page).toHaveScreenshot();
```

This is especially valuable for your frontend work.

---

# Your complete autonomous verification system

I'd eventually make the pipeline look like this:

```text
                     BUILDER AGENT
                          │
                          ▼
                   ┌──────────────┐
                   │ Go Compile   │
                   └──────┬───────┘
                          ▼
                   gofmt / go vet
                          │
                          ▼
                      staticcheck
                          │
                          ▼
                    golangci-lint
                          │
                          ▼
                     govulncheck
                          │
                          ▼
                      unit tests
                          │
                          ▼
                   race detector
                          │
                          ▼
                     fuzz tests
                          │
                          ▼
                  integration tests
                          │
                          ▼
                     API tests
                          │
                          ▼
               ┌────────────────────┐
               │ Browser QA Agent   │
               │     Playwright     │
               └─────────┬──────────┘
                         │
             ┌───────────┼────────────┐
             ▼           ▼            ▼
          Chrome      Firefox       WebKit
             │
             ▼
        functional tests
             │
             ▼
        console errors
             │
             ▼
        network errors
             │
             ▼
        screenshots
             │
             ▼
       visual regression
             │
             ▼
        accessibility
             │
             ▼
        AI exploratory QA
             │
             ▼
         Review Agent
             │
             ▼
        Security Agent
             │
             ▼
           MERGE
```

And the best part is that failures feed directly back:

```text
Browser Agent
     │
     │ FAIL
     ▼
Fix Agent
     │
     ▼
Run complete pipeline
     │
     ▼
Browser Agent
     │
     │ PASS
     ▼
Reviewer
```

### One important design choice

I would actually have **two kinds of browser QA**.

**Deterministic browser tests** are permanent Playwright tests committed to your repository. They protect known functionality every PR.

**Exploratory Browser Agent** receives a PR and instructions like:

```text
Review what changed in this PR.

Determine which user flows could be affected.

Use the browser to test those flows.

Try unexpected behavior.

Inspect console/network errors.

Report defects.
```

That second agent is where this becomes really powerful because you don't have to write every test beforehand.

So your agent workforce becomes something like:

```text
Planner
Builder × 3
Backend Tester
Browser QA
Exploratory QA
Fixer × 2
Code Reviewer
Security Reviewer
Orchestrator
```

running independently.

I think this is the direction that could realistically get you from **“I supervise Codex”** to **“I review an exception dashboard once or twice a day.”**

[1]: https://staticcheck.dev/docs/?utm_source=chatgpt.com "Welcome to Staticcheck | Staticcheck"
[2]: https://go.dev/doc/tutorial/govulncheck?utm_source=chatgpt.com "Tutorial: Find and fix vulnerable dependencies with govulncheck - The Go Programming Language"
[3]: https://go.dev/doc/security/fuzz/?utm_source=chatgpt.com "Go Fuzzing - The Go Programming Language"
[4]: https://playwright.dev/?utm_source=chatgpt.com "Fast and reliable end-to-end testing for modern web apps | Playwright"
[5]: https://chromedevtools.github.io/devtools-protocol/tot/Debugger/?utm_source=chatgpt.com "Chrome DevTools Protocol - Debugger domain"
[6]: https://playwright.dev/mcp/configuration/browser-extension?utm_source=chatgpt.com "Connecting to Browsers | Playwright"
[7]: https://playwright.dev/docs/browsers?utm_source=chatgpt.com "Browsers | Playwright"
