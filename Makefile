.PHONY: help lint lint-shell lint-yaml build build-relay build-mtproto test \
       smoke-test install pre-commit setup clean

# Default target
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ============================================================================
# Linting
# ============================================================================

lint: lint-shell lint-yaml ## Run all linters

lint-shell: ## Lint shell scripts with shellcheck
	@echo "==> Linting shell scripts..."
	@shellcheck -x -s bash install.sh renew-cert.sh tproxy-server/deploy/*.sh

lint-yaml: ## Lint YAML files
	@echo "==> Linting YAML files..."
	@yamllint -d "{extends: default, rules: {line-length: {max: 200}, truthy: disable}}" \
		docker-compose.yml .github/workflows/*.yml

# ============================================================================
# Build
# ============================================================================

build: build-relay build-mtproto ## Build all Docker images

build-relay: ## Build relay image
	@echo "==> Building relay image..."
	@docker build -t ozyab/tg-proxy-relay:local .

build-mtproto: ## Build mtproxy image
	@echo "==> Building mtproxy image..."
	@docker build -t ozyab/tg-proxy-mtproto:local mtproxy/

# ============================================================================
# Test
# ============================================================================

test: lint smoke-test ## Run all tests

smoke-test: ## Run smoke tests
	@echo "==> Running smoke tests..."
	@docker build -t tg-proxy-relay:test .
	@docker run --rm -u 0 tg-proxy-relay:test --help
	@echo "==> Smoke tests passed!"

# ============================================================================
# Development
# ============================================================================

setup: ## Set up development environment
	@echo "==> Installing pre-commit..."
	@pip install pre-commit
	@pre-commit install --install-hooks
	@echo "==> Done! Pre-commit hooks installed."

pre-commit: ## Run pre-commit on all files
	@pre-commit run --all-files

# ============================================================================
# Docker Compose
# ============================================================================

up: ## Start all services
	@docker compose up -d

down: ## Stop all services
	@docker compose down

logs: ## Show logs
	@docker compose logs -f

ps: ## Show service status
	@docker compose ps

health: ## Check health endpoints
	@echo "==> Checking health endpoints..."
	@curl -fsS http://127.0.0.1:8081/healthz && echo " OK" || echo " FAIL"
	@curl -fsS http://127.0.0.1:8081/readyz && echo " OK" || echo " FAIL"
	@curl -fsS http://127.0.0.1:8081/metrics && echo " OK" || echo " FAIL"

# ============================================================================
# Cleanup
# ============================================================================

clean: ## Clean up Docker resources
	@echo "==> Cleaning up..."
	@docker compose down -v --remove-orphans 2>/dev/null || true
	@docker image prune -f
	@echo "==> Done!"
