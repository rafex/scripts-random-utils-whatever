# =============================================================================
# just/network.just — Tareas para scripts/network/
# =============================================================================

# Diagnostica y fuerza la obtención de IP en una interfaz de red
# Uso: just nm-force-ip enp1s0f0 --check | just nm-force-ip enp1s0f0 --dhcp
nm-force-ip *args:
    bash scripts/network/nm_force_ip_linux.sh {{args}}

# Conectar a red WiFi (interactivo, con selección de BSSID)
# Uso: just wifi-connect
wifi-connect *args:
    bash scripts/network/wifi_connect_linux.sh {{args}}

# Conectar a red WiFi (interactivo, selecciona red de lista)
# Uso: just wifi-connect-interactive
wifi-connect-interactive *args:
    bash scripts/network/wifi_connect_interactive_linux.sh {{args}}

# Escanear redes WiFi
# Uso: just wifi-scan
wifi-scan *args:
    bash scripts/network/wifi_scan_linux.sh {{args}}

# Apagar WiFi
# Uso: just wifi-off
wifi-off *args:
    bash scripts/network/wifi_off_linux.sh {{args}}

# Reiniciar driver WiFi (wl)
# Uso: just wifi-reset
wifi-reset *args:
    bash scripts/network/wifi_reset_linux.sh {{args}}

# Alternar entre WiFi interno y USB
# Uso: just wifi-toggle-interface
wifi-toggle-interface *args:
    bash scripts/network/wifi_toggle_interface_linux.sh {{args}}

# Alternar WiFi on/off (radio)
# Uso: just wifi-toggle-radio
wifi-toggle-radio *args:
    bash scripts/network/wifi_toggle_internal_linux.sh {{args}}

# Mostrar IP pública
# Uso: just myip
myip *args:
    bash scripts/network/myip_linux.sh {{args}}

# Conectar a NAS
# Uso: just connect-nas
connect-nas *args:
    bash scripts/network/connect_nas_linux.sh {{args}}
