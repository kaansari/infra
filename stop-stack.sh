#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

stop_pidfile() {
  local name="$1"
  local pidfile="$2"
  local port="$3"
  local pid=""

  if [[ -f "$pidfile" ]]; then
    pid="$(cat "$pidfile")"
  fi

  if ! is_pid_running "$pid"; then
    pid="$(pid_for_port "$port")"
  fi

  if is_pid_running "$pid"; then
    echo "Stopping $name (pid $pid)"
    kill "$pid" || true
  else
    echo "$name is not running"
  fi

  rm -f "$pidfile"
}

ensure_dirs
configure_docker_cli

stop_pidfile "web UI" "$WEB_PID" "$CEERAT_WEB_UI_PORT"
stop_pidfile "admin UI" "$ADMIN_PID" "$CEERAT_ADMIN_UI_PORT"
stop_pidfile "customer UI" "$CUSTOMER_PID" "$CEERAT_CUSTOMER_UI_PORT"
stop_pidfile "agent service" "$AGENT_PID" "$CEERAT_AGENT_PORT"
stop_pidfile "agent gateway" "$GATEWAY_PID" "$CEERAT_AGENT_GATEWAY_PORT"
stop_pidfile "user service" "$SERVICE_PID" "$CEERAT_SERVICE_PORT"

if is_port_listening "$CEERAT_KEYCLOAK_PORT" && command -v docker >/dev/null 2>&1 && docker container inspect ceerat-keycloak >/dev/null 2>&1; then
  echo "Stopping Keycloak"
  docker stop ceerat-keycloak >/dev/null || true
else
  echo "Managed Keycloak container is not running"
fi

# Stop Typesense
if is_port_listening "8108"; then
  echo "Stopping Typesense"
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if command -v docker-compose >/dev/null 2>&1; then
    (cd "$script_dir" && docker-compose -f docker-compose.typesense.yml down) || true
  elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if docker compose version >/dev/null 2>&1; then
      (cd "$script_dir" && docker compose -f docker-compose.typesense.yml down) || true
    elif docker container inspect ceerat-typesense >/dev/null 2>&1; then
      docker stop ceerat-typesense >/dev/null || true
    else
      echo "docker compose was not found and ceerat-typesense container does not exist; Typesense shutdown skipped"
    fi
  else
    echo "Docker is not running or not reachable; Typesense shutdown skipped"
  fi
else
  echo "Typesense is not listening on port 8108"
fi

if [[ -x "$PG_CTL" && -d "$CEERAT_PGDATA" ]]; then
  if is_port_listening "$CEERAT_DB_PORT"; then
    echo "Stopping Postgres on port $CEERAT_DB_PORT"
    env LANG=C LC_ALL=C "$PG_CTL" -D "$CEERAT_PGDATA" stop
  else
    echo "Postgres is not listening on port $CEERAT_DB_PORT"
  fi
else
  echo "Postgres data directory or pg_ctl not found"
fi
