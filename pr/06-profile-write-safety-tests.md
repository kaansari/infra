# PR 06: Profile write safety tests

Repository: `apps-repo`

Depends on: PR 04

## Objective

Complete the permanent regression suite for the prepare/confirm write protocol
without expanding writable profile fields.

## Changes and tests

- Inject a clock into preparation storage and test expiry without sleeping.
- Confirm a preparation once, then prove replay fails.
- Prepare against version N, mutate to N+1, then prove confirmation returns a
  conflict without overwriting newer data.
- Prove preparations are bound to authenticated user and OAuth client.
- Prove a changed payload cannot be substituted after preparation.
- Exercise both in-memory and PostgreSQL state implementations.
- Assert `operation_state` distinguishes not-started, completed, and uncertain
  writes correctly.

## Non-goals

No additional profile fields, bulk updates, user-selected IDs, or retry of an
uncertain mutation.

## Builder-agent and documentation gate

- Run the shared workflow plus `ceerat-builder evidence request "MCP prepare
  confirm profile update expiry replay resource version" --output json`.
- Validate authenticated ownership, user/client/operation binding, expiration,
  replay prevention, optimistic concurrency, and uncertain-outcome behavior.
- Update gateway profile-write examples and test documentation in this PR.
- After validation, synchronize reusable prepare/confirm rules into the builder
  AI-tool and public-AI security standards before PR 07.

## Acceptance

Expiry, single use, identity/client binding, content binding, and optimistic
concurrency each have a stable negative integration test.
