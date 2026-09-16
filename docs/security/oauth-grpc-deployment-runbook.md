# OAuth/gRPC deployment runbook

This runbook defines ordering and gates. PR 01 does not authorize or perform a
live deployment.

## Required local gate

Before any runtime PR is pushed or deployed:

1. Start only disposable local PostgreSQL and Keycloak resources.
2. Verify `start-stack.sh` rejects a non-local `CEERAT_ENV` and any target whose
   value contains a Render hostname.
3. Reconcile the planned client and `ceerat-api` audience into local Keycloak.
4. Obtain a synthetic-user token with authorization code + PKCE; never use a
   password or client-credentials grant for an end user.
5. Call protected gRPC directly with Bearer metadata and verify audience,
   scope, RBAC, account status, and ownership positive and negative cases.
6. Use MCP with the same grant and verify the gateway forwards the original
   token to gRPC.
7. Correlate sanitized request/trace IDs across gateway and service logs.
8. Run contract, service, gateway, RBAC, SQL, and drift gates.

Run the PR 02 real-provider validator gate with a disposable synthetic local
client and user. The harness performs authorization code + PKCE, runs the Go
validator test without printing the token, and removes both temporary records:

```text
./verification/oauth-grpc/run-local-validator-acceptance.rb
```

Both the harness and Go test refuse a non-loopback issuer. The harness reads the
generated local Keycloak admin password file and never prints any credential,
authorization code, or token.

The local lifecycle must never accept the live issuer, a Render database host,
or a Render service URL. Live verification scripts remain separately named and
require explicit operator invocation.

## Deployment sequence

1. Freeze and review the contract scope inventory.
2. Reconcile the `ceerat-api` audience mapper and approved clients.
3. Deploy the shared OAuth validator without enabling an alternate token path.
4. Deploy issuer/subject identity resolution.
5. Enable direct gRPC enforcement.
6. Deploy MCP token pass-through.
7. Enable unified audit and alerting.
8. Remove superseded authentication RPCs, clients, secrets, and configuration.
9. Run read-only metadata checks, then bounded end-to-end acceptance.

Each release records commit IDs, configuration hashes, deployment IDs, and
sanitized PASS/FAIL evidence. Do not store tokens or secrets in evidence.

## Failure and rollback

Stop before the next step on any failed, skipped, or unknown local gate. After
deployment, roll back to a matched known-good application/configuration pair.
Do not restore the old CEERAT JWT validator, `x-auth-token`, password grants,
identity-exchange RPC, obsolete clients, or dual audience acceptance. If no
known-good canonical pair exists, keep the affected interface unavailable and
repair forward rather than weakening authentication.
