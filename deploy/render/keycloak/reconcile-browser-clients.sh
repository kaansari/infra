#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kcadm="${KCADM:-/opt/keycloak/bin/kcadm.sh}"
server="${CEERAT_KEYCLOAK_SERVER:-https://ceerat-keycloak.onrender.com}"
realm="${CEERAT_KEYCLOAK_REALM:-ceerat}"
admin_user="${CEERAT_KEYCLOAK_ADMIN_USERNAME:-${KC_BOOTSTRAP_ADMIN_USERNAME:?missing Keycloak admin username}}"
admin_password="${CEERAT_KEYCLOAK_ADMIN_PASSWORD:-${KC_BOOTSTRAP_ADMIN_PASSWORD:?missing Keycloak admin password}}"
config_file="$(mktemp)"
trap 'rm -f "$config_file"' EXIT

"$kcadm" config credentials --config "$config_file" --server "$server" \
  --realm master --user "$admin_user" --password "$admin_password"

existing_scopes="$("$kcadm" get client-scopes --config "$config_file" -r "$realm" \
  --fields name --format csv --noquotes)"

scope_exists() {
  local wanted="$1" current
  while IFS= read -r current; do
    [[ "$current" == "$wanted" ]] && return 0
  done <<< "$existing_scopes"
  return 1
}

for definition in "$script_dir"/client-scopes/*.json; do
  scope_name="$(sed -n 's/^[[:space:]]*"name":[[:space:]]*"\([^"]*\)".*/\1/p' "$definition" | head -n 1)"
  if ! scope_exists "$scope_name"; then
    "$kcadm" create client-scopes --config "$config_file" -r "$realm" -f "$definition"
    existing_scopes="${existing_scopes}"$'\n'"${scope_name}"
    echo "Created client scope $scope_name"
  fi
done

for definition in \
  "$script_dir/clients/ceerat-admin-ui.json" \
  "$script_dir/clients/ceerat-web-ui.json" \
  "$script_dir/clients/ceerat-customer-ui.json"; do
  client_id="$(sed -n 's/^[[:space:]]*"clientId":[[:space:]]*"\([^"]*\)".*/\1/p' "$definition" | head -n 1)"
  internal_id="$("$kcadm" get clients --config "$config_file" -r "$realm" \
    -q "clientId=$client_id" --fields id --format csv --noquotes | tail -n 1)"
  if [[ -z "$internal_id" || "$internal_id" == "id" ]]; then
    "$kcadm" create clients --config "$config_file" -r "$realm" -f "$definition"
    echo "Created $client_id"
  else
    "$kcadm" update "clients/$internal_id" --config "$config_file" -r "$realm" -f "$definition"
    echo "Updated $client_id"
  fi
done

echo "Reconciled browser OAuth clients for realm $realm."
