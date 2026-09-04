# Phase 1 live security acceptance

Run the credential-free Codex portion against the deployed development stack:

```bash
make verify-phase1-live
```

The harness writes a mode-0600, redacted result to
`.verification/pr08-codex.json`. That directory is gitignored. It records only
check names, status, safe evidence descriptions, timestamps, and the public
target origin. It never writes bearer tokens, refresh tokens, OAuth client
secrets, passwords, cookies, database URLs, or response bodies.

To exercise the live authentication-failure limiter from one stable source IP,
wait for the current one-minute bucket to reset and run:

```bash
CEERAT_PR08_RUN_RATE_LIMIT=true make verify-phase1-live
```

This sends eleven unauthenticated `get_current_user` calls. The first ten must
return `UNAUTHENTICATED`; the eleventh must return `RATE_LIMITED`. It neither
authenticates nor changes CEERAT data.

## Interactive completion

Use disposable verified CEERAT accounts and do not paste credentials or tokens
into evidence. Record only PASS/FAIL, UTC time, request IDs, error codes, and
opaque identifiers created for the test.

### Codex

1. Connect User A and verify authentication status, current user, own profile,
   and current connections.
2. Prepare a harmless reversible profile change, inspect the preview, confirm
   it once, then prove replay fails. Restore the original value through a new
   prepare/confirm operation.
3. With disposable connections A, B, and C for the same test account, revoke B.
   Verify A and C continue and B must reconnect. Then logout a disposable
   current connection and prove it must reconnect.
4. Use separate disposable Users A and B. Prove A cannot consume B's
   preparation or revoke B's opaque connection ID, and that neither public tool
   accepts a user/customer selector.

### ChatGPT

Repeat the authenticated reads, reversible prepare/confirm/replay check, one
non-current connection revocation, refresh after the short access-token
lifetime, and current-connection logout. Confirm consequential actions display
an approval prompt and logout requires reconnecting the CEERAT app.

### Operator-only checks

1. Create an unverified disposable Keycloak user and confirm CEERAT denies it.
   Verify the email, reconnect twice concurrently, and confirm exactly one user,
   customer, and external-identity mapping exists.
2. Match rate-limit and destructive-operation request IDs in Render logs.
   Confirm audit fields are present and no authorization header, cookie, token,
   password, SMTP/API secret, database URL, or workload credential appears.
3. Delete only identities, mappings, connections, and preparations created for
   this acceptance run.

PR 08 remains partial until every `MANUAL_REQUIRED` check is replaced with
redacted PASS evidence from both Codex and ChatGPT where applicable.
