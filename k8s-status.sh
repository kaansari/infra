#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

K8S_DRIVER="${K8S_DRIVER:-colima}"
K8S_CONTEXT="${K8S_CONTEXT:-}"

if [[ "$K8S_DRIVER" == "colima" ]]; then
  K8S_CONTEXT="${K8S_CONTEXT:-colima}"
elif [[ "$K8S_DRIVER" == "docker-desktop" ]]; then
  K8S_CONTEXT="${K8S_CONTEXT:-docker-desktop}"
fi

if [[ -n "$K8S_CONTEXT" ]]; then
  kubectl config use-context "$K8S_CONTEXT" >/dev/null 2>&1 || true
fi

echo "kubectl context: $(kubectl config current-context 2>/dev/null || echo unavailable)"

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "Kubernetes cluster is not reachable"
  if [[ "$K8S_DRIVER" == "colima" ]] && command -v colima >/dev/null 2>&1; then
    if colima status >/dev/null 2>&1; then
      colima status
    else
      echo "Colima is not running"
    fi
  fi
  exit 0
fi

echo
kubectl get nodes

echo
kubectl get pods -A

echo
kubectl get svc -A

echo
kubectl get ingress -A
