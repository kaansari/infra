#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

start_detached() {
  local log_file="$1"
  local pid_file="$2"
  shift 2

  nohup perl -MPOSIX=setsid -e 'setsid(); exec @ARGV or die "exec failed: $!\n"' "$@" </dev/null >>"$log_file" 2>&1 &
  echo $! >"$pid_file"
}

ensure_postgres() {
  if [[ ! -x "$PG_CTL" || ! -x "$INITDB" || ! -x "$PSQL" ]]; then
    echo "PostgreSQL 14 tools were not found under /usr/local/opt/postgresql@14/bin." >&2
    echo "Install PostgreSQL first or set PG_CTL, INITDB, and PSQL." >&2
    exit 1
  fi

  if [[ ! -d "$CEERAT_PGDATA" ]]; then
    echo "Initializing Postgres data directory: $CEERAT_PGDATA"
    env LANG=C LC_ALL=C "$INITDB" -D "$CEERAT_PGDATA" -U "$CEERAT_DB_USER" -A trust -E UTF8 --locale=C
  fi

  if is_port_listening "$CEERAT_DB_PORT"; then
    echo "Postgres already listening on $CEERAT_DB_HOST:$CEERAT_DB_PORT"
    return
  fi

  echo "Starting Postgres on $CEERAT_DB_HOST:$CEERAT_DB_PORT"
  env LANG=C LC_ALL=C "$PG_CTL" \
    -D "$CEERAT_PGDATA" \
    -l "$POSTGRES_LOG" \
    -o "-p $CEERAT_DB_PORT" \
    start

  PGPASSWORD="$CEERAT_DB_PASSWORD" "$PSQL" \
    -h "$CEERAT_DB_HOST" \
    -p "$CEERAT_DB_PORT" \
    -U "$CEERAT_DB_USER" \
    -d "$CEERAT_DB_NAME" \
    -c "ALTER USER $CEERAT_DB_USER PASSWORD '$CEERAT_DB_PASSWORD';" >/dev/null
}

start_typesense() {
  if [[ "${TYPESENSE_DISABLED:-}" == "true" ]]; then
    echo "Typesense is disabled"
    return
  fi

  if is_port_listening "8108"; then
    echo "Typesense already listening on localhost:8108"
    return
  fi

  echo "Starting Typesense container"
  cd "$ROOT_DIR/infra"
  if command -v docker-compose >/dev/null 2>&1; then
    docker-compose -f docker-compose.typesense.yml up -d
  elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if docker compose version >/dev/null 2>&1; then
      docker compose -f docker-compose.typesense.yml up -d
    elif docker container inspect ceerat-typesense >/dev/null 2>&1; then
      docker start ceerat-typesense >/dev/null
    else
      docker run -d \
        --name ceerat-typesense \
        -p 8108:8108 \
        -v ceerat-typesense-data:/data \
        typesense/typesense:29.0 \
        --data-dir /data \
        --api-key="${TYPESENSE_API_KEY:-dev_typesense_key}" \
        --enable-cors >/dev/null
    fi
  else
    echo "Docker is not running or not reachable; Typesense startup skipped"
    echo "Start Docker/Colima, install Docker Compose, or set TYPESENSE_DISABLED=true to silence this message."
    return
  fi
  sleep 2
}

start_user_service() {
  if is_port_listening "$CEERAT_SERVICE_PORT"; then
    echo "User service already listening on localhost:$CEERAT_SERVICE_PORT"
    return
  fi

  echo "Starting user service on localhost:$CEERAT_SERVICE_PORT"
  cd "$ROOT_DIR"
  start_detached "$SERVICE_LOG" "$SERVICE_PID" env \
    PORT="$CEERAT_SERVICE_PORT" \
    DB_HOST="$CEERAT_DB_HOST" \
    DB_PORT="$CEERAT_DB_PORT" \
    DB_USER="$CEERAT_DB_USER" \
    DB_PASSWORD="$CEERAT_DB_PASSWORD" \
    DB_NAME="$CEERAT_DB_NAME" \
    JWT_SECRET="$CEERAT_JWT_SECRET" \
    JWT_AUTH_ENABLED="$JWT_AUTH_ENABLED" \
    CEERAT_USER_ADMIN_PORT="$CEERAT_USER_ADMIN_PORT" \
    CEERAT_ENV="$CEERAT_ENV" \
    TYPESENSE_HOST="${TYPESENSE_HOST:-}" \
    TYPESENSE_PORT="${TYPESENSE_PORT:-}" \
    TYPESENSE_PROTOCOL="${TYPESENSE_PROTOCOL:-http}" \
    TYPESENSE_API_KEY="${TYPESENSE_API_KEY:-}" \
    TYPESENSE_COLLECTION_JOBS="${TYPESENSE_COLLECTION_JOBS:-jobs}" \
    TYPESENSE_DISABLED="${TYPESENSE_DISABLED:-}" \
    "$BIN_DIR/ceerat-user-service"
  sleep 1
}

start_agent_service() {
  if is_port_listening "$CEERAT_AGENT_PORT"; then
    echo "Agent service already listening on http://localhost:$CEERAT_AGENT_PORT"
    return
  fi

  echo "Starting agent service on http://localhost:$CEERAT_AGENT_PORT"
  cd "$ROOT_DIR"
  start_detached "$AGENT_LOG" "$AGENT_PID" env \
    PORT="$CEERAT_AGENT_PORT" \
    USER_SERVICE_ADDR="$USER_SERVICE_ADDR" \
    CEERAT_USER_SERVICE_ADDR="$USER_SERVICE_ADDR" \
    OPENAI_API_KEY="${OPENAI_API_KEY:-}" \
    OPENAI_MODEL="${OPENAI_MODEL:-gpt-4.1-mini}" \
    "$BIN_DIR/ceerat-agent-service"
  sleep 1
}

start_web_ui() {
  if is_port_listening "$CEERAT_WEB_UI_PORT"; then
    echo "Web UI already listening on http://localhost:$CEERAT_WEB_UI_PORT"
    return
  fi

  echo "Starting web UI on http://localhost:$CEERAT_WEB_UI_PORT"
  cd "$ROOT_DIR"
  start_detached "$WEB_LOG" "$WEB_PID" env \
    CEERAT_WEB_UI_PORT="$CEERAT_WEB_UI_PORT" \
    CEERAT_API_BASE_URL="localhost:$CEERAT_SERVICE_PORT" \
    CEERAT_AGENT_BASE_URL="$CEERAT_AGENT_BASE_URL" \
    CEERAT_WEB_UI_ROOT="$ROOT_DIR/apps-repo/apps/ceerat-web-ui" \
    CEERAT_ENV="$CEERAT_ENV" \
    "$BIN_DIR/ceerat-web-ui"
  sleep 1
}

start_admin_ui() {
  if is_port_listening "$CEERAT_ADMIN_UI_PORT"; then
    echo "Admin UI already listening on http://localhost:$CEERAT_ADMIN_UI_PORT"
    return
  fi

  echo "Starting admin UI on http://localhost:$CEERAT_ADMIN_UI_PORT"
  cd "$ROOT_DIR"
  start_detached "$ADMIN_LOG" "$ADMIN_PID" env \
    CEERAT_ADMIN_UI_PORT="$CEERAT_ADMIN_UI_PORT" \
    CEERAT_API_BASE_URL="localhost:$CEERAT_SERVICE_PORT" \
    CEERAT_ENV="$CEERAT_ENV" \
    "$BIN_DIR/ceerat-admin-ui"
  sleep 1
}

start_customer_ui() {
  if is_port_listening "$CEERAT_CUSTOMER_UI_PORT"; then
    echo "Customer UI already listening on http://localhost:$CEERAT_CUSTOMER_UI_PORT"
    return
  fi

  echo "Starting customer UI on http://localhost:$CEERAT_CUSTOMER_UI_PORT"
  cd "$ROOT_DIR"
  start_detached "$CUSTOMER_LOG" "$CUSTOMER_PID" env \
    PORT="$CEERAT_CUSTOMER_UI_PORT" \
    CEERAT_API_BASE_URL="localhost:$CEERAT_SERVICE_PORT" \
    CEERAT_AGENT_BASE_URL="$CEERAT_AGENT_BASE_URL" \
    CEERAT_CUSTOMER_UI_ROOT="$ROOT_DIR/apps-repo/apps/ceerat-customer-ui" \
    CEERAT_ENV="$CEERAT_ENV" \
    "$BIN_DIR/ceerat-customer-ui"
  sleep 1
}

ensure_dirs

# Build sequence: contracts -> services -> apps
echo "Building contracts..."
if [[ -d "$ROOT_DIR/contracts-repo/packages/ceerat-contracts" ]]; then
  (cd "$ROOT_DIR/contracts-repo/packages/ceerat-contracts" && go test ./... && go build ./...) || {
    echo "Contracts build failed" >&2
    exit 1
  }
else
  echo "Contracts directory not found: $ROOT_DIR/contracts-repo/packages/ceerat-contracts" >&2
fi

echo "Building service (ceerat-user-service)..."
if [[ -d "$ROOT_DIR/services-repo/services/ceerat-user-service" ]]; then
  (cd "$ROOT_DIR/services-repo/services/ceerat-user-service" && go test ./... && go build -buildvcs=false -o "$BIN_DIR/ceerat-user-service" .) || {
    echo "Service build failed" >&2
    exit 1
  }
else
  echo "Service directory not found: $ROOT_DIR/services-repo/services/ceerat-user-service" >&2
fi

echo "Building apps..."
# agent service
if [[ -d "$ROOT_DIR/apps-repo/ai/ceerat-agent-service" ]]; then
  (cd "$ROOT_DIR/apps-repo/ai/ceerat-agent-service" && go test ./... && go build -buildvcs=false -o "$BIN_DIR/ceerat-agent-service" .) || {
    echo "Agent build failed" >&2
    exit 1
  }
else
  echo "Agent directory not found: $ROOT_DIR/apps-repo/ai/ceerat-agent-service" >&2
fi

# web UI
if [[ -d "$ROOT_DIR/apps-repo/apps/ceerat-web-ui" ]]; then
  (cd "$ROOT_DIR/apps-repo/apps/ceerat-web-ui" && go test ./... && go build -buildvcs=false -o "$BIN_DIR/ceerat-web-ui" .) || {
    echo "Web UI build failed" >&2
    exit 1
  }
else
  echo "Web UI directory not found: $ROOT_DIR/apps-repo/apps/ceerat-web-ui" >&2
fi

# admin UI
if [[ -d "$ROOT_DIR/apps-repo/apps/ceerat-admin-ui" ]]; then
  (cd "$ROOT_DIR/apps-repo/apps/ceerat-admin-ui" && go test ./... && go build -buildvcs=false -o "$BIN_DIR/ceerat-admin-ui" .) || {
    echo "Admin UI build failed" >&2
    exit 1
  }
else
  echo "Admin UI directory not found: $ROOT_DIR/apps-repo/apps/ceerat-admin-ui" >&2
fi

# customer UI
if [[ -d "$ROOT_DIR/apps-repo/apps/ceerat-customer-ui" ]]; then
  (cd "$ROOT_DIR/apps-repo/apps/ceerat-customer-ui" && go test ./... && go build -buildvcs=false -o "$BIN_DIR/ceerat-customer-ui" .) || {
    echo "Customer UI build failed" >&2
    exit 1
  }
else
  echo "Customer UI directory not found: $ROOT_DIR/apps-repo/apps/ceerat-customer-ui" >&2
fi

ensure_postgres
start_typesense
start_user_service
start_agent_service
start_web_ui
start_admin_ui
start_customer_ui

"$SCRIPT_DIR/status.sh"
print_log_paths
