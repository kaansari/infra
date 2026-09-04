# PR 06: Profile write safety tests

Repository: `apps-repo`

Depends on: PR 04

Status: implemented and locally validated on 2026-09-03; deployed static
regression suite passed PR 08 automation, interactive write acceptance pending.

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

## Implementation evidence

- Gateway preparation expiry uses one injectable clock in both in-memory and
  PostgreSQL implementations; expiry tests do not sleep.
- In-memory preparation input and output are defensively copied so callers
  cannot mutate the stored normalized profile or change set after preparation.
- Stable negative tests cover expiry, replay, user binding, OAuth-client
  binding, content binding, and resource-version conflicts.
- Response tests assert `completed`, `not_started`, and `outcome_unknown`
  operation states without retrying an uncertain mutation.
- `GOWORK=off go test -race ./internal/gateway`, `GOWORK=off go test ./...`,
  and `GOWORK=off go build ./...` passed in `ai/ceerat-agent-gateway`.
- `TestPostgresPreparationSafety` passed against an isolated local PostgreSQL
  cluster and cleaned up only its own preparation rows.
- Builder `check drift` passed. Builder `check apps` still reports the known,
  pre-existing legacy AI-tool inventory drift; PR 06 adds no tool or app
  surface and does not expand scope to repair that separate inventory.
