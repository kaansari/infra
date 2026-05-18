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

.PHONY: all build-customer-ui start-customer-ui stop-customer-ui build-admin-ui start-admin-ui stop-admin-ui start-stack stop-stack status-stack ensure-dirs

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
		CEERAT_ENV="development" \
		"$(CUSTOMER_BIN)" </dev/null >>"$(CUSTOMER_LOG)" 2>&1 &
	@echo $$! >"$(CUSTOMER_PID)"

stop-customer-ui:
	@if [ -f "$(CUSTOMER_PID)" ]; then \
		pid=$$(cat "$(CUSTOMER_PID)"); \
		if kill -0 $$pid >/dev/null 2>&1; then \
			echo "Stopping customer UI (pid $$pid)"; \
			kill $$pid || true; \
		else \
			echo "Customer UI not running"; \
		fi; \
		rm -f "$(CUSTOMER_PID)"; \
	else \
		echo "Customer PID file not found: $(CUSTOMER_PID)"; \
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
