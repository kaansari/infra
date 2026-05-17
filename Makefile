ROOT_DIR := $(shell cd $(dir $(realpath $(firstword $(MAKEFILE_LIST)))) && pwd)
BIN_DIR := $(ROOT_DIR)/bin
RUN_DIR := $(ROOT_DIR)/.run
LOG_DIR := $(ROOT_DIR)/logs
CUSTOMER_PORT ?= 3005
CUSTOMER_BIN := $(BIN_DIR)/ceerat-customer-ui
CUSTOMER_LOG := $(LOG_DIR)/customer-ui.log
CUSTOMER_PID := $(RUN_DIR)/customer-ui.pid

.PHONY: all build-customer-ui start-customer-ui stop-customer-ui ensure-dirs

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
	@nohup env \
		PORT="$(CUSTOMER_PORT)" \
		CEERAT_API_BASE_URL="localhost:50051" \
		CEERAT_AGENT_BASE_URL="http://localhost:8088" \
		CEERAT_ENV="development" \
		"$(CUSTOMER_BIN)" >>"$(CUSTOMER_LOG)" 2>&1 &
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
