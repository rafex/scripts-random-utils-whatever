# =============================================================================
# make/check.mk — Verificación de scripts
# =============================================================================

SCRIPTS := $(shell find scripts/ -name '*.sh')

.PHONY: check check-syntax shellcheck

check: check-syntax verify-checksums docs-check ## Ejecutar todas las verificaciones de código

check-syntax: ## Verificar sintaxis bash de todos los scripts
	@echo "  Verificando sintaxis bash..."
	@errors=0; \
	for f in $(SCRIPTS); do \
		bash -n "$$f" 2>&1 && echo "  \033[32m✓\033[0m $$f" || { echo "  \033[31m✗\033[0m $$f"; errors=$$((errors+1)); }; \
	done; \
	if [ $$errors -gt 0 ]; then \
		echo ""; \
		echo "  \033[31mError: $$errors archivo(s) con errores de sintaxis.\033[0m"; \
		exit 1; \
	else \
		echo ""; \
		echo "  \033[32mSintaxis OK — todos los scripts válidos.\033[0m"; \
	fi

shellcheck: ## Verificar scripts con shellcheck (requiere shellcheck instalado)
	@command -v shellcheck >/dev/null 2>&1 || { echo "  \033[31mError: shellcheck no está instalado.\033[0m"; exit 1; }
	@echo "  Ejecutando shellcheck..."
	@shellcheck $(SCRIPTS) && echo "  \033[32mShellcheck OK.\033[0m"
