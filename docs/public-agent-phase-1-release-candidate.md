# CEERAT public-agent Phase 1 release candidate

Status: **not released — human acceptance required**  
Prepared: 2026-09-03  
Proposed tag after acceptance: `v1.0.0`

## Frozen boundary

Phase 1 exposes exactly these nine vendor-neutral remote MCP tools:

```text
describe_ceerat
get_authentication_status
get_current_user
get_my_customer_profile
prepare_my_customer_profile_update
update_my_customer_profile
list_my_agent_connections
revoke_my_agent_connection
logout_current_connection
```

The public boundary is HTTPS MCP with user-delegated OAuth. Hosted ChatGPT uses
the confidential `ceerat-mcp-chatgpt` client with `client_secret_basic`; Codex
uses the public `ceerat-mcp-codex-dev` client. Both use authorization code with
PKCE `S256`. External bearer tokens terminate at the gateway. Private gRPC uses
gateway workload authentication and service-owned RBAC/ownership enforcement.

Native Keycloak registration requires verified email and provisions the
external-identity mapping, CEERAT user, and customer idempotently. Brevo SMTP is
configured on port 2525 with authentication and STARTTLS; implicit SSL is off.
Google and Apple login are not part of this release candidate.

## Compatibility and deprecation policy

- Tool names, input/output schemas, the `schema_version: "1.0"` envelope, error
  codes, required scopes, and confirmation behavior are frozen for Phase 1.
- Compatible additive changes may add optional response fields or new tools.
  Clients must ignore unknown response fields but must not send unknown input
  fields.
- Removing or renaming a tool/field, changing its meaning or required scope, or
  making an optional input required needs a versioned contract and migration
  window.
- Deprecated fields remain truthful and documented for at least one declared
  compatibility window. Security defects may be removed immediately with a
  release note and explicit client impact assessment.
- `ceerat-mcp-dev` is a rollback client, not a supported production client. It
  is disabled only after both dedicated clients and rollback recovery pass.
- The legacy `ceerat-agent-service` HTTP tool inventory is not the canonical
  public AI surface. New public AI operations extend the MCP gateway.

## Participating repository baseline

| Repository | Baseline commit | Role |
| --- | --- | --- |
| `infra` | `53e3ec9` | PR 08 Codex harness and redacted evidence |
| `apps-repo` | `af24b8b` | Gateway controls plus explicit legacy AI-surface deprecation |
| `services-repo` | `92a89d6` | Idempotent external identity provisioning and private gRPC enforcement |
| `contracts-repo` | `a20dcb4` | Identity exchange contracts and shared gRPC security |
| `ceerat-platform-builder-agent` | `6658b4c` | Reusable security standards and lifecycle-aware inventory validation |

These are the reviewed baseline revisions, not a declaration that the release
tag exists. The final infra freeze commit and tag must be recorded after human
acceptance.

## Codex evidence

`CEERAT_PR08_RUN_RATE_LIMIT=true make verify-phase1-live` passed eleven checks
with zero failures on 2026-09-03. The committed redacted result is
`verification/phase1/evidence/codex-2026-09-03.json`; the schema and operator
instructions are beside it. No credentials, OAuth codes, tokens, response
bodies, customer data, or database content are retained.

Contract/service drift and the aggregate platform gate pass. The legacy
`ceerat-agent-service` is explicitly deprecated in the app inventory and is no
longer treated as the canonical public tool surface. First-party formatting
checks exclude immutable vendored dependencies while tests, builds, vet, race,
coverage, and static analysis still run across the participating Go modules.

## Remaining release gates

The following remain `MANUAL_REQUIRED`:

1. authenticated Codex connection/read validation;
2. two-disposable-user ownership isolation;
3. A/B/C connection lifecycle and refresh validation;
4. logout followed by failed refresh/reconnect requirement;
5. verified-email, retry, concurrent provisioning, and datastore cardinality;
6. reversible profile prepare/confirm validation in supported clients;
7. Render audit-log correlation and secret-redaction inspection;
8. final ChatGPT discovery/authentication/read/write/logout acceptance.

Also exercise rollback without deleting clients or data: retain the prior
gateway deploy, keep `ceerat-mcp-dev` disabled rather than deleted after the
acceptance window, verify that the Keycloak reconciler can restore the reviewed
client policy, and prove a gateway rollback still rejects invalid tokens and
cross-user access.

The Render free-tier Keycloak service can cold-start slowly. During the final
Codex run, the first OAuth policy request timed out after 20 seconds; waking the
issuer discovery endpoint returned HTTP 200 and the complete policy suite then
passed. Deployment readiness and client UX must account for this hosting
behavior; it is not an OAuth-policy failure.

## Release procedure

1. Follow `verification/phase1/README.md` using disposable identities and add a
   credential-free final evidence document.
2. Run `make verify-platform`, the live acceptance harness, and repository
   cleanliness/push checks. Resolve active failures; do not waive them silently.
3. After human validation, update durable builder standards if the validated
   behavior differs from them and rerun builder drift/app checks.
4. Update this document with the final infra commit and acceptance result.
5. Create and push annotated tag `v1.0.0` with title `Phase 1 COMPLETE`.

Jobs, skills, applications, TXSE, social login, account deletion, REST APIs,
and Kubernetes remain outside this milestone.
