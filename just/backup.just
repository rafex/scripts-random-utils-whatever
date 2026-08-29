# Crear y verificar un respaldo seguro de la ThinkPad en SSD externo.
# Uso: just backup-thinkpad --check | --plan | --apply
backup-thinkpad *args:
    bash scripts/backup/backup_thinkpad_recovery_linux.sh {{args}}
