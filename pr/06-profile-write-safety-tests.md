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

## Acceptance

Expiry, single use, identity/client binding, content binding, and optimistic
concurrency each have a stable negative integration test.
