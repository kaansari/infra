# Render Admin Portal Deployment Specification

## Objective

Deploy `ceerat-admin-ui` as a free Render web service and configure the existing
Render Keycloak and private user service so `khalid.a.ansari@gmail.com` can sign
in as the initial administrator. A single deployment command must converge the
environment from source-controlled configuration.

## Architecture

The browser reaches the admin UI and Keycloak over Render-managed HTTPS. The
admin UI connects only to `ceerat-user-service:10000` on Render's private
network. The user service remains a private service and no public gRPC listener
is introduced.

Production gRPC uses TLS. A deployment-generated private CA signs a certificate
for `ceerat-user-service`. The user service receives the certificate and key as
Render secret files; the admin UI receives only the CA certificate. OAuth access
tokens are forwarded unchanged and the user service continues to enforce issuer,
audience, authorized-party, scope, active-account, admin-role, and RBAC checks.

## Reproducible entry point

`deploy/render/deploy-admin-portal.sh` is the supported operator interface. It
must be safe to rerun and must:

1. Check required commands, Render login, repository branches, and pushed
   commits before changing Render.
2. Validate `render.yaml` and verify that its admin-service values agree with
   the script's canonical names and URLs.
3. Generate the private CA and service certificate once under an ignored local
   state directory with mode `0700`; reuse them on later runs unless explicit
   rotation is requested.
4. Push the committed `render.yaml` change and rely on the linked Blueprint's
   automatic sync to create or reconcile the free admin web service. The script
   waits for the corresponding Blueprint sync and fails if the resource does
   not match the YAML. It never creates or structurally updates the service
   through `render services create/update`.
5. Install only secret values that cannot be committed to a Blueprint, then
   deploy the exact pushed revisions of the admin UI and user service.
6. Reconcile the Keycloak realm, admin OAuth client, six admin scopes, and the
   initial administrator through Keycloak's administrator API.
7. Generate an initial temporary password only when the administrator lacks a
   usable credential. Store it in a local mode `0600` file and require
   `UPDATE_PASSWORD` on first login. Never print it in logs or place it in
   Render environment variables. Delete the local temporary-password file as
   soon as the forced password change succeeds.
8. Bind the exact Keycloak issuer and subject to the Ceerat administrator seed,
   redeploy the user service, wait for health, and run smoke tests.

Lower-level scripts may be run independently for diagnosis, but normal setup
and repeat deployment require only the entry point above.

## OAuth and administrator policy

The Keycloak client is public, uses authorization code flow with PKCE S256, and
has the exact redirect URI
`https://ceerat-admin-ui.onrender.com/oauth/callback`. Direct access grants,
implicit flow, service accounts, wildcard redirects, and wildcard web origins
are disabled.

The initial identity is `khalid.a.ansari@gmail.com`. Keycloak marks the address
verified because the identity is created by an authenticated realm
administrator. Email equality never grants Ceerat access. The database binding
uses the exact issuer and Keycloak subject. Self-service password reset is
disabled; a Keycloak administrator performs credential recovery. The admin UI
server uses an explicit operation allowlist and rejects user creation and local
database-password reset paths even when a caller crafts a direct proxy request.
Credential administration is never delegated to the browser or the
`AdminService` compatibility password RPC.

The client receives the exact scopes in the canonical contract policy:
`ceerat.admin.read`, `ceerat.admin.users.read`,
`ceerat.admin.users.write`, `ceerat.admin.rbac.read`,
`ceerat.admin.rbac.write`, and `ceerat.admin.operations.write`. Consent and
scope handling must stay consistent with the local MCP and gRPC security model.

## Blueprint service

The repository-root `render.yaml` is the sole source of truth for Render
resource type, name, plan, repository, branch, root directory, build command,
start command, health check, region, deployment trigger, and non-secret
environment. It defines `ceerat-admin-ui` as a Go web service on plan `free`, in
the same region as the private service, rooted at `apps/ceerat-admin-ui`. It
uses the existing Render build and start scripts, `/healthz`, production mode,
the canonical issuer and callback URL, and the private user-service host/port.
Certificate values are not committed. The deployment script may write only
secret environment variables or secret files after Blueprint sync because
Render intentionally cannot populate new `sync: false` values on later syncs.
Secret values are transferred through files, standard input, or authenticated
API request bodies; they never appear in command-line arguments or process
listings.

## Failure and recovery

The deployment exits before mutations when authentication, source revisions,
Blueprint validation, or required secrets are invalid. Each mutation is
followed by verification. Rerunning repairs drift without creating duplicate
clients, users, credentials, or database administrators.

Certificate rotation is explicit and redeploys the user service before the
admin UI. A failed service deploy stops later identity changes. A failed smoke
test leaves diagnostics that identify the failed boundary without revealing
tokens or passwords.

## Verification

Automated checks cover Blueprint validation, shell syntax, idempotent Keycloak
reconciliation, TLS refusal for plaintext production gRPC, OAuth discovery,
admin-service health, an unauthenticated redirect, and an authenticated browser
flow smoke test. Security cases cover missing and invalid tokens, wrong issuer,
audience, client, and scope, inactive accounts, non-admin roles, RBAC denial and
allowance, crafted local-password/user-creation requests, CSRF rejection,
secure cookie attributes, safe errors, and secret-redacted logs. The
authenticated test uses a real Keycloak authorization-code/PKCE flow, verifies
the Users and RBAC pages, and performs a reversible role create/delete
operation. No token, code, PKCE verifier, cookie, password, or identity claim is
persisted in test evidence.

## Documentation

The admin UI README and Render runbook document the single deployment command,
credential retrieval, Keycloak-admin-only recovery, certificate rotation,
health checks, and rollback. Service documentation and inventories are updated
after implementation tests. Reusable rules are added to the existing builder
agent architecture, security/RBAC, and service-standard documents only after
live verification and human validation.

## Platform limits

The free admin web service can sleep after inactivity and has an ephemeral file
system. Durable state stays in PostgreSQL and Keycloak. The current free Render
PostgreSQL database reports expiration on 2026-09-30; the deployment script must
surface that condition prominently rather than claiming durable production
availability.
