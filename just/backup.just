# Crear y verificar un respaldo seguro de la ThinkPad en SSD externo.
# Uso: just backup-thinkpad --check | --plan | --apply
backup-thinkpad *args:
    bash scripts/backup/backup_thinkpad_recovery_linux.sh {{args}}

# Crear respaldos Restic cifrados e incrementales; no monta ni formatea discos.
# Uso: just backup-thinkpad-restic --check|--plan|--backup|--status
backup-thinkpad-restic *args:
    bash scripts/backup/backup_thinkpad_restic_linux.sh {{args}}

# Sincronizar ~/.age hacia una ThinkPad sin borrar archivos remotos.
# Uso: just sync-age-to-thinkpad --check|--plan|--status|--apply --target <ssh>
sync-age-to-thinkpad *args:
    bash scripts/backup/sync_age_to_thinkpad_unix.sh {{args}}

# Sincronizar discoExterno de rafex al USB local del TNAS sin borrar el origen.
# Uso: just sync-tnas-usb --dry-run|--verify
sync-tnas-usb *args:
    bash scripts/backup/sync_rafex_disco_externo_to_usbshare1_linux.sh {{args}}
