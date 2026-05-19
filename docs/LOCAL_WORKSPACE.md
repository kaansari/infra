# Local Go Workspace

This platform is split across several sibling repositories/modules:

```text
infra/
apps-repo/
services-repo/
contracts-repo/
```

Go can build each module on its own, but local cross-repo development works best with a `go.work` file. The workspace tells Go to use the local sibling modules instead of trying to download those module paths from a remote source.

## Recommended Local Setup

From the shared parent directory:

```bash
cd /Users/kaansari/go/src/github.com/kaansari
```

Create or recreate the workspace:

```bash
go work init \
  ./contracts-repo/packages/ceerat-contracts \
  ./services-repo/services/ceerat-user-service \
  ./apps-repo/ai/ceerat-agent-service \
  ./apps-repo/ai/ceerat-chatgpt-client \
  ./apps-repo/apps/ceerat-admin-ui \
  ./apps-repo/apps/ceerat-web-ui \
  ./apps-repo/apps/ceerat-customer-ui
```

Then sync workspace module requirements:

```bash
go work sync
```

## If `go.work` Is Missing

Without `go.work`, Go may still build an individual module if its `go.mod` is complete and all dependencies are available remotely.

However, missing `go.work` can cause problems during local platform development:

- local sibling module changes may not be picked up;
- Go may try to download module paths instead of using local folders;
- builds can fail if a module path is not published or does not have the expected version;
- testing several apps/services together becomes more fragile.

## What To Commit

For this repo, keep `go.work.sum` out of git. It is a local workspace checksum file and can vary by developer/workspace state.

The `go.work` file is useful, but in this split-repo layout the best workspace file usually lives in the shared parent directory, which may not itself be a git repo. If a parent workspace repository is created later, commit the parent-level `go.work` there.

Until then, this document is the source of truth for recreating the local workspace.
