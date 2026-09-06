# =============================================================================
# just/macos.just — Tareas para scripts/macos/
# =============================================================================

# Limpiar metadatos Apple (._*, .DS_Store, xattrs) en un volumen o directorio
# Uso: just clean-apple-meta --path /Volumes/nas/datos
# Uso: just clean-apple-meta --path /Volumes/nas/datos --dry-run
clean-apple-meta *args:
    bash scripts/macos/clean_apple_meta_macos.sh {{args}}

# Configurar Alacritty oscuro en macOS con respaldo y rollback; no instala la app.
# Uso: just configure-alacritty-macos --check | --plan | --apply | --status | --rollback
configure-alacritty-macos *args:
    bash scripts/macos/configure_alacritty_macos.sh {{args}}
