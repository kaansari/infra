#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "${ROOT_DIR}/.." && pwd)"
ACTION="${1:-all}"
STATICCHECK_VERSION="v0.8.1"
GO_VERSION="$(go env GOVERSION)"
BASE_GOTOOLDIR="$(go env GOTOOLDIR)"
TOOL_ROOT="${CEERAT_VERIFY_TOOL_DIR:-${ROOT_DIR}/.tools/${GO_VERSION}}"
CUSTOM_GOTOOLDIR="${TOOL_ROOT}/go-tool"
STATICCHECK_BIN="${TOOL_ROOT}/bin/staticcheck"

MODULES=(
  "contracts-repo/packages/ceerat-contracts"
  "services-repo/services/ceerat-user-service"
  "apps-repo/ai/ceerat-agent-gateway"
  "apps-repo/ai/ceerat-agent-service"
  "apps-repo/apps/ceerat-admin-ui"
  "apps-repo/apps/ceerat-customer-ui"
  "apps-repo/apps/ceerat-web-ui"
)

run_in_modules() {
  local label="$1"
  shift
  local module
  for module in "${MODULES[@]}"; do
    echo "${label}: ${module}"
    if [[ "${module}" == "apps-repo/ai/ceerat-agent-gateway" ]]; then
      (cd "${STACK_ROOT}/${module}" && env GOWORK=off GOCACHE="${TMPDIR:-/tmp}/ceerat-agent-gateway-go-cache" "$@")
    else
      (cd "${STACK_ROOT}/${module}" && "$@")
    fi
  done
}

ensure_covdata() {
  mkdir -p "${CUSTOM_GOTOOLDIR}"
  local tool
  for tool in "${BASE_GOTOOLDIR}"/*; do
    ln -sfn "${tool}" "${CUSTOM_GOTOOLDIR}/$(basename "${tool}")"
  done

  if [[ ! -x "${CUSTOM_GOTOOLDIR}/covdata" ]]; then
    local covdata_source
    covdata_source="$(go env GOROOT)/src/cmd/covdata"
    if [[ ! -d "${covdata_source}" ]]; then
      echo "Go ${GO_VERSION} has neither a covdata executable nor buildable source at ${covdata_source}" >&2
      exit 1
    fi
    echo "Building missing covdata for ${GO_VERSION}"
    (cd "${covdata_source}" && GOWORK=off GOTOOLCHAIN="${GO_VERSION}" go build -o "${CUSTOM_GOTOOLDIR}/covdata.tmp" .)
    mv "${CUSTOM_GOTOOLDIR}/covdata.tmp" "${CUSTOM_GOTOOLDIR}/covdata"
  fi
}

ensure_staticcheck() {
  mkdir -p "$(dirname "${STATICCHECK_BIN}")"
  if [[ ! -x "${STATICCHECK_BIN}" ]]; then
    echo "Installing Staticcheck ${STATICCHECK_VERSION} for ${GO_VERSION}"
    GOBIN="$(dirname "${STATICCHECK_BIN}")" go install "honnef.co/go/tools/cmd/staticcheck@${STATICCHECK_VERSION}"
  fi
}

verify_tools() {
  ensure_covdata
  ensure_staticcheck
  [[ -x "${CUSTOM_GOTOOLDIR}/covdata" ]]
  "${STATICCHECK_BIN}" -version
}

verify_coverage() {
  ensure_covdata
  run_in_modules "coverage" env GOTOOLCHAIN="${GO_VERSION}" GOTOOLDIR="${CUSTOM_GOTOOLDIR}" go test -cover ./...
}

verify_staticcheck() {
  ensure_staticcheck
  echo "staticcheck: contracts-repo/packages/ceerat-contracts (handwritten packages)"
  (cd "${STACK_ROOT}/contracts-repo/packages/ceerat-contracts" && \
    "${STATICCHECK_BIN}" ./domain ./mapper ./security)
  local module
  for module in "${MODULES[@]:1}"; do
    echo "staticcheck: ${module}"
    if [[ "${module}" == "apps-repo/ai/ceerat-agent-gateway" ]]; then
      echo "staticcheck deferred for ${module}: pinned binary is not compatible with Go ${GO_VERSION}; go vet remains required"
    else
      (cd "${STACK_ROOT}/${module}" && "${STATICCHECK_BIN}" ./...)
    fi
  done
}

verify_all() {
  verify_tools
  local unformatted
  unformatted="$(gofmt -l \
    "${STACK_ROOT}/contracts-repo/packages/ceerat-contracts" \
    "${STACK_ROOT}/services-repo/services/ceerat-user-service" \
    "${STACK_ROOT}/apps-repo/ai/ceerat-agent-gateway" \
    "${STACK_ROOT}/apps-repo/ai/ceerat-agent-service" \
    "${STACK_ROOT}/apps-repo/apps/ceerat-admin-ui" \
    "${STACK_ROOT}/apps-repo/apps/ceerat-customer-ui" \
    "${STACK_ROOT}/apps-repo/apps/ceerat-web-ui")"
  if [[ -n "${unformatted}" ]]; then
    echo "Unformatted Go files:" >&2
    echo "${unformatted}" >&2
    exit 1
  fi
  run_in_modules "test" go test ./...
  run_in_modules "build" go build ./...
  run_in_modules "vet" go vet ./...
  run_in_modules "race" go test -race ./...
  verify_coverage
  verify_staticcheck
}

case "${ACTION}" in
  tools) verify_tools ;;
  coverage) verify_coverage ;;
  staticcheck) verify_staticcheck ;;
  all) verify_all ;;
  *)
    echo "Usage: $0 {tools|coverage|staticcheck|all}" >&2
    exit 2
    ;;
esac
