# Phase 2 product/cart live acceptance

Run the credential-free suite against the deployed development gateway:

```bash
make verify-phase2-live
```

The runner writes a mode-0600 result to
`.verification/phase2-codex.json`, which is ignored by Git. The versioned result
contains only check names, PASS/FAIL/manual status, safe evidence summaries,
time, and public target origin. It never retains OAuth tokens, secrets,
credentials, cookies, response bodies, cart contents, customer data, database
URLs, or SQL rows.

For disposable PostgreSQL migration/repository coverage:

```bash
CEERAT_TEST_DATABASE_URL='postgres://...' make verify-phase2-live
```

The database account must be permitted to create and remove an isolated test
schema. Never point this variable at a database where the test account cannot
safely manage disposable schemas. To include the credential-free live limiter
check, wait for the current minute bucket to reset and set
`CEERAT_PHASE2_RUN_RATE_LIMIT=true`.

## Deployment prerequisites

Before authenticated testing, confirm the PR 04 SQL migration ran once and the
service schema preflight passed. The user service and gateway must be deployed
from the commits recorded in the PR 07 report. Verify `/readyz` after each
deployment. Exercise rollback only against a disposable clone; production uses
roll-forward recovery if rollback safety checks fail.

## ChatGPT acceptance prompt

Connect a disposable CEERAT User A with all Phase 1 and Phase 2 scopes, then
paste this prompt:

```text
Use only CEERAT. First list the CEERAT product-domain tools and verify all seven
are present. Read my authentication status and complete scope list. List at
most five active products, retrieve one product detail, and read my cart.

Do not modify anything yet. Report PASS/FAIL for discovery, product listing,
product detail, cart read, customer-safe fields, and scopes. Include CEERAT
request IDs, but do not reveal tokens, credentials, customer/user IDs, raw
backend errors, or private connection data.
```

After choosing a disposable active product and recording the original cart,
ask ChatGPT to perform the reversible mutation sequence below. Explicitly
approve each consequential action when prompted:

```text
Use only CEERAT and the disposable product selected for this test. Read my cart
to obtain its current version. Add quantity 1 using a fresh idempotency key,
then repeat the exact add request and prove there is only one effect. Read the
cart again. Try one update with the stale pre-add version and verify CONFLICT,
then update using the current version and a fresh key. Remove the test item
using the returned version and another fresh key. Finally read the cart and
prove it matches the original state. Stop on OUTCOME_UNKNOWN and read the cart
before deciding whether any retry is safe. Report only safe results and CEERAT
request IDs.
```

If the disposable cart is non-empty, test clear only after its contents can be
restored exactly:

```text
Use only CEERAT. Prepare clearing my current cart using its current version and
a fresh idempotency key. Show me the item-count/total/version preview and ask
for confirmation. After I explicitly approve, execute the prepared clear once,
prove replay is rejected, and then restore every disposable item using fresh
keys and current versions. Stop and reconcile by reading the cart if any result
is uncertain.
```

Repeat the read/isolation checks with disposable User B. Neither prompt nor tool
arguments may contain `customer_id` or `user_id`. A cannot consume B's clear
preparation or mutate an item belonging only to B. Finish by logging out one
disposable connection and proving subsequent cart access requires reconnection.

## Codex and operator evidence

Repeat the same sequence through the CEERAT MCP connection in Codex. For every
tool, retain only UTC time, prompt/test-case identifier, expected and actual
safe code/state, MCP request ID, matching audit event ID, and PASS/FAIL.

In Render logs, correlate each request ID and verify:

- accepted mutations have `started` and final events with the same request ID;
- scope denial, invalid input, not-found, rate-limit, conflict, replay,
  confirmation, dependency failure, success, logout, and post-revocation denial
  are represented;
- downstream methods are the self-scoped gRPC methods;
- no authorization header, token, cookie, password, SMTP/API secret, database
  URL, notes, idempotency key, response body, email, or cross-user record appears.

Do not declare or tag Phase 2 complete until every `MANUAL_REQUIRED` result is
replaced by reviewed, redacted PASS evidence and all test-created state is
restored or deleted.
