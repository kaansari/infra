# Go workspace documentation with pkgsite

Use this guide from the directory containing the sibling `infra`,
`contracts-repo`, `services-repo`, and `apps-repo` checkouts. Go package comments
and exported declarations are the API reference; READMEs explain operation,
and architecture documents explain component responsibilities and trust boundaries.
The Python builder agent consumes Markdown standards and is not a Go module.

## Create or extend the workspace

For a new workspace with no `go.work`, start with the canonical contracts and
backend service:

```bash
go work init \
  contracts-repo/packages/ceerat-contracts \
  services-repo/services/ceerat-user-service
```

If `go.work` already exists, do not run `go work init` again or overwrite it.
Add the complete documentation module set with `go work use`; this also preserves
unrelated workspace modules:

```bash
go work use \
  contracts-repo/packages/ceerat-contracts \
  services-repo/services/ceerat-user-service \
  apps-repo/ai/ceerat-agent-gateway \
  apps-repo/ai/ceerat-agent-service \
  apps-repo/apps/ceerat-admin-ui \
  apps-repo/apps/ceerat-customer-ui \
  apps-repo/apps/ceerat-web-ui
```

Use only `contracts-repo/packages/ceerat-contracts` as the workspace contracts
module. `apps-repo/packages/ceerat-contracts` is a deployment copy with the same
module path; including both makes Go reject duplicate workspace modules.
If Go reports conflicting module-level replacements, make the canonical source
explicit in the workspace:

```bash
go work edit -replace=github.com/kaansari/ceerat-contracts@v0.0.0=./contracts-repo/packages/ceerat-contracts
```

Check the effective workspace and its modules:

```bash
go env GOWORK
go list -m
```

Use the Go version required by the checked-in `go.mod` files (currently 1.26.2
for these modules). `GOWORK=off` disables this workflow. Keep the parent workspace
local: standalone Render builds use each module's deployment configuration and
vendored dependencies, not your parent `go.work`.

## Install and run pkgsite

```bash
go install golang.org/x/pkgsite/cmd/pkgsite@latest
pkgsite -http=127.0.0.1:8080
```

Open <http://127.0.0.1:8080>. Run `pkgsite` from the workspace parent so it finds
all modules. If local Keycloak occupies port 8080, use:

```bash
pkgsite -http=127.0.0.1:6060
```

If your shell cannot find `pkgsite`, locate it with `go env GOBIN GOPATH`: Go
installs into `GOBIN` when set, otherwise the first GOPATH directory's `bin`.
Add that directory to PATH or invoke the installed binary by its full path.
Initial installation and module loading can require network access. The tool
serves local documentation; it does not deploy services or publish to pkg.go.dev.
A private repository may have restricted source/license display; use `pkgsite
-help` for local serving options and `go doc` for a direct source reference.

## Module navigation

The URL uses the declared Go module path, which does not always match the
current repository name. Append these paths to the local server URL:

| Component | Module path |
| --- | --- |
| `ceerat-contracts` | `github.com/kaansari/ceerat-contracts` |
| `ceerat-user-service` | `github.com/kaansari/ceerat-platform/services/ceerat-user-service` |
| `ceerat-agent-gateway` | `github.com/kaansari/ceerat-platform/ai/ceerat-agent-gateway` |
| `ceerat-agent-service` | `github.com/kaansari/ceerat-platform/ai/ceerat-agent-service` |
| `ceerat-admin-ui` | `github.com/kaansari/apps-repo/apps/ceerat-admin-ui` |
| `ceerat-customer-ui` | `github.com/kaansari/apps-repo/apps/ceerat-customer-ui` |
| `ceerat-web-ui` | `github.com/kaansari/ceerat-platform/apps/ceerat-web-ui` |

Start with each command's overview, then navigate its `internal/config`,
`internal/apiclient`, and `internal/server` packages where present. For backend
behavior, inspect domain handlers and repositories; for the gateway, inspect
its tool policies and gRPC adapter. Generated protobuf declarations describe
the wire API, while `domain`, `mapper`, and `security` explain shared ownership.

## Editing and verifying documentation

Write package overviews in `doc.go` and declaration comments beside the source
symbol. Keep generated protobuf files untouched; update their proto source and
regenerate when contract comments change. Preserve operational examples and
security constraints in the relevant module README rather than copying API
signatures into Markdown. Pkgsite does not turn unrelated architecture Markdown
into package documentation automatically; link both references from READMEs.

After editing, restart pkgsite if needed, open every affected module, and check
that the rendered overview and source links match the checkout. Use `go doc`
from the module directory to verify comments without starting the platform:

```bash
cd apps-repo/ai/ceerat-agent-gateway
go doc .
go list ./...
```

## Architecture and operations

- [Apps and gateway architecture](../../apps-repo/docs/architecture.md)
- [Backend platform architecture](../../services-repo/services/ceerat-user-service/docs/architecture.md)
- [Render deployment and readiness](../deploy/render/README.md)
- [Builder architecture rules](../../ceerat-platform-builder-agent/.ceerat-agent/architecture.md)
- [Builder security rules](../../ceerat-platform-builder-agent/.ceerat-agent/security-rbac-standard.md)

References: [pkgsite command](https://pkg.go.dev/golang.org/x/pkgsite/cmd/pkgsite),
[Go workspace tutorial](https://go.dev/doc/tutorial/workspaces).
