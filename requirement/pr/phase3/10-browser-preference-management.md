# Human preference management extension

Requested 2026-10-21: expose a human form experience at
`http://localhost:3005/preferences`, independent of MCP tools and gateway paths.
This explicitly extends the original Phase 3 browser exclusion for this customer
UI adapter only; the Phase 3 MCP acceptance/freeze requirements remain separate.

## Architecture and ownership

```text
Customer browser + HttpOnly OAuth session cookie
 -> ceerat-customer-ui same-origin JSON adapter
 -> existing private preference.PreferenceService with original OAuth token
 -> OAuth / identity / scope / RBAC / account status / customer ownership
 -> existing ceerat-user-service preference module -> existing PostgreSQL
```

Reuse the existing catalog, closed typed contract, validation, and storage.
No browser-to-gRPC/database access, new deployment, public generic API, duplicate
preference domain, arbitrary RPC selector, or MCP gateway dependency is added.

## User experience

Keep profile/address editing. Add a responsive saved-preference list and editor:
choose a catalog definition, supported qualitative level, typed value, supported
scope, and enabled state. Catalog labels/descriptions are server-owned. Updating
locks logical identity; retargeting requires removal and a separately reviewed
create. Canonical creation uses definition ID only, not caller-owned metadata.
Existing custom and disabled-definition records remain visible/removable; their
write policy is not expanded through a guessed browser catalog.

Review displays complete normalized before/after (or removal target), scope,
enabled state, domain warnings, and expiry. Explicit confirmation sends the
original versions, fingerprint, and idempotency key. Removal explains retention.

## Browser security and recovery

- Require an active customer OAuth session and forward its original access token.
- Domain gRPC independently checks read/write scopes, role, status, ownership.
- Closed operation allowlist; bounded strict protobuf JSON decoding and contract
  validation reject unknown identity/authority fields and malformed values.
- Require JSON and a non-simple custom request header, same-origin checks, and
  reject cross-site fetch metadata. Do not enable cross-origin access.
- POST bodies keep page tokens and operation keys out of URLs. No content/body
  activity logs, safe static error messages, no-store responses, and escaped
  DOM text presentation. Preference-route query strings are excluded from logs.
- Keep preview data in memory. Retain only kind/key in per-account tab session
  storage before dispatch so a reload can reconcile an uncertain confirmation.
- Pending/unknown never means failed and never permits automatic mutation retry.
  Status reads use the original operation kind/key. The service remains the
  authority for idempotency and transactional updates.
- Session-storage removal/unavailability and independently opened tabs cannot be
  treated as evidence that an earlier operation failed. Cross-tab durable browser
  review coordination is outside this bounded release.

## Verification and limits

Use ceerat-builder context, app context, evidence, gRPC-security patterns, RBAC,
app inventory and contract drift checks. Test strict request/auth/origin gates,
original-token forwarding, closed method selection, unknown outcome handling,
redaction, and browser preview/create/edit/delete/recovery with responsive layout.
Run customer UI tests/build and update app/browser-gRPC inventories together.
Fixture browser tests are not live OAuth/database acceptance. Do not mark Phase 3
ChatGPT/Codex human acceptance complete based on this browser extension.
