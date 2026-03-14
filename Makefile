# =============================================================================
# Makefile — aws-eks-balance-service-demo
# =============================================================================

REPO_ROOT := $(shell pwd)
PROTO_PATH := $(REPO_ROOT)/proto
PYTHONPATH_WITH_PROTO := $(PROTO_PATH):$(PROTO_PATH)/generated:$(PYTHONPATH)

SERVICE_DIR := apps/balance-service
GATEWAY_DIR := apps/balance-gateway

.DEFAULT_GOAL := help

ECR_REGISTRY = 456102076320.dkr.ecr.us-east-1.amazonaws.com
ECR_SERVICE   = balance-dev-balance-service
ECR_GATEWAY   = balance-dev-balance-gateway

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------
.PHONY: help
help:
	@echo ""
	@echo "  aws-eks-balance-service-demo"
	@echo "  ============================="
	@echo ""
	@echo "  Proto"
	@echo "    make proto              Generate gRPC Python stubs from balance.proto"
	@echo ""
	@echo "  Dependencies"
	@echo "    make install            Install dependencies for both apps"
	@echo "    make install-service    Install dependencies for balance-service"
	@echo "    make install-gateway    Install dependencies for balance-gateway"
	@echo ""
	@echo "  Run (local)"
	@echo "    make run-service        Start balance-service gRPC server (port 50051)"
	@echo "    make run-gateway        Start balance-gateway FastAPI server (port 8000)"
	@echo ""
	@echo "  Docker"
	@echo "    make docker-build       Build Docker images for both apps"
	@echo "    make docker-run         Run both apps via Docker (requires images built)"
	@echo "    make docker-stop        Stop and remove Docker containers"
	@echo ""
	@echo "  Utilities"
	@echo "    make clean              Remove virtualenvs and generated proto files"
	@echo ""

.PHONY: docker-setup
docker-setup:
	@echo "[docker] Setting up buildx multiplatform builder..."
	-docker buildx create --name multiplatform --use
	docker buildx use multiplatform

# -----------------------------------------------------------------------------
# Proto
# -----------------------------------------------------------------------------
.PHONY: proto
proto:
	@echo "[proto] Generating gRPC stubs..."
	cd $(SERVICE_DIR) && poetry run bash ../../scripts/generate_proto.sh

# -----------------------------------------------------------------------------
# Install
# -----------------------------------------------------------------------------
.PHONY: install
install: install-service install-gateway

.PHONY: install-service
install-service:
	@echo "[install] balance-service..."
	cd $(SERVICE_DIR) && poetry install

.PHONY: install-gateway
install-gateway:
	@echo "[install] balance-gateway..."
	cd $(GATEWAY_DIR) && poetry install

# -----------------------------------------------------------------------------
# Run (local)
# -----------------------------------------------------------------------------
.PHONY: run-service
run-service:
	@echo "[run] Starting balance-service on port 50051..."
	cd $(SERVICE_DIR) && PYTHONPATH=$(PYTHONPATH_WITH_PROTO) poetry run python app/main.py

.PHONY: run-gateway
run-gateway:
	@echo "[run] Starting balance-gateway on port 8000..."
	cd $(GATEWAY_DIR) && PYTHONPATH=$(PYTHONPATH_WITH_PROTO) poetry run python app/main.py

# -----------------------------------------------------------------------------
# Docker
# -----------------------------------------------------------------------------
.PHONY: docker-build
docker-build:
	@echo "[docker] Building balance-service..."
	docker build -t balance-service:local -f apps/balance-service/Dockerfile .
	@echo "[docker] Building balance-gateway..."
	docker build -t balance-gateway:local -f apps/balance-gateway/Dockerfile .

.PHONY: docker-run
docker-run:
	@echo "[docker] Creating network..."
	docker network create balance-net 2>/dev/null || true
	@echo "[docker] Starting balance-service..."
	docker run -d --name balance-service --network balance-net -p 50051:50051 balance-service:local
	@echo "[docker] Starting balance-gateway..."
	docker run -d --name balance-gateway --network balance-net -p 8000:8000 \
		-e BALANCE_SERVICE_ADDRESS=balance-service:50051 \
		balance-gateway:local
	@echo "[docker] Services running:"
	@echo "  balance-gateway → http://localhost:8000"
	@echo "  balance-service → localhost:50051 (internal)"

.PHONY: docker-stop
docker-stop:
	@echo "[docker] Stopping containers..."
	docker rm -f balance-service balance-gateway 2>/dev/null || true
	docker network rm balance-net 2>/dev/null || true
	@echo "[docker] Done."

.PHONY: docker-push
docker-push: docker-setup
	@echo "[docker] Building and pushing balance-service (multiplatform)..."
	docker buildx build \
		--platform linux/amd64,linux/arm64 \
		-t $(ECR_REGISTRY)/$(ECR_SERVICE):latest \
		-f apps/balance-service/Dockerfile \
		--push .
	@echo "[docker] Building and pushing balance-gateway (multiplatform)..."
	docker buildx build \
		--platform linux/amd64,linux/arm64 \
		-t $(ECR_REGISTRY)/$(ECR_GATEWAY):latest \
		-f apps/balance-gateway/Dockerfile \
		--push .
	
# -----------------------------------------------------------------------------
# Clean
# -----------------------------------------------------------------------------
.PHONY: clean
clean:
	@echo "[clean] Removing virtualenvs..."
	cd $(SERVICE_DIR) && poetry env remove --all 2>/dev/null || true
	cd $(GATEWAY_DIR) && poetry env remove --all 2>/dev/null || true
	@echo "[clean] Removing generated proto files..."
	rm -rf proto/generated
	@echo "[clean] Done."