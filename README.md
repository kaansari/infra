# Infra: start/stop stack

This folder contains helper scripts to start a local development stack for Ceerat.

Files:
- `start-stack.sh` — waits for a Postgres instance (local by default) and launches services (user service, agent, web UI) using `go run` in the background. Logs are written to `logs/` and PIDs are stored in `pids`.
- `stop-stack.sh` — stops background processes recorded in `pids` and removes the Postgres Docker container if one was started by the script.

Usage:

Make the scripts executable:

```bash
chmod +x infra/start-stack.sh infra/stop-stack.sh
```

Start the stack (defaults can be overridden via environment variables). By default the script expects a local Postgres installation and will not start Docker.

To use the local DB (default):

```bash
infra/start-stack.sh
```

To explicitly start a Postgres Docker container instead set `USE_LOCAL_DB=false`:

```bash
USE_LOCAL_DB=false infra/start-stack.sh
```

Or customize env vars inline:

```bash
ROOT_DIR="/path/to/your/ceerat-workspace" DB_PASSWORD=secret infra/start-stack.sh
```

Stop the stack:

```bash
infra/stop-stack.sh
```

Notes:
- The scripts assume the workspace layout where `services-repo`, `apps-repo`, and `contracts-repo` are in the same parent directory.
- The scripts start processes with `go run .` — if you prefer built binaries, replace the `go run` lines in `start-stack.sh` with `go build` + `./binary` runs.
- You can edit `ROOT_DIR` environment variable if your repositories are in a different path.

## Optional Typesense Job Search

Imported ATS jobs remain stored in Postgres as the source of truth. Typesense is an optional derived search index owned by `ceerat-user-service`; the crawler and browser apps do not write to Typesense directly.

Start a local Typesense instance:

```bash
TYPESENSE_API_KEY=dev_typesense_key docker compose -f infra/docker-compose.typesense.yml up -d
```

Enable indexing/search when starting the stack:

```bash
TYPESENSE_HOST=localhost \
TYPESENSE_PORT=8108 \
TYPESENSE_PROTOCOL=http \
TYPESENSE_API_KEY=dev_typesense_key \
TYPESENSE_COLLECTION_JOBS=jobs \
infra/start-stack.sh
```

If any Typesense env var is missing, the user service logs job search as disabled and falls back to database-backed job search.

Indexing behavior:
- `career.JobService/ImportATSJobs` saves jobs to Postgres first.
- After a successful save/update, `ceerat-user-service` normalizes and upserts the saved job into Typesense.
- Typesense errors are logged and do not fail the import.

Rebuild the index from Postgres:

```bash
curl -X POST http://localhost:8081/api/admin/jobs/search-index/rebuild \
  -H "Authorization: Bearer $CEERAT_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"recreate":true}'
```

The rebuild response returns counts only: processed, succeeded, and failed.
