#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

K8S_DRIVER="${K8S_DRIVER:-colima}"
K8S_CONTEXT="${K8S_CONTEXT:-}"
K8S_REGISTRY="${K8S_REGISTRY:-ceerat}"
IMAGE_TAG="${IMAGE_TAG:-dev}"
PROJECT_ID="${PROJECT_ID:-PROJECT_ID}"
REGION="${REGION:-us}"
PUSH="${PUSH:-false}"
SKIP_BUILD="${SKIP_BUILD:-false}"
SKIP_DEPLOY="${SKIP_DEPLOY:-false}"
LOCAL_PORT_FORWARD="${LOCAL_PORT_FORWARD:-false}"
RUN_DIR="$SCRIPT_DIR/.run"
LOG_DIR="$SCRIPT_DIR/logs"
PORT_FORWARD_PID_FILE="$RUN_DIR/k8s-port-forwards.pid"

usage() {
  cat <<'EOF'
Usage: ./k8s-start.sh [--local]

Options:
  --local   Start local port-forwards after deploying:
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
      echo "Using the current kubectl context"
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
    make k8-build \
      K8S_REGISTRY="$K8S_REGISTRY" \
      IMAGE_TAG="$IMAGE_TAG" \
      PROJECT_ID="$PROJECT_ID" \
      REGION="$REGION"
  fi

  if [[ "$SKIP_DEPLOY" != "true" ]]; then
    make k8-deploy \
      K8S_REGISTRY="$K8S_REGISTRY" \
      IMAGE_TAG="$IMAGE_TAG" \
      PROJECT_ID="$PROJECT_ID" \
      REGION="$REGION" \
      PUSH="$PUSH"
  fi
}

wait_for_local_targets() {
  echo "Waiting for frontend deployments before starting local port-forwards"
  kubectl -n ceerat-frontend rollout status deploy/ceerat-web-ui --timeout=180s
  kubectl -n ceerat-frontend rollout status deploy/ceerat-customer-ui --timeout=180s
  kubectl -n ceerat-frontend rollout status deploy/ceerat-admin-ui --timeout=180s
}

stop_existing_port_forwards() {
  if [[ ! -f "$PORT_FORWARD_PID_FILE" ]]; then
    return
  fi

  while read -r pid; do
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  done < "$PORT_FORWARD_PID_FILE"
  rm -f "$PORT_FORWARD_PID_FILE"
}

start_port_forward() {
  local name="$1"
  local service="$2"
  local mapping="$3"
  local url="$4"
  local log_file="$LOG_DIR/k8s-port-forward-$name.log"

  echo "Port-forwarding $service at $url"
  nohup kubectl -n ceerat-frontend port-forward "svc/$service" "$mapping" >"$log_file" 2>&1 </dev/null &
  local pid="$!"
  echo "$pid" >> "$PORT_FORWARD_PID_FILE"
  sleep 1

  if ! kill -0 "$pid" >/dev/null 2>&1; then
    echo "Failed to start port-forward for $service. See $log_file:" >&2
    sed -n '1,20p' "$log_file" >&2 || true
    return 1
  fi
}

start_local_port_forwards() {
  mkdir -p "$RUN_DIR" "$LOG_DIR"
  stop_existing_port_forwards
  : > "$PORT_FORWARD_PID_FILE"

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

require_command kubectl
require_command make
require_command docker

start_cluster
deploy_ceerat
"$SCRIPT_DIR/k8s-status.sh"

if [[ "$LOCAL_PORT_FORWARD" == "true" ]]; then
  start_local_port_forwards
fi
