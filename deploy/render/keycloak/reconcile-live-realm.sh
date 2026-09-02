#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kcadm="${KCADM:-/opt/keycloak/bin/kcadm.sh}"
server="${CEERAT_KEYCLOAK_SERVER:-https://ceerat-keycloak.onrender.com}"
realm="${CEERAT_KEYCLOAK_REALM:-ceerat}"
admin_user="${CEERAT_KEYCLOAK_ADMIN_USERNAME:?set CEERAT_KEYCLOAK_ADMIN_USERNAME}"
admin_password="${CEERAT_KEYCLOAK_ADMIN_PASSWORD:?set CEERAT_KEYCLOAK_ADMIN_PASSWORD}"
config_file="$(mktemp)"
trap 'rm -f "$config_file"' EXIT

"$kcadm" config credentials --config "$config_file" --server "$server" \
  --realm master --user "$admin_user" --password "$admin_password"

"$kcadm" update "realms/$realm" --config "$config_file" \
  -s registrationAllowed=true \
  -s registrationEmailAsUsername=true \
  -s verifyEmail=true \
  -s accessTokenLifespan=600 \
  -s revokeRefreshToken=true \
  -s refreshTokenMaxReuse=0 \
  -s ssoSessionIdleTimeout=1800 \
  -s ssoSessionMaxLifespan=28800 \
  -s offlineSessionIdleTimeout=2592000 \
  -s offlineSessionMaxLifespanEnabled=true \
  -s offlineSessionMaxLifespan=5184000

reconcile_client() {
  local definition="$1"
  local client_id internal_id
  client_id="$(sed -n 's/^[[:space:]]*"clientId":[[:space:]]*"\([^"]*\)".*/\1/p' "$definition" | head -n 1)"
  if [[ -z "$client_id" ]]; then
    echo "Unable to read clientId from $definition" >&2
    return 1
  fi
  internal_id="$("$kcadm" get clients --config "$config_file" -r "$realm" \
    -q "clientId=$client_id" --fields id --format csv --noquotes | tail -n 1)"
  if [[ -z "$internal_id" || "$internal_id" == "id" ]]; then
    "$kcadm" create clients --config "$config_file" -r "$realm" -f "$definition"
    internal_id="$("$kcadm" get clients --config "$config_file" -r "$realm" \
      -q "clientId=$client_id" --fields id --format csv --noquotes | tail -n 1)"
    echo "Created $client_id"
  else
    "$kcadm" update "clients/$internal_id" --config "$config_file" -r "$realm" -f "$definition"
    echo "Updated $client_id"
  fi

  if [[ "$client_id" == "ceerat-gateway-revoker" && -n "${CEERAT_KEYCLOAK_REVOKER_CLIENT_SECRET:-}" ]]; then
    "$kcadm" update "clients/$internal_id" --config "$config_file" -r "$realm" \
      -s "secret=$CEERAT_KEYCLOAK_REVOKER_CLIENT_SECRET"
    echo "Updated disabled revoker secret from the environment"
  fi
}

for definition in \
  "$script_dir/clients/ceerat-mcp-chatgpt.json" \
  "$script_dir/clients/ceerat-mcp-codex-dev.json" \
  "$script_dir/clients/ceerat-gateway-revoker.json"; do
  reconcile_client "$definition"
done

echo "Reconciled realm $realm. Legacy ceerat-mcp-dev remains enabled for rollback."
