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
cd /path/to/your/ceerat-workspace
```

Create or recreate the workspace:

```bash
go work init \
  ./contracts-repo/packages/ceerat-contracts \
  ./services-repo/services/ceerat-user-service \
  ./apps-repo/ai/ceerat-agent-service \
  ./apps-repo/apps/ceerat-admin-ui \
  ./apps-repo/apps/ceerat-web-ui \
  ./apps-repo/apps/ceerat-customer-ui \
  ./atscrawler
```

Then sync workspace module requirements:

```bash
go work sync
```

## Docker Prerequisites

The stack uses Docker for running Typesense (search service). Ensure you have:

- Docker installed and running
- Docker Compose installed

On macOS with Homebrew:
```bash
brew install docker-compose
```

## Typesense Configuration

Typesense is used for search functionality across the platform. It runs in a Docker container managed by `docker-compose.typesense.yml`.

### Configuration

Environment variables are configured in `infra/typesense.env`:

```bash
TYPESENSE_HOST=localhost          # Typesense host (for clients)
TYPESENSE_PORT=8108               # Typesense port
TYPESENSE_PROTOCOL=http           # Protocol (http/https)
TYPESENSE_API_KEY=dev_typesense_key  # API key for authentication
TYPESENSE_COLLECTION_JOBS=jobs    # Name of jobs collection
TYPESENSE_COLLECTION_PRODUCTS=products # Name of products collection
TYPESENSE_DISABLED=false          # Set to true to disable Typesense
```

### Starting the Stack

From the `infra` directory:

```bash
make start-stack
```

This will:
1. Start Typesense in Docker (port 8108)
2. Start PostgreSQL (port 55434)
3. Build and start all services (user service, agent service, web UI, admin UI, customer UI)

Typesense is started before the user service since the service depends on it for job search functionality.

### Checking Status

```bash
make status-stack
```

You should see Typesense listed as running on port 8108:
```
Typesense         running  port=8108  http://localhost:8108
```

### Accessing Typesense

- **API Endpoint**: `http://localhost:8108`
- **Documentation**: [Typesense API Docs](https://typesense.org/docs/api/)
- **API Key**: `dev_typesense_key` (from `typesense.env`)

### Stopping the Stack

```bash
make stop-stack
```

This will stop all services including the Typesense Docker container and PostgreSQL.

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
