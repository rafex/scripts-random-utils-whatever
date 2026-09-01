# Crear y verificar un respaldo seguro de la ThinkPad en SSD externo.
# Uso: just backup-thinkpad --check | --plan | --apply
backup-thinkpad *args:
    bash scripts/backup/backup_thinkpad_recovery_linux.sh {{args}}

# Crear respaldos Restic cifrados e incrementales; no monta ni formatea discos.
# Uso: just backup-thinkpad-restic --check|--plan|--backup|--status
backup-thinkpad-restic *args:
    bash scripts/backup/backup_thinkpad_restic_linux.sh {{args}}
