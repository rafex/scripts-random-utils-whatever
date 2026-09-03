# =============================================================================
# make/checksums.mk — Generación y verificación de SHA256SUMS
# =============================================================================

SCRIPTS          := $(shell find scripts/ -name '*.sh')
DOTFILES_SCRIPTS := $(shell find dotfiles/ -name '*.sh' -o -name 'install.sh' 2>/dev/null)
CONTAINER_FILES  := $(shell find containers/ -type f 2>/dev/null)
ALL_CHECKSUM_FILES := $(SCRIPTS) $(DOTFILES_SCRIPTS) $(CONTAINER_FILES)
CHECKSUMS_FILE   := SHA256SUMS

.PHONY: checksums verify-checksums

checksums: ## Generar SHA256SUMS con hashes de scripts y artefactos versionados
	@echo "  Generando $(CHECKSUMS_FILE)..."
	@sha256sum $(ALL_CHECKSUM_FILES) | sort -k2 > $(CHECKSUMS_FILE)
	@echo "  \033[32m✓ $(CHECKSUMS_FILE)\033[0m ($$(wc -l < $(CHECKSUMS_FILE)) archivos y artefactos)"

verify-checksums: ## Verificar que los scripts coinciden con SHA256SUMS
	@if [ ! -f $(CHECKSUMS_FILE) ]; then \
		echo "  \033[33m⚠  $(CHECKSUMS_FILE) no existe. Ejecuta: make checksums\033[0m"; \
		exit 0; \
	fi
	@sha256sum -c $(CHECKSUMS_FILE) --quiet 2>/dev/null && \
		echo "  \033[32m✓ Checksums OK — todos los scripts coinciden.\033[0m" || \
		{ echo "  \033[31m✗ Discrepancia detectada. Ejecuta: make checksums\033[0m"; exit 1; }
