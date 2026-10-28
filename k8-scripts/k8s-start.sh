#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

detect_k8s_driver() {
  if kubectl config get-contexts docker-desktop >/dev/null 2>&1; then
    echo "docker-desktop"
    return
  fi

  if command -v colima >/dev/null 2>&1; then
    echo "colima"
    return
  fi

  if command -v docker >/dev/null 2>&1; then
    echo "docker-desktop"
    return
  fi

  echo "none"
}

K8S_DRIVER="${K8S_DRIVER:-$(detect_k8s_driver)}"
K8S_CONTEXT="${K8S_CONTEXT:-}"
K8S_REGISTRY="${K8S_REGISTRY:-ceerat}"
IMAGE_TAG="${IMAGE_TAG:-dev}"
PROJECT_ID="${PROJECT_ID:-PROJECT_ID}"
REGION="${REGION:-us}"
PUSH="${PUSH:-false}"
SKIP_BUILD="${SKIP_BUILD:-false}"
SKIP_DEPLOY="${SKIP_DEPLOY:-false}"
LOCAL_PORT_FORWARD="${LOCAL_PORT_FORWARD:-true}"
LOCAL_TLS="${LOCAL_TLS:-true}"
LOCAL_EXPOSE="${LOCAL_EXPOSE:-false}"
RUN_DIR="$SCRIPT_DIR/.run"
LOG_DIR="$SCRIPT_DIR/logs"
PORT_FORWARD_PID_FILE="$RUN_DIR/k8s-port-forwards.pid"

usage() {
  cat <<'EOF'
Usage: ./k8s-start.sh [--local|--expose]

Options:
  --local   Start local port-forwards after deploying:
            web      http://localhost:3000
            customer http://localhost:3005
            admin    http://localhost:3010
  --expose  Expose frontend apps through Kubernetes LoadBalancer Services:
            web      http://localhost:3000
            customer http://localhost:3005
            admin    http://localhost:3010
  -h, --help
            Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)
      LOCAL_PORT_FORWARD=true
      shift
      ;;
    --expose)
      LOCAL_EXPOSE=true
      LOCAL_PORT_FORWARD=false
      shift
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

if [[ "$LOCAL_PORT_FORWARD" == "true" && "$LOCAL_EXPOSE" == "true" ]]; then
  echo "Use either --local or --expose, not both; both modes need ports 3000, 3005, and 3010." >&2
  exit 1
fi

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "$name is required but was not found." >&2
    exit 1
  fi
}

wait_for_cluster() {
  local attempts="${1:-18}"
  local delay="${2:-5}"
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if kubectl cluster-info >/dev/null 2>&1; then
      kubectl cluster-info
      return 0
    fi
    if (( attempt < attempts )); then
      echo "Kubernetes API is not ready yet ($attempt/$attempts); waiting ${delay}s"
      sleep "$delay"
    fi
  done

  kubectl cluster-info
}

wait_for_nodes() {
  local attempts="${1:-18}"
  local delay="${2:-5}"
  local attempt

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if kubectl get nodes >/dev/null 2>&1; then
      return 0
    fi
    if (( attempt < attempts )); then
      echo "Kubernetes nodes are not ready yet ($attempt/$attempts); waiting ${delay}s"
      sleep "$delay"
    fi
  done

  kubectl get nodes >/dev/null
}

start_cluster() {
  case "$K8S_DRIVER" in
    colima)
      require_command colima
      if colima status >/dev/null 2>&1; then
        echo "Colima is already running"
      else
        echo "Starting Colima with Kubernetes"
        colima start --kubernetes
      fi
      K8S_CONTEXT="${K8S_CONTEXT:-colima}"
      ;;
    docker-desktop)
      echo "Using Docker Desktop Kubernetes. Enable Kubernetes in Docker Desktop if it is not already running."
      K8S_CONTEXT="${K8S_CONTEXT:-docker-desktop}"
      ;;
    none)
      echo "No supported local Kubernetes driver is available. Install Colima or enable Docker Desktop Kubernetes." >&2
      exit 1
      ;;
    *)
      echo "Unsupported K8S_DRIVER=$K8S_DRIVER. Use colima, docker-desktop, or none." >&2
      exit 1
      ;;
  esac

  if [[ -n "$K8S_CONTEXT" ]]; then
    kubectl config use-context "$K8S_CONTEXT"
  fi

  echo "Checking Kubernetes cluster"
  if wait_for_cluster 3 3; then
    wait_for_nodes 12 5
    return
  fi

  if [[ "$K8S_DRIVER" != "colima" ]]; then
    exit 1
  fi

  echo
  echo "Colima is running, but the Kubernetes API is not reachable."
  echo "Restarting Colima Kubernetes to refresh the local API server and kubeconfig."
  colima kubernetes stop >/dev/null 2>&1 || true
  colima kubernetes start
  kubectl config use-context "${K8S_CONTEXT:-colima}"

  echo "Rechecking Kubernetes cluster"
  if wait_for_cluster 18 5; then
    wait_for_nodes 12 5
    return
  fi

  echo
  echo "Colima Kubernetes is still unreachable; restarting the Colima VM with Kubernetes."
  colima stop
  colima start --kubernetes
  kubectl config use-context "${K8S_CONTEXT:-colima}"

  echo "Rechecking Kubernetes cluster after Colima VM restart"
  wait_for_cluster 24 5
  wait_for_nodes 18 5
}

deploy_ceerat() {
  if [[ "$SKIP_BUILD" != "true" ]]; then
    make -C "$ROOT_DIR" k8-build \
      K8S_REGISTRY="$K8S_REGISTRY" \
      IMAGE_TAG="$IMAGE_TAG" \
      PROJECT_ID="$PROJECT_ID" \
      REGION="$REGION"
  fi

  if [[ "$SKIP_DEPLOY" != "true" ]]; then
    if [[ "$PUSH" == "true" ]]; then
      make -C "$ROOT_DIR" k8-push K8S_REGISTRY="$K8S_REGISTRY" IMAGE_TAG="$IMAGE_TAG"
    fi
    if [[ "$LOCAL_TLS" == "true" ]]; then
      python3 "$SCRIPT_DIR/local_tls.py" --registry "$K8S_REGISTRY" --tag "$IMAGE_TAG"
      kubectl apply -f "$ROOT_DIR/.run/k8s-local/resources.json"
    else
      make -s -C "$ROOT_DIR" k8-render K8S_REGISTRY="$K8S_REGISTRY" IMAGE_TAG="$IMAGE_TAG" | kubectl apply -f -
    fi
  fi
}

wait_for_local_targets() {
  echo "Waiting for frontend deployments before starting local port-forwards"
  kubectl -n ceerat-frontend rollout status deploy/ceerat-web-ui --timeout=600s
  kubectl -n ceerat-frontend rollout status deploy/ceerat-customer-ui --timeout=600s
  kubectl -n ceerat-frontend rollout status deploy/ceerat-admin-ui --timeout=600s
}

wait_for_frontend_targets() {
  echo "Waiting for frontend deployments"
  kubectl -n ceerat-frontend rollout status deploy/ceerat-web-ui --timeout=600s
  kubectl -n ceerat-frontend rollout status deploy/ceerat-customer-ui --timeout=600s
  kubectl -n ceerat-frontend rollout status deploy/ceerat-admin-ui --timeout=600s
}

stop_existing_port_forwards() {
  python3 "$SCRIPT_DIR/forward.py" cleanup-legacy
}

start_port_forward() {
  local name="$1"
  local service="$2"
  local mapping="$3"
  local url="$4"
  local namespace="${5:-ceerat-frontend}"
  local log_file="$LOG_DIR/k8s-port-forward-$name.log"

  echo "Port-forwarding $service at $url"
  local pid
  pid="$(python3 - "$log_file" "$namespace" "$service" "$mapping" <<'PY_FORWARD'
import subprocess
import sys
with open(sys.argv[1], 'ab', buffering=0) as log:
    process = subprocess.Popen(['kubectl', '-n', sys.argv[2], 'port-forward',
                                'svc/' + sys.argv[3], sys.argv[4]],
                               stdin=subprocess.DEVNULL, stdout=log,
                               stderr=subprocess.STDOUT, start_new_session=True)
print(process.pid)
PY_FORWARD
)"
  echo "$pid" >> "$PORT_FORWARD_PID_FILE"
  sleep 1

  if ! kill -0 "$pid" >/dev/null 2>&1; then
    echo "Failed to start port-forward for $service. See $log_file:" >&2
    sed -n '1,20p' "$log_file" >&2 || true
    return 1
  fi
}

start_local_port_forwards() {
  if [[ "$LOCAL_TLS" == "true" ]]; then
    kubectl -n ceerat-backend rollout status deploy/ceerat-keycloak --timeout=600s
    kubectl -n ceerat-frontend rollout status deploy/ceerat-web-proxy --timeout=180s
    wait_for_local_targets
    python3 "$SCRIPT_DIR/reconcile_proxy_clients.py"
    python3 "$SCRIPT_DIR/forward.py" start
    return
  fi
  mkdir -p "$RUN_DIR" "$LOG_DIR"
  stop_existing_port_forwards
  : > "$PORT_FORWARD_PID_FILE"

  if [[ "$LOCAL_TLS" == "true" ]]; then
    kubectl -n ceerat-backend rollout status deploy/ceerat-keycloak --timeout=600s
    start_port_forward auth ceerat-keycloak 8443:8443 https://auth.localhost:8443 ceerat-backend
  fi
  wait_for_local_targets
  start_port_forward web ceerat-web-ui 3000:3000 http://localhost:3000
  start_port_forward customer ceerat-customer-ui 3005:3005 http://localhost:3005
  start_port_forward admin ceerat-admin-ui 3010:3010 http://localhost:3010

  echo
  echo "Local Kubernetes URLs:"
  echo "  web:      http://localhost:3000"
  echo "  customer: http://localhost:3005"
  echo "  admin:    http://localhost:3010"
  echo
  echo "Port-forward logs are in $LOG_DIR/k8s-port-forward-*.log"
}

expose_frontend_load_balancers() {
  if [[ "$LOCAL_TLS" == "true" ]]; then
    start_local_port_forwards
    kubectl -n ceerat-frontend patch svc ceerat-web-proxy --type merge -p '{"spec":{"type":"LoadBalancer"}}'
    return
  fi
  wait_for_frontend_targets

  echo "Exposing frontend services through Kubernetes LoadBalancer services"
  kubectl -n ceerat-frontend patch svc ceerat-web-ui --type merge -p '{"spec":{"type":"LoadBalancer"}}'
  kubectl -n ceerat-frontend patch svc ceerat-customer-ui --type merge -p '{"spec":{"type":"LoadBalancer"}}'
  kubectl -n ceerat-frontend patch svc ceerat-admin-ui --type merge -p '{"spec":{"type":"LoadBalancer"}}'

  echo
  echo "Kubernetes frontend URLs:"
  echo "  web:      http://localhost:3000"
  echo "  customer: http://localhost:3005"
  echo "  admin:    http://localhost:3010"
  echo
  echo "Service status:"
  kubectl -n ceerat-frontend get svc ceerat-web-ui ceerat-customer-ui ceerat-admin-ui
}

require_command kubectl
require_command make
require_command docker
require_command python3
if [[ "$LOCAL_TLS" == "true" ]]; then
  require_command ruby
  require_command openssl
fi

start_cluster
deploy_ceerat
"$SCRIPT_DIR/k8s-status.sh"

if [[ "$LOCAL_PORT_FORWARD" == "true" ]]; then
  start_local_port_forwards
fi

if [[ "$LOCAL_EXPOSE" == "true" ]]; then
  expose_frontend_load_balancers
fi
