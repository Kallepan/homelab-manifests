SHELL := /bin/sh

KUSTOMIZE ?= kustomize
APPS_DIR ?= apps

KUSTOMIZATION_DIRS := $(shell find $(APPS_DIR) -type f -name kustomization.yaml -exec dirname {} \; | sort)

.PHONY: all help list-kustomizations render-apps check-apps

.DEFAULT_GOAL := all

all: check-apps render-apps

help:
	@echo "Targets:"
	@echo "  make list-kustomizations  # List all discovered kustomization directories"
	@echo "  make render-apps          # Render all kustomizations under apps/"
	@echo "  make check-apps           # Render all kustomizations and print concise OK/FAIL summary"

list-kustomizations:
	@printf '%s\n' $(KUSTOMIZATION_DIRS)

render-apps:
	@set -e; \
	if [ -z "$(KUSTOMIZATION_DIRS)" ]; then \
		echo "No kustomizations found under $(APPS_DIR)/"; \
		exit 0; \
	fi; \
	for d in $(KUSTOMIZATION_DIRS); do \
		echo "==> Rendering $$d"; \
		$(KUSTOMIZE) build "$$d" >/dev/null; \
	done; \
	echo "All kustomizations rendered successfully."

check-apps:
	@set -e; \
	if [ -z "$(KUSTOMIZATION_DIRS)" ]; then \
		echo "No kustomizations found under $(APPS_DIR)/"; \
		exit 0; \
	fi; \
	failed=0; \
	for d in $(KUSTOMIZATION_DIRS); do \
		if $(KUSTOMIZE) build "$$d" >/dev/null 2>&1; then \
			echo "[OK]   $$d"; \
		else \
			echo "[FAIL] $$d"; \
			failed=1; \
		fi; \
	done; \
	if [ $$failed -ne 0 ]; then \
		echo "One or more kustomizations failed."; \
		exit 1; \
	fi; \
	echo "All kustomizations passed."
