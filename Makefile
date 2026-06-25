.DEFAULT_GOAL := help
.PHONY: help setup up down restart logs ps psql seed reseed reset clean lint \
        traffic inject failures watch reset-schema land test

SHELL := /bin/bash
COMPOSE := docker compose

ifneq (,$(wildcard .env))
include .env
export
endif
RUN := uv run python -m src.seed.seed
GEN := uv run python -m src.gen.cli

CUSTOMERS ?= 500
PRODUCTS  ?= 200
ORDERS    ?= 5000
SEED      ?= 42
FAILURE   ?= schema_drift
TRAFFIC   ?= 200

# Chaos injection is SILENT by default (no injected_incidents row). Pass RECORD=1
# to write the ground-truth ledger entry: `make inject FAILURE=schema_drift RECORD=1`.
RECORD    ?=
RECORD_FLAG := $(if $(RECORD),--record,)

help:
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

setup: ## Install Python dependencies with uv
	uv sync

up: ## Start PostgreSQL (schema auto-applied on first boot)
	$(COMPOSE) up -d
	@echo "Waiting for PostgreSQL to be healthy..."
	@until [ "$$($(COMPOSE) ps -q postgres | xargs docker inspect -f '{{.State.Health.Status}}')" = "healthy" ]; do sleep 1; done
	@echo "PostgreSQL is ready."

down: ## Stop containers (keep data)
	$(COMPOSE) down

restart: down up ## Restart the stack

logs: ## Tail PostgreSQL logs
	$(COMPOSE) logs -f postgres

ps: ## Show container status
	$(COMPOSE) ps

psql: ## Open a psql shell against the source database
	$(COMPOSE) exec postgres psql -U $${POSTGRES_USER:-postgres} -d $${POSTGRES_DB:-ecommerce}

seed: ## Generate clean correlated data (CUSTOMERS/PRODUCTS/ORDERS/SEED overridable)
	$(RUN) --customers $(CUSTOMERS) --products $(PRODUCTS) --orders $(ORDERS) --seed $(SEED)

reseed: ## Truncate then regenerate a fresh clean dataset
	$(RUN) --customers $(CUSTOMERS) --products $(PRODUCTS) --orders $(ORDERS) --seed $(SEED) --truncate

reset: down clean up ## Destroy data volume and recreate an empty database

clean: ## Remove containers and the data volume
	$(COMPOSE) down -v

failures: ## List available failure modes
	$(GEN) list

traffic: ## Insert normal orders (TRAFFIC=count)
	$(GEN) traffic --orders $(TRAFFIC)

inject: ## Inject one failure mode SILENTLY (FAILURE=schema_drift); add RECORD=1 to log the ledger
	$(GEN) inject $(FAILURE) $(RECORD_FLAG)

reset-schema: ## Revert schema drift (user_id -> customer_id)
	$(GEN) reset-schema

watch: ## Stream traffic and inject random failures SILENTLY (Ctrl-C to stop); add RECORD=1 to log the ledger
	$(GEN) watch $(RECORD_FLAG)

land: ## Land Postgres into DuckDB via ATTACH (Postgres -> raw.* in the warehouse)
	uv run python -m src.transition.cli land

test: ## Run the pytest suite (no tests yet — added with the dbt/MCP build)
	uv run pytest --no-header -q || [ $$? -eq 5 ]

lint: ## Lint the Python code with ruff
	uv run ruff check src
