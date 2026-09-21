# Render Admin Portal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy and verify the Ceerat admin portal and its Keycloak administrator through one repeatable script while keeping gRPC private and TLS protected.

**Architecture:** A free public Render Go service handles browser traffic and OAuth PKCE. It calls the existing user service only at its Render private hostname using a deployment-managed private CA; Keycloak and the user service retain all identity and authorization enforcement.

**Tech Stack:** Bash, Render CLI and API, Render Blueprint YAML, Go, Keycloak `kcadm.sh`, OpenSSL, PostgreSQL, OAuth 2.0 authorization code with PKCE, gRPC TLS.

**Spec:** `docs/superpowers/specs/2026-09-18-render-admin-portal.md`

## Global Constraints

- Keep `ceerat-user-service` private; create no public gRPC endpoint.
- Treat repository-root `render.yaml` as the sole definition of every Render
  service property and every non-secret environment variable.
- Normal deployment and reconciliation use one command: `deploy/render/deploy-admin-portal.sh`.
- The OAuth client is public, requires PKCE S256, and accepts only the exact production callback.
- Initial admin identity is `khalid.a.ansari@gmail.com`; authorization binds exact issuer and subject, never email alone.
- Initial password is temporary, locally stored with mode `0600`, never logged, and recovery is Keycloak-admin-only.
- Delete the local temporary-password file immediately after the forced password change succeeds.
- Production gRPC must fail closed without TLS.
- No certificate, password, token, or Render credential is committed.
- The admin app server must deny user creation and local password reset; only a Keycloak administrator manages login credentials.

## Review Focus

- A rerun after partial failure converges without duplicate Keycloak users, OAuth clients, or database admins; covered in Task 3 tests.
- A local commit absent from the remote branch stops deployment before Render mutation; covered in Task 4 tests.
- Existing administrator credentials are preserved and a new temporary password is not silently issued; covered in Task 3 tests.
- Wrong TLS server name or CA prevents the admin UI from connecting; covered in Task 2 tests.
- Expiring or unavailable Render Postgres produces an explicit deployment warning or failure; covered in Task 4 tests.

---

### Task 1: Blueprint and admin service runtime

**Files:**
- Modify: `render.yaml`
- Modify: `../apps-repo/apps/ceerat-admin-ui/scripts/render-build.sh`
- Modify: `../apps-repo/apps/ceerat-admin-ui/scripts/render-start.sh`
- Modify: `../apps-repo/apps/ceerat-admin-ui/internal/server/server.go`
- Test: `../apps-repo/apps/ceerat-admin-ui/internal/server/oauth_test.go`

**Interfaces:**
- Consumes: existing `CEERAT_ADMIN_*`, OAuth issuer, and gRPC transport configuration.
- Produces: `GET /healthz` and Blueprint service `ceerat-admin-ui` at `https://ceerat-admin-ui.onrender.com`.

- [ ] Add failing handler tests asserting `GET /healthz` returns `200` without an authentication redirect, production cookies are `Secure`, `HttpOnly`, and `SameSite=Lax`, CSRF checks reject cross-site mutations, and crafted proxy requests for user creation or local password reset are denied.
- [ ] Run `go test ./internal/server` from `apps/ceerat-admin-ui` and confirm the health test fails.
- [ ] Add the health handler before authenticated routes and replace generic mutation dispatch with an explicit server-side allowlist that omits `CreateUser` and `ResetUserPassword`.
- [ ] Add the free Go web service to `render.yaml` with root `apps/ceerat-admin-ui`, existing build/start scripts, `/healthz`, production OAuth values, and private target `ceerat-user-service:10000`.
- [ ] Run `go test ./internal/server`, `bash -n scripts/render-build.sh scripts/render-start.sh`, and `render blueprints validate render.yaml`; require all to pass.
- [ ] Commit the app and infrastructure changes in their owning repositories.

### Task 2: Private gRPC certificate installation

**Files:**
- Modify: `../services-repo/services/ceerat-user-service/grpc_transport.go`
- Modify: `../services-repo/services/ceerat-user-service/grpc_transport_test.go`
- Modify: `../apps-repo/apps/ceerat-admin-ui/internal/apiclient/client.go`
- Modify: `../apps-repo/apps/ceerat-admin-ui/internal/apiclient/client_test.go`
- Create: `deploy/render/lib/tls.sh`
- Create: `deploy/render/tests/tls_test.sh`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: certificate files installed through Render secret-file configuration.
- Produces: `ensure_tls_material STATE_DIR`, server certificate SAN `ceerat-user-service`, and client CA trust file.

- [ ] Add tests proving production server startup rejects plaintext and invalid key pairs, and proving the admin client rejects a wrong CA or server name.
- [ ] Run the focused Go tests and confirm the new invalid-material cases fail.
- [ ] Implement strict TLS file validation while preserving TLS 1.3 and the private service name check.
- [ ] Write `tls_test.sh` to verify first-run generation, mode `0700`/`0600`, SAN contents, reuse on rerun, and explicit rotation.
- [ ] Implement `tls.sh` with OpenSSL commands using a 3072-bit CA key, a 2048-bit service key, SHA-256 signatures, SAN `DNS:ceerat-user-service`, and no secret output.
- [ ] Run the focused Go tests and `bash deploy/render/tests/tls_test.sh`; require all to pass.
- [ ] Commit service, app, and infrastructure changes in their owning repositories.

### Task 3: Idempotent live Keycloak and admin reconciliation

**Files:**
- Create: `deploy/render/keycloak/clients/ceerat-admin-ui.json`
- Create: `deploy/render/keycloak/client-scopes/ceerat.admin.users.read.json`
- Create: `deploy/render/keycloak/client-scopes/ceerat.admin.users.write.json`
- Create: `deploy/render/keycloak/client-scopes/ceerat.admin.read.json`
- Create: `deploy/render/keycloak/client-scopes/ceerat.admin.rbac.read.json`
- Create: `deploy/render/keycloak/client-scopes/ceerat.admin.rbac.write.json`
- Create: `deploy/render/keycloak/client-scopes/ceerat.admin.operations.write.json`
- Modify: `deploy/render/keycloak/reconcile-live-realm.sh`
- Create: `deploy/render/keycloak/reconcile-admin-user.sh`
- Modify: `deploy/render/keycloak/realm_config_test.rb`

**Interfaces:**
- Consumes: Keycloak administrator credentials and `CEERAT_INITIAL_ADMIN_EMAIL`.
- Produces: exact OAuth client, six scopes, and machine-readable `issuer`, `subject`, `email`, and `credential_created` fields without returning the password.

- [ ] Add fixture tests for exact redirect URI, PKCE S256, disabled implicit/direct/service-account grants, the six exact canonical scopes (`ceerat.admin.read`, `ceerat.admin.users.read/write`, `ceerat.admin.rbac.read/write`, `ceerat.admin.operations.write`), disabled reset-password policy, and rerun behavior.
- [ ] Add tests proving an existing credential is preserved and duplicate email/user creation is rejected.
- [ ] Run `ruby deploy/render/keycloak/realm_config_test.rb` and confirm the new cases fail.
- [ ] Add the client and scope definitions and extend `reconcile-live-realm.sh` to reconcile and assign them.
- [ ] Implement `reconcile-admin-user.sh`: locate by exact username/email, create only when absent, mark verified, generate a temporary credential only when required, add `UPDATE_PASSWORD`, write it to the supplied local file at `0600`, and emit only non-secret identity fields.
- [ ] Run the Ruby fixture tests and shell syntax checks; require all to pass.
- [ ] Commit the Keycloak reconciliation changes.

### Task 4: One-command Blueprint convergence

**Files:**
- Create: `deploy/render/deploy-admin-portal.sh`
- Create: `deploy/render/lib/render.sh`
- Create: `deploy/render/tests/deploy_admin_portal_test.sh`
- Modify: `render.yaml`

**Interfaces:**
- Consumes: authenticated Render CLI, pushed `main` revisions, TLS helpers, and Keycloak reconciler.
- Produces: a successfully synced `render.yaml` Blueprint plus local `.run/render-admin/initial-password` and `deployment.json` with mode `0600`.

- [ ] Build a fake Render/API test harness covering Blueprint auto-sync discovery, missing Blueprint linkage, failed sync, partial rerun, unpushed commit rejection, secret redaction, and expiring database reporting.
- [ ] Run `bash deploy/render/tests/deploy_admin_portal_test.sh` and confirm it fails because the entry point is absent.
- [ ] Implement Blueprint lookup, require `path=render.yaml` and auto-sync enabled, push the validated committed YAML revision, wait for its Blueprint sync, assert the resulting service matches every non-secret YAML field, install only secret files/values, and poll health with bounded timeouts.
- [ ] Add a guard that fails if the script invokes `render services create`, `render services update`, or the service-update API for a Blueprint-managed property.
- [ ] Install secrets only through local `0600` files, standard input, or authenticated API request bodies; add a harness assertion that no secret is placed in command arguments, shell tracing, process listings, or retained output.
- [ ] Invoke Keycloak reconciliation through a non-logging administrative execution path, capture its identity output, set the user-service seed binding, deploy the user service, then deploy the admin UI.
- [ ] Make `--check`, `--rotate-tls`, and `--skip-browser-smoke` explicit flags; default reruns must reuse credentials and certificates and must trigger service changes only through a `render.yaml` Blueprint sync.
- [ ] Run the deployment harness, `shellcheck` when installed, `bash -n`, and Blueprint validation; require all to pass.
- [ ] Commit the deployment entry point and tests.

### Task 5: Live smoke test and rollback evidence

**Files:**
- Create: `deploy/render/smoke-admin-portal.sh`
- Create: `deploy/render/tests/smoke_admin_portal_test.sh`
- Modify: `deploy/render/deploy-admin-portal.sh`

**Interfaces:**
- Consumes: deployed URLs, temporary administrator credential file, and Keycloak OAuth endpoints.
- Produces: redacted smoke-test report and nonzero status on any security or functional failure.

- [ ] Add fixture tests for discovery failure, bad redirect, missing token, invalid token, wrong issuer/audience/client, missing admin scope, inactive account, non-admin role, RBAC denial, RBAC allowance, crafted create-user/password-reset denial, CSRF denial, secure cookie attributes, sanitized public errors, redacted logs, successful Users/RBAC loads, and reversible role create/delete cleanup. Mark ownership and AI-tool cases not applicable because these cross-user admin RPCs accept intentional selectors and no AI tool is involved.
- [ ] Implement HTTP/OAuth checks and a Playwright browser path if an installed browser is available; otherwise stop with a precise manual-browser verification requirement rather than claiming full success.
- [ ] Ensure logs and retained evidence redact authorization headers, cookies, codes, PKCE verifiers, tokens, passwords, and identity claims.
- [ ] Run fixture tests, then run the live entry point and retain deploy IDs and health results in the local report.
- [ ] Complete first login, change the temporary password, delete the local temporary-password file, verify Users and RBAC, and confirm the role mutation is deleted.
- [ ] Record rollback commands for each deployed exact commit and verify the previous Render deploy remains available.

### Task 6: Operator and builder-agent documentation

**Files:**
- Modify: `deploy/render/README.md`
- Modify: `../apps-repo/apps/ceerat-admin-ui/README.md`
- Modify: `../services-repo/services/ceerat-user-service/RENDER_DEPLOY.md`
- Modify: `../services-repo/services/ceerat-user-service/docs/grpc-security.md`
- Modify: `../ceerat-platform-builder-agent/README.md`
- Modify after human validation: `../ceerat-platform-builder-agent/.ceerat-agent/architecture.md`
- Modify after human validation: `../ceerat-platform-builder-agent/.ceerat-agent/security-rbac-standard.md`
- Modify after human validation: `../ceerat-platform-builder-agent/.ceerat-agent/service-standards.md`

**Interfaces:**
- Consumes: verified command names, paths, Render URLs, recovery behavior, and live smoke evidence.
- Produces: one-command deployment, recovery, rotation, diagnosis, and rollback guidance.

- [ ] Document `./deploy/render/deploy-admin-portal.sh` as the normal setup and redeploy path, including prerequisites and the local temporary-password path.
- [ ] Document Keycloak-admin-only recovery, exact subject binding, certificate rotation, free-service wake behavior, and PostgreSQL expiration risk.
- [ ] Update service docs and inventories after implementation tests, then add only reusable private-gRPC/TLS, OAuth-client, and idempotent-reconciliation rules to the existing builder standards after live checks and human validation.
- [ ] Run repository link/path checks and search docs for obsolete public-gRPC or multi-step setup instructions; correct any conflicts.
- [ ] Commit documentation in each owning repository.

### Task 7: Final verification and deployment record

**Files:**
- Modify: `docs/superpowers/plans/2026-09-18-render-admin-portal.md`

**Interfaces:**
- Consumes: all task test suites and live deployment report.
- Produces: checked task list and exact verification evidence.

- [ ] Run all affected Go tests in admin UI and user service, Keycloak fixture tests, deployment shell tests, shell syntax checks, `render blueprints validate render.yaml`, builder `check-context`, `rbac check`, `check drift`, and `check apps`.
- [ ] Run the canonical `make verify-platform` gate from `infra`; require it to pass before live deployment.
- [ ] Run `git diff --check` and inspect every repository's status and pushed revision.
- [ ] Run the one-command deployment a second time to prove convergence and confirm no password or certificate rotation occurred.
- [ ] Run the live smoke suite and confirm private gRPC, OAuth login, Users, RBAC, and reversible role mutation.
- [ ] Mark completed plan items and record deploy IDs, commit SHAs, URLs, and redacted test outcomes without committing secrets.
