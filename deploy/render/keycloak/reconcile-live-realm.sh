#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kcadm="${KCADM:-/opt/keycloak/bin/kcadm.sh}"
server="${CEERAT_KEYCLOAK_SERVER:-https://ceerat-keycloak.onrender.com}"
realm="${CEERAT_KEYCLOAK_REALM:-ceerat}"
admin_user="${CEERAT_KEYCLOAK_ADMIN_USERNAME:?set CEERAT_KEYCLOAK_ADMIN_USERNAME}"
admin_password="${CEERAT_KEYCLOAK_ADMIN_PASSWORD:?set CEERAT_KEYCLOAK_ADMIN_PASSWORD}"
revoker_secret="${CEERAT_KEYCLOAK_REVOKER_CLIENT_SECRET:?set CEERAT_KEYCLOAK_REVOKER_CLIENT_SECRET}"
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
  -s offlineSessionMaxLifespan=5184000 \
  -s eventsEnabled=true \
  -s 'eventsListeners=["jboss-logging"]' \
  -s 'enabledEventTypes=["LOGIN","LOGIN_ERROR","CODE_TO_TOKEN","CODE_TO_TOKEN_ERROR","REFRESH_TOKEN","REFRESH_TOKEN_ERROR","GRANT_CONSENT","GRANT_CONSENT_ERROR","DENY_CONSENT","UPDATE_CONSENT","UPDATE_CONSENT_ERROR","REVOKE_GRANT","REVOKE_GRANT_ERROR"]'

reconcile_client_scope() {
  local definition="$1"
  local scope_name internal_id="" candidate_id candidate_name
  scope_name="$(sed -n 's/^[[:space:]]*"name":[[:space:]]*"\([^"]*\)".*/\1/p' "$definition" | head -n 1)"
  if [[ -z "$scope_name" ]]; then
    echo "Unable to read client scope name from $definition" >&2
    return 1
  fi
  while IFS=, read -r candidate_id candidate_name; do
    if [[ "$candidate_name" == "$scope_name" ]]; then
      internal_id="$candidate_id"
      break
    fi
  done < <("$kcadm" get client-scopes --config "$config_file" -r "$realm" \
    --fields id,name --format csv --noquotes)
  if [[ -z "$internal_id" ]]; then
    "$kcadm" create client-scopes --config "$config_file" -r "$realm" -f "$definition"
    echo "Created client scope $scope_name"
  else
    "$kcadm" update "client-scopes/$internal_id" --config "$config_file" -r "$realm" -f "$definition"
    echo "Updated client scope $scope_name"
  fi
}

client_scope_id() {
  local requested_name="$1"
  local candidate_id candidate_name
  while IFS=, read -r candidate_id candidate_name; do
    if [[ "$candidate_name" == "$requested_name" ]]; then
      printf '%s\n' "$candidate_id"
      return 0
    fi
  done < <("$kcadm" get client-scopes --config "$config_file" -r "$realm" \
    --fields id,name --format csv --noquotes)
  return 1
}

assign_product_scopes() {
  local client_internal_id="$1"
  local scope_name scope_internal_id
  for scope_name in \
    ceerat.products.read \
    ceerat.products.cart.read \
    ceerat.products.cart.write; do
    scope_internal_id="$(client_scope_id "$scope_name")" || {
      echo "Unable to find reconciled client scope $scope_name" >&2
      return 1
    }
    "$kcadm" update "clients/$client_internal_id/optional-client-scopes/$scope_internal_id" \
      --config "$config_file" -r "$realm"
  done
}

reconcile_client() {
  local definition="$1"
  local client_id internal_id existing_secret=""
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
    if [[ "$client_id" == "ceerat-mcp-chatgpt" ]]; then
      existing_secret="$("$kcadm" get "clients/$internal_id/client-secret" \
        --config "$config_file" -r "$realm" --fields value \
        --format csv --noquotes | tail -n 1)"
      if [[ -z "$existing_secret" || "$existing_secret" == "value" ]]; then
        echo "Unable to preserve the existing ceerat-mcp-chatgpt secret" >&2
        return 1
      fi
    fi
    "$kcadm" update "clients/$internal_id" --config "$config_file" -r "$realm" -f "$definition"
    if [[ "$client_id" == "ceerat-mcp-chatgpt" ]]; then
      "$kcadm" update "clients/$internal_id" --config "$config_file" -r "$realm" \
        -s "secret=$existing_secret"
    fi
    echo "Updated $client_id"
  fi

  if [[ "$client_id" == "ceerat-mcp-chatgpt" || "$client_id" == "ceerat-mcp-codex-dev" ]]; then
    assign_product_scopes "$internal_id"
    echo "Assigned optional product scopes to $client_id"
  fi

  if [[ "$client_id" == "ceerat-gateway-revoker" ]]; then
    "$kcadm" update "clients/$internal_id" --config "$config_file" -r "$realm" \
      -s "secret=$revoker_secret"
    "$kcadm" add-roles --config "$config_file" -r "$realm" \
      --uusername "service-account-ceerat-gateway-revoker" \
      --cclientid realm-management --rolename manage-users
    echo "Updated revoker secret and assigned realm-management/manage-users"
  fi
}

for definition in "$script_dir"/client-scopes/*.json; do
  reconcile_client_scope "$definition"
done

for definition in \
  "$script_dir/clients/ceerat-mcp-chatgpt.json" \
  "$script_dir/clients/ceerat-mcp-codex-dev.json" \
  "$script_dir/clients/ceerat-gateway-revoker.json"; do
  reconcile_client "$definition"
done

echo "Reconciled realm $realm. Legacy ceerat-mcp-dev remains enabled for rollback."
