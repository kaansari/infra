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
echo "Ingress classes"
ingress_classes="$(kubectl get ingressclass 2>/dev/null || true)"
if [[ -n "$ingress_classes" ]]; then
  echo "$ingress_classes"
else
  echo "No ingress classes found"
fi

echo
echo "Nodes"
kubectl get nodes || echo "Unable to list nodes"

echo
echo "Ceerat pods"
for namespace in ceerat-backend ceerat-frontend ceerat-data; do
  echo
  echo "namespace/$namespace"
  kubectl -n "$namespace" get pods -o wide 2>/dev/null || echo "Namespace $namespace not found"
done

echo
echo "Ceerat services"
for namespace in ceerat-backend ceerat-frontend ceerat-data; do
  echo
  echo "namespace/$namespace"
  kubectl -n "$namespace" get svc 2>/dev/null || echo "Namespace $namespace not found"
done

echo
echo "Ingress"
kubectl get ingress -A || echo "Unable to list ingress resources"

echo
echo "Recent Ceerat events"
for namespace in ceerat-backend ceerat-frontend ceerat-data; do
  echo
  echo "namespace/$namespace"
  kubectl -n "$namespace" get events --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -20 || echo "No events"
done

echo
echo "Local access"
cat <<'EOF'
LoadBalancer mode:
  ./k8s-start.sh --expose
  web:      http://localhost:3000
  customer: http://localhost:3005
  admin:    http://localhost:3010

Port-forward mode:
  ./k8s-start.sh --local
  web:      http://localhost:3000
  customer: http://localhost:3005
  admin:    http://localhost:3010

Manual port-forwards:
  kubectl -n ceerat-frontend port-forward svc/ceerat-web-ui 3000:3000
  kubectl -n ceerat-frontend port-forward svc/ceerat-customer-ui 3005:3005
  kubectl -n ceerat-frontend port-forward svc/ceerat-admin-ui 3010:3010
  kubectl -n ceerat-data port-forward svc/postgres 55434:5432

Ingress hostnames:
  app.ceerat.local
  customer.ceerat.local
  admin.ceerat.local

Logs:
  ./k8s-logs.sh backend
  ./k8s-logs.sh frontend
  ./k8s-logs.sh user-service
  ./k8s-logs.sh customer-ui
EOF
