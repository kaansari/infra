#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

K8S_DRIVER="${K8S_DRIVER:-colima}"
K8S_CONTEXT="${K8S_CONTEXT:-}"
FOLLOW="${FOLLOW:-true}"
TAIL="${TAIL:-100}"

if [[ "$K8S_DRIVER" == "colima" ]]; then
  K8S_CONTEXT="${K8S_CONTEXT:-colima}"
elif [[ "$K8S_DRIVER" == "docker-desktop" ]]; then
  K8S_CONTEXT="${K8S_CONTEXT:-docker-desktop}"
fi

usage() {
  cat <<'EOF'
Usage: ./k8s-logs.sh [target] [--no-follow] [--tail N]

Targets:
  all            All Ceerat app/backend/data logs
  backend        ceerat-backend namespace
  frontend       ceerat-frontend namespace
  data           ceerat-data namespace
  user-service   ceerat-user-service deployment
  agent-service  ceerat-agent-service deployment
  web-ui         ceerat-web-ui deployment
  customer-ui    ceerat-customer-ui deployment
  admin-ui       ceerat-admin-ui deployment
  postgres       postgres statefulset
  typesense      typesense statefulset

Examples:
  ./k8s-logs.sh backend
  ./k8s-logs.sh customer-ui --tail 200
  FOLLOW=false ./k8s-logs.sh all
EOF
}

target="${1:-all}"
if [[ $# -gt 0 && "$1" != --* ]]; then
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-follow)
      FOLLOW=false
      shift
      ;;
    --tail)
      TAIL="${2:-}"
      if [[ -z "$TAIL" ]]; then
        echo "--tail requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -n "$K8S_CONTEXT" ]]; then
  kubectl config use-context "$K8S_CONTEXT" >/dev/null 2>&1 || true
fi

follow_arg=()
stern_follow_arg=()
if [[ "$FOLLOW" == "true" ]]; then
  follow_arg=(-f)
else
  stern_follow_arg=(--no-follow)
fi

logs_deploy() {
  local namespace="$1"
  local deploy="$2"
  kubectl -n "$namespace" logs "deploy/$deploy" --all-containers=true --tail="$TAIL" "${follow_arg[@]}"
}

logs_statefulset() {
  local namespace="$1"
  local statefulset="$2"
  kubectl -n "$namespace" logs "statefulset/$statefulset" --all-containers=true --tail="$TAIL" "${follow_arg[@]}"
}

logs_namespace() {
  local namespace="$1"
  if command -v stern >/dev/null 2>&1; then
    stern -n "$namespace" '.*' --tail "$TAIL" "${stern_follow_arg[@]}"
  else
    kubectl -n "$namespace" logs -l app.kubernetes.io/part-of=ceerat --all-containers=true --tail="$TAIL" --max-log-requests=20 "${follow_arg[@]}"
  fi
}

case "$target" in
  all)
    if command -v stern >/dev/null 2>&1; then
      stern -A 'ceerat-' --tail "$TAIL" "${stern_follow_arg[@]}"
    else
      echo "stern is not installed; showing current logs for each Ceerat namespace with kubectl."
      echo "Install stern for multi-pod follow: brew install stern"
      kubectl -n ceerat-backend logs -l app.kubernetes.io/part-of=ceerat --all-containers=true --tail="$TAIL" --prefix=true --max-log-requests=20 || true
      kubectl -n ceerat-frontend logs -l app.kubernetes.io/part-of=ceerat --all-containers=true --tail="$TAIL" --prefix=true --max-log-requests=20 || true
      kubectl -n ceerat-data logs -l app.kubernetes.io/part-of=ceerat --all-containers=true --tail="$TAIL" --prefix=true --max-log-requests=20 || true
    fi
    ;;
  backend)
    logs_namespace ceerat-backend
    ;;
  frontend)
    logs_namespace ceerat-frontend
    ;;
  data)
    logs_namespace ceerat-data
    ;;
  user-service)
    logs_deploy ceerat-backend ceerat-user-service
    ;;
  agent-service)
    logs_deploy ceerat-backend ceerat-agent-service
    ;;
  web-ui)
    logs_deploy ceerat-frontend ceerat-web-ui
    ;;
  customer-ui)
    logs_deploy ceerat-frontend ceerat-customer-ui
    ;;
  admin-ui)
    logs_deploy ceerat-frontend ceerat-admin-ui
    ;;
  postgres)
    logs_statefulset ceerat-data postgres
    ;;
  typesense)
    logs_statefulset ceerat-data typesense
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "Unknown log target: $target" >&2
    usage >&2
    exit 1
    ;;
esac
