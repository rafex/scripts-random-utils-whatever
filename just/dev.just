# =============================================================================
# just/dev.just — Tareas para scripts/dev/
# =============================================================================

# Convierte Markdown a PDF con pandoc + weasyprint (profesional, estilo libro)
# Uso: just md2pdf -f doc.md -t "Título" | just md2pdf (procesa todos los .md en input/)
md2pdf *args:
    bash scripts/dev/md2pdf_unix.sh {{args}}
