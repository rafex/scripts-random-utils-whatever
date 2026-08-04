# =============================================================================
# Makefile — Builder
# Responsabilidad: verificación, empaquetado y distribución de scripts.
# NO ejecuta scripts directamente. Para eso usar: just
# =============================================================================

DIST_DIR := dist
VERSION  ?= dev

include make/check.mk
include make/dist.mk
include make/checksums.mk

.DEFAULT_GOAL := help

.PHONY: help
help: ## Mostrar esta ayuda
	@echo ""
	@echo "  Builder — targets disponibles:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
