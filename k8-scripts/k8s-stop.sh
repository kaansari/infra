#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

K8S_DRIVER="${K8S_DRIVER:-colima}"
K8S_CONTEXT="${K8S_CONTEXT:-}"
K8S_REGISTRY="${K8S_REGISTRY:-ceerat}"
IMAGE_TAG="${IMAGE_TAG:-dev}"
PROJECT_ID="${PROJECT_ID:-PROJECT_ID}"
REGION="${REGION:-us}"
SKIP_DELETE="${SKIP_DELETE:-false}"
STOP_CLUSTER="${STOP_CLUSTER:-true}"
RUN_DIR="$SCRIPT_DIR/.run"
PORT_FORWARD_PID_FILE="$RUN_DIR/k8s-port-forwards.pid"

stop_port_forwards() {
  if [[ ! -f "$PORT_FORWARD_PID_FILE" ]]; then
    return
  fi

  echo "Stopping Kubernetes port-forwards"
  while read -r pid; do
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  done < "$PORT_FORWARD_PID_FILE"
  rm -f "$PORT_FORWARD_PID_FILE"
}

if [[ "$K8S_DRIVER" == "colima" ]]; then
  K8S_CONTEXT="${K8S_CONTEXT:-colima}"
elif [[ "$K8S_DRIVER" == "docker-desktop" ]]; then
  K8S_CONTEXT="${K8S_CONTEXT:-docker-desktop}"
fi

if [[ -n "$K8S_CONTEXT" ]]; then
  kubectl config use-context "$K8S_CONTEXT" >/dev/null 2>&1 || true
fi

stop_port_forwards

if [[ "$SKIP_DELETE" != "true" ]]; then
  if kubectl cluster-info >/dev/null 2>&1; then
    echo "Deleting Ceerat Kubernetes resources"
    make -C "$ROOT_DIR" k8-render \
      K8S_REGISTRY="$K8S_REGISTRY" \
      IMAGE_TAG="$IMAGE_TAG" \
      PROJECT_ID="$PROJECT_ID" \
      REGION="$REGION" | kubectl delete -f - --ignore-not-found=true
  else
    echo "Kubernetes cluster is not reachable; resource deletion skipped"
  fi
fi

if [[ "$STOP_CLUSTER" == "true" ]]; then
  case "$K8S_DRIVER" in
    colima)
      if command -v colima >/dev/null 2>&1; then
        if colima status >/dev/null 2>&1; then
          echo "Stopping Colima"
          colima stop
        else
          echo "Colima is not running"
        fi
      else
        echo "Colima is not installed; cluster stop skipped"
      fi
      ;;
    docker-desktop)
      echo "Docker Desktop Kubernetes must be stopped from Docker Desktop settings"
      ;;
    none)
      echo "K8S_DRIVER=none; cluster stop skipped"
      ;;
  esac
fi
