---
title: Catálogo de scripts
description: Inventario de scripts, tareas, privilegios y documentación del repositorio
tags:
  - referencia
  - onboarding
---

# Catálogo de scripts

Este inventario se mantiene junto con los scripts. El validador documental comprueba que cada script ejecutable tenga una fila y un documento asociado.

## Cómo leer la tabla

- **sudo:** indica si el script puede solicitar o ejecutar privilegios elevados.
- **seguro:** indica si ofrece `--check`, `--plan` o `--dry-run`.
- **riesgo:** `bajo`, `medio` o `alto` según cambios externos, red, archivos o discos.
- Los documentos suplementarios no representan scripts ejecutables.

## Scripts

| Script | Plataforma | Tarea Just | sudo | Seguro | Riesgo | Documentación |
|---|---|---|---|---|---|---|
| `scripts/audio/create_retro_podcast_sounds.py` | macOS/Linux | — | no | — | bajo | [doc](audio/create_retro_podcast_sounds.md) |
| `scripts/backup/backup_thinkpad_recovery_linux.sh` | Linux | backup-thinkpad | sí | sí | alto | [doc](backup/backup_thinkpad_recovery_linux.md) |
| `scripts/backup/backup_thinkpad_restic_linux.sh` | Linux | backup-thinkpad-restic | no | sí | alto | [doc](backup/backup_thinkpad_restic_linux.md) |
| `scripts/dev/commons_deploy_verify_unix.sh` | macOS/Linux | — | no | — | medio | [doc](dev/commons_deploy_verify_unix.md) |
| `scripts/dev/deploy_configs_unix.sh` | macOS/Linux | deploy-configs | opcional | sí | alto | [doc](dev/deploy_configs_unix.md) |
| `scripts/dev/deploy_verify_unix.sh` | macOS/Linux | deploy-verify | no | sí | medio | [doc](dev/deploy_verify_unix.md) |
| `scripts/dev/disk_usage_linux.sh` | Linux | disk-usage | sí | no | medio | [doc](dev/disk_usage_linux.md) |
| `scripts/dev/jdtls_linux.sh` | Linux | — | no | — | bajo | [doc](dev/jdtls_linux.md) |
| `scripts/dev/md2pdf_unix.sh` | macOS/Linux | md2pdf | no | sí | bajo | [doc](dev/md2pdf_unix.md) |
| `scripts/dev/podman_cleanup_linux.sh` | Linux | podman-cleanup | no | sí | alto | [doc](dev/podman_cleanup_linux.md) |
| `scripts/dev/podman_overlay_watch_linux.sh` | Linux | podman-overlay-watch | no | sí | medio | [doc](dev/podman_overlay_watch_linux.md) |
| `scripts/dev/podman_recover_linux.sh` | Linux | podman-recover | no | sí | medio | [doc](dev/podman_recover_linux.md) |
| `scripts/dev/update_copilot_chat_linux.sh` | Linux | — | no | — | medio | [doc](dev/update_copilot_chat_linux.md) |
| `scripts/dev/update_copilot_linux.sh` | Linux | — | no | — | medio | [doc](dev/update_copilot_linux.md) |
| `scripts/dev/update_opencode_unix.sh` | macOS, Linux | curl, OpenCode | no | — | medio | [doc](dev/update_opencode_unix.md) |
| `scripts/dev/validate_script_docs.py` | macOS/Linux | validate-script-docs | no | sí | bajo | [doc](dev/validate_script_docs.md) |
| `scripts/display/hidpi_xorg_linux.sh` | Linux | — | opcional | sí | medio | [doc](display/hidpi_xorg_linux.md) |
| `scripts/display/screen_auto_edge_mirror_linux.sh` | Linux | — | no | — | medio | [doc](display/screen_auto_edge_mirror_linux.md) |
| `scripts/display/screen_auto_mirror_linux.sh` | Linux | — | no | — | medio | [doc](display/screen_auto_mirror_linux.md) |
| `scripts/display/screen_extend_auto_linux.sh` | Linux | — | no | — | medio | [doc](display/screen_extend_auto_linux.md) |
| `scripts/display/screen_mirror_linux.sh` | Linux | — | no | — | medio | [doc](display/screen_mirror_linux.md) |
| `scripts/display/screen_projector_linux.sh` | Linux | screen-projector | no | sí | medio | [doc](display/screen_projector_linux.md) |
| `scripts/hardware/autorotate_x1_yoga_linux.sh` | Linux | — | no | sí | medio | [doc](hardware/autorotate_x1_yoga_linux.md) |
| `scripts/hardware/configure_thinkpad_s2idle_linux.sh` | Linux | configure-thinkpad-s2idle | sí | sí | alto | [doc](hardware/configure_thinkpad_s2idle_linux.md) |
| `scripts/hardware/configure_fstrim_linux.sh` | Linux | configure-fstrim | sí | sí | medio | [doc](hardware/configure_fstrim_linux.md) |
| `scripts/hardware/configure_lid_suspend_linux.sh` | Linux | configure-lid-suspend | sí | no | medio | [doc](hardware/configure_lid_suspend_linux.md) |
| `scripts/hardware/configure_initramfs_compression_linux.sh` | Linux | configure-initramfs-compression | sí | sí | alto | [doc](hardware/configure_initramfs_compression_linux.md) |
| `scripts/hardware/configure_thinkpad_keyboard_linux.sh` | Linux | configure-thinkpad-keyboard | sí | sí | medio | [doc](hardware/configure_thinkpad_keyboard_linux.md) |
| `scripts/hardware/configure_tlp_battery_linux.sh` | Linux | configure-tlp-battery | sí | sí | medio | [doc](hardware/configure_tlp_battery_linux.md) |
| `scripts/hardware/notify_brightness_linux.sh` | Linux | — | no | — | bajo | [doc](hardware/notify_brightness_linux.md) |
| `scripts/hardware/notify_kbd_brightness_linux.sh` | Linux | — | no | — | bajo | [doc](hardware/notify_kbd_brightness_linux.md) |
| `scripts/hardware/notify_microphone_linux.sh` | Linux | — | no | — | bajo | [doc](hardware/notify_microphone_linux.md) |
| `scripts/hardware/notify_power_linux.sh` | Linux | — | no | — | bajo | [doc](hardware/notify_power_linux.md) |
| `scripts/hardware/notify_volume_linux.sh` | Linux | — | no | — | bajo | [doc](hardware/notify_volume_linux.md) |
| `scripts/hardware/power_control_linux.sh` | Linux | power-control | sí | sí | alto | [doc](hardware/power_control_linux.md) |
| `scripts/hardware/screensaver_toggle_linux.sh` | Linux | screensaver-toggle | no | sí | bajo | [doc](hardware/screensaver_toggle_linux.md) |
| `scripts/hardware/test_wacom_pen_linux.sh` | Linux | test-wacom-pen | opcional | sí | bajo | [doc](hardware/test_wacom_pen_linux.md) |
| `scripts/hardware/usb_mount_perms_linux.sh` | Linux | usb-perms | sí | sí | alto | [doc](hardware/usb_mount_perms_linux.md) |
| `scripts/install/configure_sudo_linux.sh` | Linux | configure-sudo | sí | sí | alto | [doc](install/configure_sudo_linux.md) |
| `scripts/install/create_usb_unix.sh` | macOS/Linux | create-usb | sí | sí | alto | [doc](install/create_usb_unix.md) |
| `scripts/install/enable_debian_repositories_linux.sh` | Linux | enable-debian-repositories | sí | sí | alto | [doc](install/enable_debian_repositories_linux.md) |
| `scripts/install/format_usb_unix.sh` | macOS/Linux | format-usb | sí | sí | alto | [doc](install/format_usb_unix.md) |
| `scripts/install/configure_java_mise_linux.sh` | Linux | configure-java-mise | no | sí | medio | [doc](install/configure_java_mise_linux.md) |
| `scripts/install/install_bash_reload_linux.sh` | Linux | install-bash-reload | no | sí | bajo | [doc](install/install_bash_reload_linux.md) |
| `scripts/install/install_dotfiles_unix.sh` | macOS/Linux | install-dotfiles | no | sí | medio | [doc](install/install_dotfiles_unix.md) |
| `scripts/install/install_eclipse_ide_linux.sh` | Linux | install-eclipse-ide | no | sí | medio | [doc](install/install_eclipse_ide_linux.md) |
| `scripts/install/install_ether_rules_mcp_unix.sh` | macOS/Linux | install-ether-rules-mcp | no | sí | medio | [doc](install/install_ether_rules_mcp_unix.md) |
| `scripts/install/install_firefox_mozilla_linux.sh` | Linux | install-firefox-mozilla | sí | sí | medio | [doc](install/install_firefox_mozilla_linux.md) |
| `scripts/install/install_github_cli_linux.sh` | Linux | install-github-cli | sí | sí | medio | [doc](install/install_github_cli_linux.md) |
| `scripts/install/install_java_runtime_linux.sh` | Linux | install-java-runtime | no | sí | medio | [doc](install/install_java_runtime_linux.md) |
| `scripts/install/install_node_runtime_linux.sh` | Linux | install-node-runtime | no | sí | medio | [doc](install/install_node_runtime_linux.md) |
| `scripts/install/install_build_runtime_linux.sh` | Linux | install-build-runtime | no | sí | medio | [doc](install/install_build_runtime_linux.md) |
| `scripts/install/reconcile_runtimes_linux.sh` | Linux | reconcile-runtimes | no | sí | alto | [doc](install/reconcile_runtimes_linux.md) |
| `scripts/install/runtime_registry_linux.sh` | Linux | — | no | — | bajo | [doc](install/runtime_registry_linux.md) |
| `scripts/install/install_mosh_tmux_kitty_unix.sh` | macOS/Linux | install-mosh-tmux-kitty | opcional | sí | medio | [doc](install/install_mosh_tmux_kitty_unix.md) |
| `scripts/install/install_runtime_switcher_linux.sh` | Linux | install-runtime-switcher | no | sí | bajo | [doc](install/install_runtime_switcher_linux.md) |
| `scripts/install/install_terminal_workstation_linux.sh` | Linux | install-terminal-workstation | sí | sí | medio | [doc](install/install_terminal_workstation_linux.md) |
| `scripts/install/install_security_lab_linux.sh` | Linux | install-security-lab | sí | sí | medio | [doc](install/install_security_lab_linux.md) |
| `scripts/install/install_android_tools_linux.sh` | Linux | install-android-tools | sí | sí | medio | [doc](install/install_android_tools_linux.md) |
| `scripts/install/install_firefoxos_ca_tools_linux.sh` | Linux | install-firefoxos-ca-tools | sí | sí | medio | [doc](install/install_firefoxos_ca_tools_linux.md) |
| `scripts/install/install_firefoxos_sms_bridge_linux.sh` | Linux | install-firefoxos-sms-bridge | sí | sí | medio | [doc](install/install_firefoxos_sms_bridge_linux.md) |
| `scripts/install/install_graphics_linux.sh` | Linux | install-graphics | sí | sí | medio | [doc](install/install_graphics_linux.md) |
| `scripts/install/install_office_linux.sh` | Linux | install-office | sí | sí | medio | [doc](install/install_office_linux.md) |
| `scripts/install/install_antivirus_linux.sh` | Linux | install-antivirus | sí | sí | medio | [doc](install/install_antivirus_linux.md) |
| `scripts/install/install_multimedia_linux.sh` | Linux | install-multimedia | sí | sí | medio | [doc](install/install_multimedia_linux.md) |
| `scripts/install/install_fonts_linux.sh` | Linux | install-fonts | sí | sí | medio | [doc](install/install_fonts_linux.md) |
| `scripts/install/install_clipboard_linux.sh` | Linux | install-clipboard | sí | sí | medio | [doc](install/install_clipboard_linux.md) |
| `scripts/install/install_screenshot_linux.sh` | Linux | install-screenshot | sí | sí | medio | [doc](install/install_screenshot_linux.md) |
| `scripts/install/install_printers_linux.sh` | Linux | install-printers | sí | sí | medio | [doc](install/install_printers_linux.md) |
| `scripts/install/configure_printers_linux.sh` | Linux | configure-printers, printer-test | sí | sí | medio | [doc](install/configure_printers_linux.md) |
| `scripts/install/install_ai_cli_linux.sh` | Linux | install-ai-cli | no | sí | medio | [doc](install/install_ai_cli_linux.md) |
| `scripts/install/install_age_gopass_linux.sh` | Linux | install-age-gopass, init-gopass-age | sí | sí | alto | [doc](install/install_age_gopass_linux.md) |
| `scripts/install/install_restic_backup_linux.sh` | Linux | install-restic-backup | sí | sí | medio | [doc](install/install_restic_backup_linux.md) |
| `scripts/install/configure_kvm_linux.sh` | Linux | configure-kvm | sí | sí | medio | [doc](install/configure_kvm_linux.md) |
| `scripts/install/audit_thinkpad_readiness_linux.sh` | Linux | audit-thinkpad | no | sí | bajo | [doc](install/audit_thinkpad_readiness_linux.md) |
| `scripts/install/install_thinkpad_backgrounds_linux.sh` | Linux | install-thinkpad-backgrounds | sí | sí | alto | [doc](install/install_thinkpad_backgrounds_linux.md) |
| `scripts/install/install_conky_linux.sh` | Linux | install-conky | sí | sí | medio | [doc](install/install_conky_linux.md) |
| `scripts/install/install_feh_linux.sh` | Linux | install-feh | sí | sí | bajo | [doc](install/install_feh_linux.md) |
| `scripts/install/install_ratmenu_linux.sh` | Linux | install-ratmenu | sí | sí | bajo | [doc](install/install_ratmenu_linux.md) |
| `scripts/install/install_eww_linux.sh` | Linux | install-eww | sí | sí | medio | [doc](install/install_eww_linux.md) |
| `scripts/install/install_i3lock_color_linux.sh` | Linux | install-i3lock-color | sí | sí | alto | [doc](install/install_i3lock_color_linux.md) |
| `scripts/install/install_rafex_control_panel_linux.sh` | Linux | install-rafex-control-panel | sí | sí | medio | [doc](install/install_rafex_control_panel_linux.md) |
| `scripts/install/install_picom_upstream_linux.sh` | Linux | install-picom-upstream | sí | sí | medio | [doc](install/install_picom_upstream_linux.md) |
| `scripts/install/install_vscodium_linux.sh` | Linux | install-vscodium | sí | sí | medio | [doc](install/install_vscodium_linux.md) |
| `scripts/install/install_rustdesk_linux.sh` | Linux | install-rustdesk | sí | sí | medio | [doc](install/install_rustdesk_linux.md) |
| `scripts/install/migrate_laptop_linux.sh` | Linux | migrate-laptop | sí | sí | alto | [doc](install/migrate_laptop_linux.md) |
| `scripts/install/scrape_eclipse_packages.py` | Linux | scrape-eclipse-packages | no | — | bajo | [doc](install/scrape_eclipse_packages.md) |
| `scripts/install/scrape_java_runtimes.py` | Linux | scrape-java-runtimes | no | — | bajo | [doc](install/scrape_java_runtimes.md) |
| `scripts/install/scrape_node_runtime.py` | Linux | — | no | — | bajo | [doc](install/scrape_node_runtime.md) |
| `scripts/install/scrape_build_runtime.py` | Linux | — | no | — | bajo | [doc](install/scrape_build_runtime.md) |
| `scripts/install/install_i3_laptop_controls_linux.sh` | Linux | install-i3-laptop-controls | sí | sí | medio | [doc](install/install_i3_laptop_controls_linux.md) |
| `scripts/install/install_kbd_brightness_policy_linux.sh` | Linux | install-kbd-brightness | sí | sí | alto | [doc](install/install_kbd_brightness_policy_linux.md) |
| `scripts/install/install_i3_gaps_linux.sh` | Linux | install-i3-gaps | sí | sí | medio | [doc](install/install_i3_gaps_linux.md) |
| `scripts/install/configure_thinkpad_xorg_dri3_linux.sh` | Linux | configure-thinkpad-xorg-dri3 | sí | sí | alto | [doc](install/configure_thinkpad_xorg_dri3_linux.md) |
| `scripts/install/install_openbox_profile_linux.sh` | Linux | install-openbox-profile | sí | sí | medio | [doc](install/install_openbox_profile_linux.md) |
| `scripts/install/install_i3_bar_profiles_linux.sh` | Linux | install-i3-bar-profiles | sí | sí | medio | [doc](install/install_i3_bar_profiles_linux.md) |
| `scripts/install/install_ufw_linux.sh` | Linux | install-ufw | sí | sí | alto | [doc](install/install_ufw_linux.md) |
| `scripts/install/harden_thinkpad_linux.sh` | Linux | harden-thinkpad | sí | sí | alto | [doc](install/harden_thinkpad_linux.md) |
| `scripts/install/setup_ssh_trust_unix.sh` | macOS/Linux | setup-ssh-trust | no | sí | alto | [doc](install/setup_ssh_trust_unix.md) |
| `scripts/macos/clean_apple_meta_macos.sh` | macOS | clean-apple-meta | no | sí | alto | [doc](macos/clean_apple_meta_macos.md) |
| `scripts/network/connect_nas_linux.sh` | Linux | connect-nas | sí | — | medio | [doc](network/connect_nas_linux.md) |
| `scripts/network/diag_iface_linux.sh` | Linux | diag-iface | sí | sí | medio | [doc](network/diag_iface_linux.md) |
| `scripts/network/install_wifi_polkit_linux.sh` | Linux | — | sí | — | alto | [doc](network/install_wifi_polkit_linux.md) |
| `scripts/network/myip_linux.sh` | Linux | myip | no | — | bajo | [doc](network/myip_linux.md) |
| `scripts/network/nm_force_ip_linux.sh` | Linux | nm-force-ip | opcional | sí | alto | [doc](network/nm_force_ip_linux.md) |
| `scripts/network/reconcile_networkmanager_linux.sh` | Linux | reconcile-networkmanager | sí | sí | alto | [doc](network/reconcile_networkmanager_linux.md) |
| `scripts/network/configure_wwan_oxxocel_linux.sh` | Linux | configure-wwan-oxxocel | sí | sí | medio | [doc](network/configure_wwan_oxxocel_linux.md) |
| `scripts/network/install_mdns_linux.sh` | Linux | install-mdns | sí | sí | medio | [doc](network/install_mdns_linux.md) |
| `scripts/network/wifi_connect_interactive_linux.sh` | Linux | wifi-connect-interactive | opcional | — | medio | [doc](network/wifi_connect_interactive_linux.md) |
| `scripts/network/wifi_connect_linux.sh` | Linux | wifi-connect | opcional | — | medio | [doc](network/wifi_connect_linux.md) |
| `scripts/network/wifi_off_linux.sh` | Linux | wifi-off | opcional | — | medio | [doc](network/wifi_off_linux.md) |
| `scripts/network/wifi_reset_linux.sh` | Linux | wifi-reset | sí | — | alto | [doc](network/wifi_reset_linux.md) |
| `scripts/network/wifi_scan_linux.sh` | Linux | wifi-scan | opcional | — | bajo | [doc](network/wifi_scan_linux.md) |
| `scripts/network/wifi_toggle_interface_linux.sh` | Linux | wifi-toggle-interface | opcional | — | medio | [doc](network/wifi_toggle_interface_linux.md) |
| `scripts/network/wifi_toggle_internal_linux.sh` | Linux | wifi-toggle-radio | opcional | — | medio | [doc](network/wifi_toggle_internal_linux.md) |
| `scripts/network/flight_mode_toggle_linux.sh` | Linux | — | no | — | medio | [doc](network/flight_mode_toggle_linux.md) |
| `scripts/network/wifi_toggle_linux.sh` | Linux | — | no | — | bajo | [doc](network/wifi_toggle_linux.md) |
| `scripts/system/i3_settings_menu_linux.sh` | Linux | — | no | — | bajo | [doc](system/i3_settings_menu_linux.md) |
| `scripts/system/rofi_search_linux.sh` | Linux | — | no | — | bajo | [doc](system/rofi_search_linux.md) |
| `scripts/system/theme_toggle_linux.sh` | Linux | theme-toggle | no | sí | bajo | [doc](system/theme_toggle_linux.md) |
| `scripts/system/generate_terminal_themes_linux.sh` | Linux | generate-terminal-themes | no | sí | bajo | [doc](system/generate_terminal_themes_linux.md) |
| `scripts/system/dunst_smart_start_linux.sh` | Linux | dunst-smart | no | sí | bajo | [doc](system/dunst_smart_start_linux.md) |
| `scripts/system/desktop_settings_menu_linux.sh` | Linux | desktop-settings-menu | no | — | bajo | [doc](system/desktop_settings_menu_linux.md) |
| `scripts/system/picom_toggle_linux.sh` | Linux | picom-toggle | no | sí | bajo | [doc](system/picom_toggle_linux.md) |
| `scripts/system/picom_debian_linux.sh` | Linux | picom-debian | no | sí | bajo | [doc](system/picom_debian_linux.md) |
| `scripts/system/tint2_status_linux.sh` | Linux | tint2-status | no | — | bajo | [doc](system/tint2_status_linux.md) |
| `scripts/system/i3_bar_profile_linux.sh` | Linux | i3-bar | no | sí | medio | [doc](system/i3_bar_profile_linux.md) |
| `scripts/system/rafex_i3_bar_runtime_linux.sh` | Linux | — | no | sí | medio | [doc](system/rafex_i3_bar_runtime_linux.md) |
| `scripts/system/scan_usb_clamav_linux.sh` | Linux | scan-usb | no | sí | medio | [doc](system/scan_usb_clamav_linux.md) |
| `scripts/system/scan_document_linux.sh` | Linux | scan-document | no | sí | medio | [doc](system/scan_document_linux.md) |
| `scripts/system/clipboard_menu_linux.sh` | Linux | clipboard-menu | no | sí | bajo | [doc](system/clipboard_menu_linux.md) |
| `scripts/system/screenshot_linux.sh` | Linux | screenshot | no | sí | medio | [doc](system/screenshot_linux.md) |
| `scripts/system/kbd_brightness_privileged_linux.sh` | Linux | — | sí | — | alto | [doc](system/kbd_brightness_privileged_linux.md) |
| `scripts/system/age_file_linux.sh` | Linux | age-file | no | sí | medio | [doc](system/age_file_linux.md) |
| `scripts/system/conky_status_linux.sh` | Linux | conky-status | no | — | bajo | [doc](system/conky_status_linux.md) |
| `scripts/system/set_wallpaper_linux.sh` | Linux | — | no | — | bajo | [doc](system/set_wallpaper_linux.md) |
| `scripts/system/rafex_ratmenu_linux.sh` | Linux | rafex-ratmenu | no | — | bajo | [doc](system/rafex_ratmenu_linux.md) |
| `scripts/system/eww_actions_linux.sh` | Linux | — | no | sí | medio | [doc](system/eww_actions_linux.md) |
| `scripts/system/eww_widgets_linux.sh` | Linux | eww-widgets | no | sí | bajo | [doc](system/eww_widgets_linux.md) |
| `scripts/system/lock_screen_linux.sh` | Linux | lock-screen | no | — | alto | [doc](system/lock_screen_linux.md) |
| `scripts/system/rafex_control_panel.py` | Linux | rafex-control-panel | no | — | medio | [doc](system/rafex_control_panel.md) |
| `scripts/system/android_tools_linux.sh` | Linux | android-tools | no | sí | medio | [doc](system/android_tools_linux.md) |
| `scripts/system/firefoxos_tools_linux.sh` | Linux | firefoxos-tools | no | sí | alto | [doc](system/firefoxos_tools_linux.md) |
| `scripts/system/firefoxos_ca_linux.sh` | Linux | firefoxos-ca | sí | sí | alto | [doc](system/firefoxos_ca_linux.md) |
| `scripts/system/firefoxos_flash_base_linux.sh` | Linux | firefoxos-flash-base | no | sí | alto | [doc](system/firefoxos_flash_base_linux.md) |
| `scripts/system/firefoxos_flash_nightly_linux.sh` | Linux | firefoxos-flash-nightly | no | sí | alto | [doc](system/firefoxos_flash_nightly_linux.md) |
| `scripts/system/firefoxos_hello_world_linux.sh` | Linux | firefoxos-hello-world | no | sí | bajo | [doc](system/firefoxos_hello_world_linux.md) |
| `scripts/system/firefoxos_sms_bridge_linux.sh` | Linux | firefoxos-sms | no | sí | medio | [doc](system/firefoxos_sms_bridge_linux.md) |

## Documentos suplementarios

- [Reglas polkit de Wi-Fi](network/wifi_polkit_rules.md): explica la política, no es un ejecutable.
- [Metadatos de macOS](macos/Metadatos.md): referencia conceptual para limpieza de volúmenes.

## Hallazgos

- `deploy_configs_unix.sh` documenta una interfaz cuyo orden de argumentos no coincide completamente con la tarea `deploy-configs`.
- `commons_deploy_verify_unix.sh` no tiene tarea Just dedicada.
- Algunos scripts simples no exponen `--help`; sus modos se describen directamente en su documento.
- Los scripts con cambios de sistema o disco están marcados como riesgo alto y requieren leer sus protecciones antes de aplicar.
