# ── md2pdf ────────────────────────────────────────────────────────────────────

# Convierte Markdown a PDF con pandoc + weasyprint/xelatex.
# Temas: podcast (sans-serif cálido) y academic (serif formal).
# Auto-detecta CSS local, título YAML, fallback de motor e idempotencia.
# Uso: just md2pdf -f doc.md --theme podcast | just md2pdf -i ./podcast
md2pdf *args:
    bash scripts/dev/md2pdf_unix.sh {{args}}

# ── disk-usage ─────────────────────────────────────────────────────────────────

# Diagnostica qué llena el disco con sudo, genera REPORTE.md con análisis automático
# Uso: just disk-usage | just disk-usage -p /var -t 10M --top 30
disk-usage *args:
    bash scripts/dev/disk_usage_linux.sh {{args}}

# ── podman-cleanup ─────────────────────────────────────────────────────────────

# Limpia almacenamiento de Podman/Docker por niveles (0=análisis, 5=nuclear)
# Uso: just podman-cleanup --analyze | just podman-cleanup -l 2 | just podman-cleanup -l 4 --yes
podman-cleanup *args:
    bash scripts/dev/podman_cleanup_linux.sh {{args}}

# ── deploy + verify ───────────────────────────────────────────────────────────

# Deploy + verify todos los scripts mapeados a un host
# Uso: just deploy-verify bastion-usb-wifi
deploy-verify host:
    bash scripts/dev/deploy_verify_unix.sh --deploy-verify {{host}}

# Solo verificar scripts en un host (sin deploy)
# Uso: just verify-remote bastion-usb-wifi
verify-remote host:
    bash scripts/dev/deploy_verify_unix.sh --verify {{host}}

# Verificar todos los hosts en paralelo
verify-all:
    bash scripts/dev/deploy_verify_unix.sh --verify-all

# Listar hosts y scripts configurados
deploy-list:
    bash scripts/dev/deploy_verify_unix.sh --list

# Deploy + verify configs de un perfil a un host
# Uso: just deploy-configs macbook-pro-late2012 192.168.3.177
deploy-configs profile host *args:
    bash scripts/dev/deploy_configs_unix.sh --deploy-verify {{profile}} {{host}} {{args}}

# Listar perfiles de dotfiles
deploy-profiles:
    bash scripts/dev/deploy_configs_unix.sh --list-profiles

# Generar SHA256SUMS
checksums:
    make checksums
