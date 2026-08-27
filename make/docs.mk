# =============================================================================
# make/docs.mk — Construcción y validación del sitio MkDocs
# =============================================================================

MKDOCS_CONFIG ?= .config/mkdocs/mkdocs.yml
MKDOCS_REQUIREMENTS ?= .config/mkdocs/requirements.txt

.PHONY: docs serve docs-check validate-script-docs

validate-script-docs: ## Validar cobertura, frontmatter, secciones y enlaces
	@python3 scripts/dev/validate_script_docs.py

docs-check: validate-script-docs ## Validar documentación y construir el sitio estrictamente
	@command -v mkdocs >/dev/null 2>&1 || { echo "  Error: mkdocs no está instalado. Usa: python3 -m pip install -r $(MKDOCS_REQUIREMENTS)"; exit 1; }
	@mkdocs build --strict -f $(MKDOCS_CONFIG)
	@if command -v markdownlint-cli2 >/dev/null 2>&1; then markdownlint-cli2 'docs/**/*.md'; else echo "  Aviso: markdownlint-cli2 no está instalado; se omite lint Markdown."; fi

docs: docs-check ## Construir el sitio MkDocs Material en site/
	@echo "  Sitio generado en site/"

serve: ## Servir la documentación localmente con MkDocs
	@command -v mkdocs >/dev/null 2>&1 || { echo "  Error: mkdocs no está instalado. Usa: python3 -m pip install -r $(MKDOCS_REQUIREMENTS)"; exit 1; }
	@mkdocs serve -f $(MKDOCS_CONFIG)
