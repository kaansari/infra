# PR09 live acceptance execution plan

Binding spec: `requirement/pr/phase3/09-preference-live-acceptance.md`.

1. Inspect actual remote heads, Render deployment/configuration and database
   migration/preflight. Renew missing operator authentication without exposing
   credentials. Align canonical OAuth audience before an auto-deploying push.
   Deploy supported committed sources in dependency order and verify revisions.
2. Add a credential-free/read-only live preflight and exact per-client prompt
   runbook. Store only closed, validated redacted evidence. Require every matrix
   case from both fresh hosted versions, separate human-confirmation evidence
   for every write, operator preflight, and cleanup before freeze can pass.
3. Reconcile Keycloak and scope policy, refresh both hosted app versions and
   consent, run authenticated private RPC/schema/readiness checks, then operate
   the two-customer matrix with the human. Stop uncertain writes; reconcile only.
4. Synchronize durable builder ownership/privacy/prompt/confirmation/idempotency/
   deployment standards and inventories. Run builder gates and code checks.
5. Only after complete live evidence and cleanup: mark all slices complete and
   create the agreed milestone tag. Never substitute PR08 automated evidence
   or a fixture for either hosted-client run.

Current evidence: PR08 committed tuple 6961331/fddee2c/4cca58d passed 30 checks.
Render CLI reports expired authentication. App GitHub SSH access works.

Ruling: defer auto-deploying pushes until live configuration can be inspected;
gateway's canonical audience change must not launch against an incompatible
existing Render setting. Authentication is needed, not new task authorization.
Keep the established multi-repository checkout; preserve existing PR09 wording
and builder bytecode edits. No human live write confirmation has yet occurred.

## Execution ledger

- Added read-only live preflight, exact both-client prompts, closed operator
  evidence/schema, explicit 32-case inventory, human write/preview counts,
  consent/version/reconnection/cleanup gates. Private artifacts use mode 0600.
- Twelve Python regressions pass. RBAC/apps/drift/preference builder commands
  pass; durable builder standards updated without claiming live completion.
- Fresh review's error-code rejection and contradictory-outcome false positives
  reproduced (RED) and fixed (GREEN). Duplicate advertised tool names now fail
  preflight. No review code findings remain.
- Gateway requests timed out; Keycloak public discovery returned HTTP 200.
  Interpreter CA trust was corrected using the trusted system bundle, with TLS
  verification and credential-safe redirect rejection retained.
- Render authentication, hosted app versions/reconnections/human operation,
  controlled failures/TXSE approval and cleanup remain external prerequisites.
  No source push/deploy/live write/freeze/tag has occurred.
- Ruling: do not rewrite replay policy to make a live checklist green. Await
  explicit acceptance of a private-RPC companion proof or a revised public
  contract. Cost if unresolved: replay case and milestone remain open.
