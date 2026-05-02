# =============================================================================
# make/dist.mk — Empaquetado y distribución
# =============================================================================

DIST_DIR ?= dist
VERSION  ?= dev
ARCHIVE  := $(DIST_DIR)/scripts-$(VERSION).tar.gz

.PHONY: dist clean

dist: check ## Empaquetar scripts en un archivo distribuible (requiere: make check)
	@mkdir -p $(DIST_DIR)
	@echo "  Empaquetando scripts → $(ARCHIVE)"
	@tar -czf $(ARCHIVE) \
		--exclude='.git' \
		--exclude='$(DIST_DIR)' \
		scripts/ docs/ README.md LICENSE
	@echo "  \033[32m✓ Paquete generado: $(ARCHIVE)\033[0m"

clean: ## Eliminar artefactos de build
	@echo "  Limpiando $(DIST_DIR)/..."
	@rm -rf $(DIST_DIR)
	@echo "  \033[32m✓ Limpieza completa.\033[0m"
