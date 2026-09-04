# PR 01: Gateway contract correctness

Repository: `apps-repo`

## Objective

Remove two known correctness gaps before expanding the security suite:

1. `get_authentication_status` must accept a valid authenticated OIDC access
   token even when Keycloak omits `openid` from the access token's `scope`
   claim.
2. Runtime decoding must enforce the MCP tool schemas' `additionalProperties:
   false` promise for every tool, including public tools.

## Changes

- Treat `get_authentication_status` as requiring authentication, not an
  additional business scope. Continue validating issuer, signature, audience,
  time bounds, subject/identity, and client.
- Keep `logout_current_connection` protected by authentication plus explicit
  confirmation; do not infer authorization from model arguments.
- Centralize strict argument decoding and reject unknown fields with
  `INVALID_ARGUMENT`, `agent_action=correct_arguments`, and
  `operation_state=not_started`.
- Align `tools/list` security metadata and descriptions with runtime behavior.

## Tests

- Valid token without `openid` in the scope claim can call authentication
  status.
- Missing/invalid token still returns `UNAUTHENTICATED` with an OAuth challenge.
- Unknown argument on `describe_ceerat` and every protected tool fails.
- Missing required arguments and `confirmed:false` remain rejected.
- `go test -mod=vendor ./...` passes for the gateway module.

## Non-goals

No connection schema changes, Keycloak changes, profile behavior changes, or
new tools.

## Builder-agent and documentation gate

- Before coding, run the shared builder workflow in `pr/README.md` plus
  `ceerat-builder app-surface ceerat-agent-gateway --output json`.
- Validate strict tool inputs, OAuth termination at the gateway, derived
  identity, and LLM-safe errors against
  `.ceerat-agent/public-ai-integration-security-profile.md`.
- Update the gateway README/tool contract notes in this PR.
- After merge and live ChatGPT/Codex validation, update reusable strict-schema
  and authentication-only-tool guidance in
  `.ceerat-agent/ai-tool-standard.md` and the public-AI security profile, then
  run the builder drift checks before PR 02.

## Acceptance

The authenticated Codex smoke test reports PASS for authentication status,
current user, profile, and connection listing. Public tools reject undeclared
arguments exactly as advertised.
