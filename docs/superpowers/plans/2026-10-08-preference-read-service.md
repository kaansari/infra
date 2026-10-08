# Preference read service implementation plan

> **For agentic workers:** Use superpowers:executing-plans inline; request one fresh review at completion.

**Goal:** Implement PR04's four private preference read RPCs in the existing user service.
**Architecture:** Read-only repeatable-read transactions resolve authenticated customer ownership, profile version and bounded queries together. AES-GCM opaque cursors bind method, pseudonymous subject, normalized filters, resource/catalog versions and expiry. Static reviewed templates supply guidance; summaries contain counts and fixed precedence/control text only.
**Tech stack:** Existing Go, GORM/pgx, protobuf/gRPC, slog, PostgreSQL and Go standard-library crypto; no new dependency.
**Spec:** `requirement/pr/phase3/04-preference-read-service.md`.

## Constraints and decisions

- No ownership selectors, writes, inference, dereferencing, tools, REST or production deployment.
- Resolve customer in each authenticated read; missing and foreign preference IDs share NOT_FOUND.
- 2-second server deadline, page size default 25/max100, context limit1–100; probe one extra row and cap protobuf responses at128KiB.
- Repeatable-read/read-only transactions; absent profile reads version1 without inserting anything.
- Cursor validity15minutes; stale profile/catalog snapshots return ABORTED rather than inconsistent pages. Matching preference-row and enabled definition digests detect direct SQL changes too; aggregate results are bounded and subject to deadline.
- Key must be32 bytes; production requires base64 `CEERAT_PREFERENCE_PAGE_TOKEN_KEY`; development may generate a process key. Never log token/key/query/body.
- SQL filters are parameterized literal case-insensitive key/display-name searches (definition description also searchable). Category sets canonicalized for token binding.
- Context sorts scope entity/context/global, then category/key/scope references/ID. Retain all matches/conflicts; no winner resolution. Custom data has no executable guidance. TXSE consumes only five reviewed definitions and allowed options/references.
- Consumer context is definition-domain bound; custom rows may participate for non-TXSE consumers only. Disabled linked definitions do not erase stored snapshots.
- Preserve interceptor chain and instrument only safe counts/categories, profile version, correlation, pseudonymous actor/status/latency.

## Tasks

- [x] Write failing real-PostgreSQL tests: identity/ownership, projections, filters/cursors, context ordering/summary/authority, empty state and safe errors.
- [x] Implement read snapshots/query filters in `preferences/read_repository.go`; share typed projections in `row_validation.go`/`projection.go`.
- [x] Implement encrypted cursor codec in `preferences/pagination.go`; expiry/subject/filter/version tampering tests.
- [x] Implement four handlers and reviewed context templates in `preferences/handler.go`/`context.go`; enforce response validation and deadline/error redaction.
- [x] Add real gRPC authentication/RBAC tests, logging-redaction tests and cancellation/dependency tests.
- [x] Register service in `main.go`, preserve nine-method inventory with four implemented/five planned, document key/deployment prerequisites.
- [x] Run PG-backed full tests/race/build and builder contract/service, RBAC and drift gates; independent review and fix findings.
- [x] Record acceptance and commit only scoped verified changes. Hosted deployment remains gated on live preflight/authenticated smoke.
