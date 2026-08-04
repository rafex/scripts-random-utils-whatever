# ── md2pdf ────────────────────────────────────────────────────────────────────

# Convierte Markdown a PDF con pandoc + weasyprint (profesional, estilo libro)
# Uso: just md2pdf -f doc.md -t "Título" | just md2pdf (procesa todos los .md en input/)
md2pdf *args:
    bash scripts/dev/md2pdf_unix.sh {{args}}

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
