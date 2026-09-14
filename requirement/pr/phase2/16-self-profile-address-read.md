# Phase 2 PR 16: Self-profile shipping and billing address read

Repositories: `apps-repo`, `infra`, `ceerat-platform-builder-agent`  
Depends on: Phase 1 profile read/update and Phase 2 checkout address work

## Objective

Allow an authenticated customer using ChatGPT, Codex, or another MCP client to
read the complete shipping and billing addresses stored on their own CEERAT
profile. Extend the existing `get_my_customer_profile` result with explicit
address objects:

```json
{
  "shipping_address": {
    "line1": "...",
    "line2": "...",
    "city": "...",
    "state_or_region": "...",
    "country_code": "...",
    "postal_code": "..."
  },
  "shipping_address_complete": true,
  "billing_address": {
    "line1": "...",
    "line2": "...",
    "city": "...",
    "state_or_region": "...",
    "country_code": "...",
    "postal_code": "..."
  },
  "billing_address_complete": true
}
```

Retain the completeness flags because they are useful for checkout readiness,
but do not make them substitutes for the actual customer-visible values.

## Confirmed current-state defect

`customer.Address` already contains `line1`, `line2`, `city`, `state`,
`country`, and `postal_code`. `customer.Customer` already returns distinct
`shipping_address` and `billing_address` fields, and
`GetMyCustomerProfile` already obtains the customer from authenticated user
context. The user service and database also already persist and return all of
these fields.

The loss occurs only in
`apps-repo/ai/ceerat-agent-gateway/internal/gateway/server.go`:
`publicProfile` currently emits the two completeness Booleans while dropping
both full addresses. Therefore this PR is an MCP response-projection correction,
not a new data model or backend capability.

## Builder context, security, and architecture gate

The `ceerat-platform-builder-agent` evidence identifies:

- contract owner: `customer.CustomerService`;
- private RPC: `GetMyCustomerProfile`;
- service owner: `services-repo/services/ceerat-user-service/customers`;
- public adapter: `apps-repo/ai/ceerat-agent-gateway`;
- required interceptor order: JWT -> RBAC -> logging -> handler; and
- ownership rule: derive the customer from authenticated context and enforce
  ownership in the handler/repository, never from caller-supplied identity.

The builder impact command's generic Address CRUD suggestions are inventory
hints only and are explicitly rejected. Do not add Address CRUD RPCs, a second
profile tool, `customer_id`/`user_id` inputs, REST, browser access, direct
database access, a legacy adapter, or any parallel read path.

The one canonical path remains:

```text
public AI -> get_my_customer_profile over OAuth MCP
          -> authenticated private customer.CustomerService/GetMyCustomerProfile
          -> ceerat-user-service customer repository
          -> canonical PostgreSQL customer row
```

## Scope by repository

### `apps-repo`

- Update `publicProfile` to project both complete address objects using the MCP
  field names shown above.
- Use one small address-projection helper so shipping and billing cannot drift.
- Keep `get_my_customer_profile` input empty and closed.
- Keep the existing `ceerat.profile.read` requirement and read-only annotation.
- Update the tool description to state that the result includes full shipping
  and billing addresses for the authenticated customer.
- Add gateway unit/integration tests for exact values, distinct shipping versus
  billing values, optional `line2`, incomplete/empty address behavior, scope
  enforcement, self-scoping, and absence of internal identity data.
- Add redaction tests proving addresses never appear in structured audit logs,
  errors, request metadata, or dependency-failure details.

### `infra`

- Update this Phase 2 index and the live acceptance record after deployment.
- Document the deployed gateway commit and hosted-app Version ID used for the
  acceptance test; do not record real address values in repository evidence.

### `ceerat-platform-builder-agent`

- After implementation and live validation, update durable platform evidence
  to state that authenticated self-profile reads expose the customer's full
  shipping and billing addresses while logs redact them.
- Run inventory and drift checks. No contract/service inventory entry should be
  added because no RPC, message, or service changes.

### Explicitly unchanged

- `contracts-repo`: no protobuf, generated-code, mapper, security inventory, or
  RBAC change;
- `services-repo`: no handler, repository, model, database, migration, or
  preflight change;
- Keycloak/OAuth: no new client, secret, audience, claim, or scope.

If implementation inspection contradicts any unchanged assertion, stop and
amend this design before widening the PR.

## Response semantics

- Always use the same stable keys for both address objects.
- `line2` may be an empty string; it is not required for completeness.
- Preserve stored address values accurately. Do not invent, geocode, normalize,
  merge, or fall back from one address type to the other in the gateway.
- `*_address_complete` is true only when trimmed `line1`, `city`, state/region,
  country code, and postal code are present, matching the existing server rule.
- If an address is absent/incomplete, return its available customer-owned fields
  and `*_address_complete: false`; do not substitute profile city/state/country.
- Do not return database column names, user ownership IDs, provider fields, or
  order address snapshots as part of these objects.

## Privacy, errors, and logging

Shipping and billing addresses are sensitive personal data. Returning them to
the authenticated owner is intentional; propagating them into operational
telemetry is not.

- Require a valid bearer token and `ceerat.profile.read` before the private call.
- Preserve indistinguishable, customer-safe not-found behavior for missing or
  foreign resources; there is no caller-supplied selector to probe.
- Log only tool/RPC name, request ID, safe subject/client correlation, outcome,
  error code, and duration. Never log address values or complete profile bodies.
- Never include addresses in structured error `details`, dependency diagnostics,
  rate-limit keys, analytics, tracing attributes, or readiness output.
- Existing structured MCP errors retain `code`, `category`, `message`,
  `retryable`, `agent_action`, `operation_state`, and `request_id`; no error may
  echo the profile payload.
- Do not expose these values from public `describe_ceerat`, OAuth discovery, or
  unauthenticated endpoints.

## Automated tests

1. A profile with different complete shipping and billing addresses returns all
   six fields for each and both completeness flags are true.
2. Empty `line2` is represented safely and does not make an address incomplete.
3. A missing required field yields `complete: false` without fallback or guessed
   data.
4. The two address objects do not alias, merge, or overwrite each other.
5. The tool accepts no identity or filter arguments and remains read-only.
6. Missing token, wrong audience/issuer, expired token, and missing
   `ceerat.profile.read` are rejected before gRPC execution.
7. The authenticated subject can obtain only its own profile through the
   existing self-scoped RPC.
8. Success, validation, dependency, and authorization logs/errors contain none
   of the fixture street, postal, city, state, or country values.
9. Existing profile prepare/confirm, checkout address, OAuth, and gateway tests
   continue to pass.

Required gates:

```text
go test ./...
go build ./...
ceerat-builder rbac check --output json
ceerat-builder check apps --output json
ceerat-builder check drift --output json
ceerat-builder verify contract-and-service customer.CustomerService --output json
```

Because the contract is deliberately unchanged, `make proto` should produce no
diff. Any generated-contract diff is a design regression.

## Deployment and live acceptance

Deploy only `ceerat-agent-gateway`. Do not redeploy the user service, run a
database migration, or reconcile Keycloak for this response-only change.

After Render is serving the expected gateway commit, verify the live MCP tool
and create/refresh the ChatGPT development app version if its cached metadata or
behavior does not update. Open a new chat and use this exact read-only prompt:

```text
Using only CEERAT, read my customer profile and report my complete shipping and
billing addresses exactly as CEERAT returns them, including line 1, line 2,
city, state or region, country code, postal code, and each completeness flag.
Make no changes. Do not call any prepare, update, cart, order, logout, revoke,
or destructive tool. Report the CEERAT request ID and operation state.
```

Expected tool sequence: exactly one `get_my_customer_profile` call. PASS means
the authenticated customer's stored shipping and billing values are both
visible and accurate, the completeness flags agree with the values, and no
mutation occurs. Repeat through Codex to detect hosted-app schema/cache drift.

For committed acceptance evidence, record only PASS/FAIL, request ID, operation
state, deployed commit, app Version ID, and whether the two addresses matched
the user's private expected values. Redact the actual address values.

## Completion criteria

- Full shipping and billing addresses are returned by the existing self-profile
  MCP tool to the authenticated owner.
- OAuth scope, self-ownership, gRPC security, and read-only semantics remain
  intact.
- Address PII is absent from logs, errors, documentation, and test evidence.
- No contract, database, Keycloak, REST, browser, legacy, or parallel path is
  introduced.
- Automated gateway/build/builder gates and fresh ChatGPT and Codex acceptance
  tests pass against the deployed gateway commit.

## Out of scope

- changing either address (the existing profile prepare/confirm flow owns it);
- address validation, geocoding, standardization, suggestions, or deliverability;
- multiple saved addresses, address labels, or selecting an address book entry;
- reading another customer, admin address search, order snapshot changes, or
  exposing addresses in catalog/cart responses;
- protobuf, database, migration, service, RBAC, or OAuth changes;
- REST, browser UI, legacy compatibility, fallbacks, feature flags, or dual paths.

## Implementation record (2026-09-13)

Implemented as the planned gateway-only projection correction. The existing
`get_my_customer_profile` tool now returns distinct `shipping_address` and
`billing_address` objects with line 1, optional line 2, city, state/region,
country code, and postal code while retaining both completeness flags. The tool
description now advertises those owner-visible fields.

Regression coverage proves exact address projection, distinct shipping and
billing values, empty/incomplete address behavior without fallback, closed
selector-free input, pre-dispatch scope denial, private-token dispatch, and PII
redaction from dependency errors and audit logs. Gateway tests and build pass.
The focused gateway suite, full gateway module suite, gateway build, builder
RBAC check, app-inventory check, drift check, and customer-contract/service
verification all pass locally. Render deployment and fresh ChatGPT/Codex
acceptance remain the live completion gates.
