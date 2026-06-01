Use this prompt with Codex:

```md
Use the builder agent for consistency and architecture integrity before making any code changes.

Task:
Implement the auth/session cleanup where `auth.Auth/ValidateToken` returns authenticated user claims directly, so callers do not locally parse `user.id` from the JWT payload after validation.

Context:
Currently `apps-repo/ai/ceerat-agent-service/internal/platform/client.go` does:

1. Calls `auth.Auth/ValidateToken`.
2. Checks `resp.valid`.
3. Separately decodes the JWT payload locally in `userIDFromJWT(token)` to extract `user.id`.

This is acceptable only because `ValidateToken` cryptographically validates the exact token first, but the cleaner architecture is for `ceerat-user-service` to return the authenticated user/claims directly from the validated token/current user lookup.

Required builder-agent workflow:
1. Run builder discovery first:
   - `ceerat-builder codex-context --output json`
   - `ceerat-builder docs all --output json`
   - `ceerat-builder inventory contracts --output json`
   - `ceerat-builder inventory services --output json`
   - `ceerat-builder inventory apps --output json`
   - `ceerat-builder evidence request "return authenticated user from auth ValidateToken and stop local JWT payload parsing in agent service" --output json`
   - `ceerat-builder patterns service --output json`
   - `ceerat-builder patterns grpc-security --output json`
   - `ceerat-builder patterns testing --output json`
   - `ceerat-builder rbac check --output json`
   - `ceerat-builder check drift --output json`
2. Use builder output as factual context, not final design.
3. Preserve existing service ownership:
   - Contract owner: `contracts-repo/packages/ceerat-contracts/proto/auth/auth.proto`
   - Implementation owner: `services-repo/services/ceerat-user-service/user`
   - Caller to update: `apps-repo/ai/ceerat-agent-service/internal/platform/client.go`
4. Do not create a new service or new auth boundary.

Implementation requirements:
1. Update `auth.proto` so `message Token` includes the authenticated user.
   - Prefer adding a backward-compatible field:
     - `User user = 4;`
   - Do not break existing fields:
     - `token = 1`
     - `valid = 2`
     - `errors = 3`
2. Regenerate protobuf Go files with the repo’s normal proto generation command.
3. Update `ceerat-user-service` `ValidateToken` implementation to return the current authenticated user when token validation succeeds.
   - It should still:
     - cryptographically decode/validate JWT via `TokenService.Decode`
     - require `claims.User.ID`
     - load the current user from repository
     - reject inactive/pending/blocked users
   - Return the fresh/current user, not stale JWT user claims, so role/status/name/email reflect current DB state.
4. Update tests for `ValidateToken`.
   - Successful validation should assert `valid == true` and returned `user.id` is populated.
   - Inactive/current-user rejection behavior should remain covered.
   - Bad/empty claims should still return invalid behavior.
5. Update `ceerat-agent-service/internal/platform/client.go`.
   - `ValidateSession` should use `resp.GetUser().GetId()` from `ValidateToken`.
   - Remove local JWT payload parsing helper `userIDFromJWT`.
   - Remove now-unused imports such as `encoding/base64` and `encoding/json`.
   - Keep `Session{Token, UserID}` shape unchanged unless builder evidence says otherwise.
6. Check whether other callers can benefit from the returned user without forcing unrelated changes.
   - Do not refactor unrelated app clients unless needed for compile/tests.
7. Update contract/service inventories and docs if they describe `ValidateToken`.
   - `contracts-repo/docs/contract-inventory.json`
   - `services-repo/docs/grpc-service-inventory.json`
   - `services-repo/services/ceerat-user-service/docs/api.md`
   - Any security docs that say ValidateToken only returns validity.
8. Update builder-agent docs only if this becomes a durable standard:
   - Auth validation responses should return authenticated user/claims from the auth service.
   - Callers should not decode JWT payloads locally after validation.

Security requirements:
1. Do not make `ValidateToken` public beyond its existing public allowlist status.
2. Do not return password/token secrets in the returned user.
3. The returned user must be sanitized using existing response mapping patterns.
4. Do not trust browser/model-supplied user ids.
5. Do not weaken JWT/RBAC behavior.

Verification:
Run and report results:
- In `contracts-repo/packages/ceerat-contracts`:
  - proto generation command
  - `go test ./...`
  - `go build ./...`
- In `services-repo/services/ceerat-user-service`:
  - `go test ./...`
  - `go build ./...`
- In `apps-repo/ai/ceerat-agent-service`:
  - `go test ./...`
  - `go build ./...`
- Builder checks:
  - `ceerat-builder rbac check --output json`
  - `ceerat-builder check drift --output json`
  - `ceerat-builder check apps --output json`

Expected outcome:
- `ValidateToken` returns `valid=true` plus sanitized authenticated user.
- `ceerat-agent-service` no longer parses JWT payload locally to get `user.id`.
- Existing auth/session behavior remains backward compatible.
- Tests and builder checks pass.
```