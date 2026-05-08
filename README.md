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
ROOT_DIR=/Users/kaansari/go/src/github.com/kaansari DB_PASSWORD=secret infra/start-stack.sh
```

Stop the stack:

```bash
infra/stop-stack.sh
```

Notes:
- The scripts assume the workspace layout where `services-repo`, `apps-repo`, and `contracts-repo` are in the same parent directory.
- The scripts start processes with `go run .` — if you prefer built binaries, replace the `go run` lines in `start-stack.sh` with `go build` + `./binary` runs.
- You can edit `ROOT_DIR` environment variable if your repositories are in a different path.
