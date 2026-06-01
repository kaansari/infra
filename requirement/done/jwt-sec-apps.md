Use this prompt with Codex:

```md
Use the builder agent for consistency and architecture integrity before making any code changes.

Task:
Upgrade all app clients to align with the new auth/session security model where `auth.Auth/ValidateToken` returns the sanitized authenticated user directly. App clients must stop locally decoding JWT payloads after validation.

Context:
The auth contract was updated so `auth.Token` includes:

- `token = 1`
- `valid = 2`
- `errors = 3`
- `user = 4`

`ceerat-user-service` `ValidateToken` now cryptographically validates the JWT, loads the current user from the DB, rejects inactive/pending/blocked users, and returns the sanitized current user when valid.

`ceerat-agent-service` has already been updated so `ValidateSession` uses `resp.GetUser().GetId()` instead of locally parsing JWT payloads.

Now upgrade the remaining app clients in `apps-repo`, including:
- `apps-repo/apps/ceerat-web-ui`
- `apps-repo/apps/ceerat-customer-ui`
- `apps-repo/apps/ceerat-admin-ui`
- `apps-repo/ai/ceerat-agent-service`
- `apps-repo/ai/ceerat-chatgpt-client`
- any ChatGPT assistant/client application found under `apps-repo/ai` or `apps-repo/apps`

Required builder-agent workflow:
1. Run builder discovery first:
   - `ceerat-builder codex-context --output json`
   - `ceerat-builder docs all --output json`
   - `ceerat-builder inventory contracts --output json`
   - `ceerat-builder inventory services --output json`
   - `ceerat-builder inventory apps --output json`
   - `ceerat-builder evidence request "upgrade all app clients to use ValidateToken returned user and stop local JWT payload parsing" --output json`
   - `ceerat-builder patterns apps --output json`
   - `ceerat-builder patterns service --output json`
   - `ceerat-builder patterns grpc-security --output json`
   - `ceerat-builder patterns testing --output json`
   - `ceerat-builder rbac check --output json`
   - `ceerat-builder check drift --output json`
2. Use builder output as factual context, not final design.
3. Preserve existing app ownership and UX behavior.
4. Do not create a new auth boundary or new service.

Implementation requirements:
1. Search all app code for local JWT payload parsing helpers, including names like:
   - `userFromToken`
   - `userIDFromJWT`
   - `userFromJWT`
   - `base64.RawURLEncoding`
   - JWT payload JSON parsing
   - manual extraction of `user.id`, `role`, `email`, `status` from token payload
2. For every app session validation flow that already calls `auth.Auth/ValidateToken`:
   - use `resp.GetUser()` / `token.GetUser()` from the validated response
   - reject when `valid != true`
   - reject when returned `user.id` is empty
   - keep current session structs and cookies unless there is a strong existing pattern requiring otherwise
3. Remove local JWT decoding helpers when no longer used.
4. Remove now-unused imports such as:
   - `encoding/base64`
   - `encoding/json`
5. Preserve current behavior:
   - login still works
   - session restore still works
   - logout still works
   - role-based UI behavior still works
   - customer/admin/agent route guards still work
6. Do not trust browser-supplied or model-supplied user ids.
7. Do not decode JWT payloads locally after `ValidateToken`.
8. Do not return or expose password/token secrets in UI session objects.
9. If an app needs more user fields than `ValidateToken.user` returns, use the sanitized returned user first and only call `GetUser`/`Get` when the app already had that behavior or needs fresh expanded profile fields.
10. Update tests where present:
    - valid session uses `ValidateToken.user`
    - missing returned user id is rejected
    - invalid token remains rejected
    - existing role/customer/admin checks remain covered
11. Update docs/inventories if they describe app session validation or local JWT parsing.

Security requirements:
1. `ValidateToken` remains public only according to existing allowlist.
2. Do not weaken JWT/RBAC behavior.
3. Do not add unauthenticated shortcuts.
4. Do not parse claims locally as a substitute for auth-service validation.
5. App identity must come from auth service validated response, not request params, local storage, model text, or decoded-but-unverified JWT content.

Verification:
Run and report results for every changed app package.

At minimum run:
- In `apps-repo/apps/ceerat-web-ui`:
  - `go test ./...`
  - `go build ./...`
- In `apps-repo/apps/ceerat-customer-ui`:
  - `go test ./...`
  - `go build ./...`
- In `apps-repo/apps/ceerat-admin-ui`:
  - `go test ./...`
  - `go build ./...`
- In `apps-repo/ai/ceerat-agent-service`:
  - `go test ./...`
  - `go build ./...`
- In `apps-repo/ai/ceerat-chatgpt-client` or any discovered ChatGPT assistant/client app:
  - repo/package normal test command
  - repo/package normal build command

Also run:
- `ceerat-builder rbac check --output json`
- `ceerat-builder check drift --output json`
- `ceerat-builder check apps --output json`

Expected outcome:
- No app client locally decodes JWT payloads to derive authenticated user identity after `ValidateToken`.
- Apps use the sanitized current user returned by `auth.Auth/ValidateToken`.
- Existing login/session/role behavior remains backward compatible.
- Tests/builds and builder checks pass.
```