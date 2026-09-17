#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "bash" || "${1:-}" == "sh" ]]; then
  exec "$@"
fi
exec /opt/keycloak/bin/kc.sh "$@"
