ROOT_DIR := $(shell cd $(dir $(realpath $(firstword $(MAKEFILE_LIST)))) && pwd)
STACK_ROOT := $(ROOT_DIR)/..
BIN_DIR := $(STACK_ROOT)/bin
RUN_DIR := $(STACK_ROOT)/.run
LOG_DIR := $(STACK_ROOT)/logs
CUSTOMER_PORT ?= 3005
CUSTOMER_BIN := $(BIN_DIR)/ceerat-customer-ui
CUSTOMER_LOG := $(LOG_DIR)/customer-ui.log
CUSTOMER_PID := $(RUN_DIR)/customer-ui.pid
ADMIN_PORT ?= 3010
ADMIN_BIN := $(BIN_DIR)/ceerat-admin-ui
ADMIN_LOG := $(LOG_DIR)/admin-ui.log
ADMIN_PID := $(RUN_DIR)/admin-ui.pid
PROJECT_ID ?= PROJECT_ID
REGION ?= us
K8S_REPOSITORY ?= ceerat
K8S_REGISTRY ?= $(REGION)-docker.pkg.dev/$(PROJECT_ID)/$(K8S_REPOSITORY)
IMAGE_TAG ?= dev
K8S_OVERLAY ?= k8s
KUBECTL ?= kubectl
DOCKER ?= docker
PUSH ?= false
K8S_CONTEXT_DIR ?= $(ROOT_DIR)/.k8-build-context

.PHONY: all build-customer-ui start-customer-ui stop-customer-ui build-admin-ui start-admin-ui stop-admin-ui start-stack stop-stack status-stack ensure-dirs verify-builder verify-tools verify-coverage verify-staticcheck verify-code verify-platform verify-render-native test-keycloak-config reconcile-keycloak-live verify-api-tools verify-api-read verify-api-write verify-api-security verify-api k8-context k8-build k8-push k8-deploy k8-render start-k8 stop-k8 status-k8 k8-logs

all: build-customer-ui

ensure-dirs:
	@mkdir -p "$(BIN_DIR)" "$(RUN_DIR)" "$(LOG_DIR)"

build-customer-ui: ensure-dirs
	@if [ -d "$(ROOT_DIR)/../apps-repo/apps/ceerat-customer-ui" ]; then \
		cd "$(ROOT_DIR)/../apps-repo/apps/ceerat-customer-ui" && go test ./... && go build -o "$(CUSTOMER_BIN)" .; \
	else \
		echo "Customer UI directory not found: $(ROOT_DIR)/../apps-repo/apps/ceerat-customer-ui" && exit 1; \
	fi

start-customer-ui: ensure-dirs
	@echo "Starting customer UI on http://localhost:$(CUSTOMER_PORT)"
	@nohup perl -MPOSIX=setsid -e 'setsid(); exec @ARGV or die "exec failed: $$!\n"' env \
		PORT="$(CUSTOMER_PORT)" \
		CEERAT_API_BASE_URL="localhost:50051" \
		CEERAT_AGENT_BASE_URL="http://localhost:8088" \
		CEERAT_CUSTOMER_UI_ROOT="$(STACK_ROOT)/apps-repo/apps/ceerat-customer-ui" \
		CEERAT_ENV="development" \
		"$(CUSTOMER_BIN)" </dev/null >>"$(CUSTOMER_LOG)" 2>&1 &
	@sleep 1; \
	pid=$$(lsof -tiTCP:$(CUSTOMER_PORT) -sTCP:LISTEN 2>/dev/null | head -n 1); \
	if [ -n "$$pid" ]; then \
		echo "$$pid" >"$(CUSTOMER_PID)"; \
	else \
		echo $$! >"$(CUSTOMER_PID)"; \
	fi

stop-customer-ui:
	@pid=$$(lsof -tiTCP:$(CUSTOMER_PORT) -sTCP:LISTEN 2>/dev/null | head -n 1); \
	if [ -n "$$pid" ]; then \
		echo "Stopping customer UI (pid $$pid)"; \
		kill $$pid || true; \
		rm -f "$(CUSTOMER_PID)"; \
	elif [ -f "$(CUSTOMER_PID)" ]; then \
		pid=$$(cat "$(CUSTOMER_PID)"); \
		if kill -0 $$pid >/dev/null 2>&1; then \
			echo "Stopping customer UI (pid $$pid)"; \
			kill $$pid || true; \
		else \
			echo "Customer UI not running"; \
		fi; \
		rm -f "$(CUSTOMER_PID)"; \
	else \
		echo "Customer UI not running"; \
	fi

build-admin-ui: ensure-dirs
	@if [ -d "$(ROOT_DIR)/../apps-repo/apps/ceerat-admin-ui" ]; then \
		cd "$(ROOT_DIR)/../apps-repo/apps/ceerat-admin-ui" && go test ./... && go build -o "$(ADMIN_BIN)" .; \
	else \
		echo "Admin UI directory not found: $(ROOT_DIR)/../apps-repo/apps/ceerat-admin-ui" && exit 1; \
	fi

start-admin-ui: ensure-dirs
	@echo "Starting admin UI on http://localhost:$(ADMIN_PORT)"
	@nohup perl -MPOSIX=setsid -e 'setsid(); exec @ARGV or die "exec failed: $$!\n"' env \
		CEERAT_ADMIN_UI_PORT="$(ADMIN_PORT)" \
		CEERAT_API_BASE_URL="$${CEERAT_API_BASE_URL:-localhost:50051}" \
		CEERAT_ADMIN_API_BASE_URL="$${CEERAT_ADMIN_API_BASE_URL:-http://localhost:8081}" \
		CEERAT_ENV="development" \
		"$(ADMIN_BIN)" </dev/null >>"$(ADMIN_LOG)" 2>&1 & echo $$! >"$(ADMIN_PID)"

stop-admin-ui:
	@if [ -f "$(ADMIN_PID)" ]; then \
		pid=$$(cat "$(ADMIN_PID)"); \
		if kill -0 $$pid >/dev/null 2>&1; then \
			echo "Stopping admin UI (pid $$pid)"; \
			kill $$pid || true; \
		else \
			echo "Admin UI not running"; \
		fi; \
		rm -f "$(ADMIN_PID)"; \
	else \
		echo "Admin PID file not found: $(ADMIN_PID)"; \
	fi

start-stack:
	@./start-stack.sh

stop-stack:
	@./stop-stack.sh

status-stack:
	@./status.sh

# Code-only verification. These targets never start the stack, Docker, or Kubernetes.
# Tool versions and the covdata compatibility shim are managed by verify-code.sh.
verify-builder:
	@cd "$(STACK_ROOT)/ceerat-platform-builder-agent" && PYTHONDONTWRITEBYTECODE=1 ceerat-builder check drift --output json
	@cd "$(STACK_ROOT)/ceerat-platform-builder-agent" && PYTHONDONTWRITEBYTECODE=1 ceerat-builder check apps --output json

verify-tools:
	@./verify-code.sh tools

verify-coverage:
	@./verify-code.sh coverage

verify-staticcheck:
	@./verify-code.sh staticcheck

verify-code:
	@./verify-code.sh all

verify-platform: verify-builder verify-code

verify-render-native:
	@cd "$(STACK_ROOT)/apps-repo/ai/ceerat-agent-gateway" && GOWORK=off go test -mod=vendor ./... && GOWORK=off go build -mod=vendor -trimpath -o /tmp/ceerat-agent-gateway .
	@cd "$(STACK_ROOT)/services-repo/services/ceerat-user-service" && GOWORK=off go test -mod=vendor ./... && GOWORK=off go build -mod=vendor -trimpath -o /tmp/ceerat-user-service .

test-keycloak-config:
	@ruby deploy/render/keycloak/realm_config_test.rb
	@bash -n deploy/render/keycloak/reconcile-live-realm.sh
	@bash -n deploy/render/keycloak/oauth-policy-smoke-test.sh

reconcile-keycloak-live:
	@test -n "$${CEERAT_KEYCLOAK_ADMIN_USERNAME:-}" || (echo "set CEERAT_KEYCLOAK_ADMIN_USERNAME" >&2; exit 1)
	@test -n "$${CEERAT_KEYCLOAK_ADMIN_PASSWORD:-}" || (echo "set CEERAT_KEYCLOAK_ADMIN_PASSWORD" >&2; exit 1)
	@$(DOCKER) run --rm --entrypoint /bin/bash \
		-e CEERAT_KEYCLOAK_ADMIN_USERNAME \
		-e CEERAT_KEYCLOAK_ADMIN_PASSWORD \
		-e CEERAT_KEYCLOAK_REVOKER_CLIENT_SECRET \
		-e CEERAT_KEYCLOAK_SERVER=https://ceerat-keycloak.onrender.com \
		-v "$(ROOT_DIR)/deploy/render/keycloak:/work:ro" \
		quay.io/keycloak/keycloak:26.3 /work/reconcile-live-realm.sh

# Phase 2 live API verification. Stack startup is opt-in with
# VERIFY_API_START_STACK=true and always goes through make start-stack.
verify-api-tools:
	@./verify-api.sh tools

verify-api-read:
	@./verify-api.sh read

verify-api-write:
	@./verify-api.sh write

verify-api-security:
	@./verify-api.sh security

verify-api: verify-platform
	@./verify-api.sh all

start-k8:
	@./k8s-start.sh

stop-k8:
	@./k8s-stop.sh

status-k8:
	@./k8s-status.sh

k8-logs:
	@./k8s-logs.sh

k8-context:
	@echo "Preparing Docker build context in $(K8S_CONTEXT_DIR)"
	@rm -rf "$(K8S_CONTEXT_DIR)"
	@mkdir -p "$(K8S_CONTEXT_DIR)"
	@sed '/\.\/atscrawler/d' "$(STACK_ROOT)/go.work" >"$(K8S_CONTEXT_DIR)/go.work"
	@cp "$(STACK_ROOT)/go.work.sum" "$(K8S_CONTEXT_DIR)/go.work.sum"
	@cp -R "$(STACK_ROOT)/contracts-repo" "$(K8S_CONTEXT_DIR)/contracts-repo"
	@cp -R "$(STACK_ROOT)/apps-repo" "$(K8S_CONTEXT_DIR)/apps-repo"
	@cp -R "$(STACK_ROOT)/services-repo" "$(K8S_CONTEXT_DIR)/services-repo"
	@rm -rf "$(K8S_CONTEXT_DIR)/contracts-repo/.git" "$(K8S_CONTEXT_DIR)/apps-repo/.git" "$(K8S_CONTEXT_DIR)/services-repo/.git"

k8-build: k8-context
	@echo "Building Ceerat Kubernetes images with tag $(IMAGE_TAG)"
	@$(DOCKER) build -f "$(ROOT_DIR)/k8s/dockerfiles/apps-repo.Dockerfile" -t "$(K8S_REGISTRY)/ceerat-apps-repo:$(IMAGE_TAG)" "$(K8S_CONTEXT_DIR)"
	@$(DOCKER) build -f "$(ROOT_DIR)/k8s/dockerfiles/services-repo.Dockerfile" -t "$(K8S_REGISTRY)/ceerat-services-repo:$(IMAGE_TAG)" "$(K8S_CONTEXT_DIR)"

k8-push:
	@echo "Pushing Ceerat Kubernetes images to $(K8S_REGISTRY)"
	@$(DOCKER) push "$(K8S_REGISTRY)/ceerat-apps-repo:$(IMAGE_TAG)"
	@$(DOCKER) push "$(K8S_REGISTRY)/ceerat-services-repo:$(IMAGE_TAG)"

k8-render:
	@$(KUBECTL) kustomize "$(ROOT_DIR)/$(K8S_OVERLAY)" | sed -e 's#us-docker.pkg.dev/PROJECT_ID/ceerat#$(K8S_REGISTRY)#g' -e 's#:latest#:$(IMAGE_TAG)#g' -e 's#:dev#:$(IMAGE_TAG)#g' -e 's#:staging#:$(IMAGE_TAG)#g' -e 's#:prod#:$(IMAGE_TAG)#g'

k8-deploy: k8-build
	@if [ "$(PUSH)" = "true" ]; then \
		echo "Pushing Ceerat Kubernetes images to $(K8S_REGISTRY)"; \
		$(DOCKER) push "$(K8S_REGISTRY)/ceerat-apps-repo:$(IMAGE_TAG)"; \
		$(DOCKER) push "$(K8S_REGISTRY)/ceerat-services-repo:$(IMAGE_TAG)"; \
	fi
	@echo "Deploying $(K8S_OVERLAY) with image tag $(IMAGE_TAG)"
	@$(KUBECTL) kustomize "$(ROOT_DIR)/$(K8S_OVERLAY)" | sed -e 's#us-docker.pkg.dev/PROJECT_ID/ceerat#$(K8S_REGISTRY)#g' -e 's#:latest#:$(IMAGE_TAG)#g' -e 's#:dev#:$(IMAGE_TAG)#g' -e 's#:staging#:$(IMAGE_TAG)#g' -e 's#:prod#:$(IMAGE_TAG)#g' | $(KUBECTL) apply -f -
