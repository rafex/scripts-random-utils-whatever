# =============================================================================
# just/macos.just — Tareas para scripts/macos/
# =============================================================================

# Limpiar metadatos Apple (._*, .DS_Store, xattrs) en un volumen o directorio
# Uso: just clean-apple-meta --path /Volumes/nas/datos
# Uso: just clean-apple-meta --path /Volumes/nas/datos --dry-run
clean-apple-meta *args:
    bash scripts/macos/clean_apple_meta_macos.sh {{args}}
