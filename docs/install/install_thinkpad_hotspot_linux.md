---
title: install_thinkpad_hotspot_linux.sh
description: Preparar el perfil visible THINKPAD_RAFEX en NetworkManager
tags:
  - red
  - thinkpad
---

# install_thinkpad_hotspot_linux.sh

Prepara un perfil NetworkManager independiente para compartir una conexión
WWAN mediante el hotspot visible `THINKPAD_RAFEX`.

- **Ruta:** `scripts/install/install_thinkpad_hotspot_linux.sh`
- **SO requerido:** Linux (Debian y derivados)
- **Dependencias:** `NetworkManager`, `nmcli`, `iw`, `rfkill`, `sudo` solo para APT

## Índice
## Requisitos
## Uso
## Opciones
## Variables de entorno
## Ejemplos
## Protecciones de seguridad
## Fallos conocidos
## Changelog

## Requisitos

NetworkManager debe estar activo, con una interfaz Wi-Fi administrada y modo AP
disponible. La clave WPA2 se introduce de forma interactiva y oculta; no se
incluye en el repositorio ni en los argumentos del proceso.

## Uso

```bash
just install-thinkpad-hotspot --check
just install-thinkpad-hotspot --set-key
just install-thinkpad-hotspot --apply
```

`--apply` prepara el perfil, pero no inicia el punto de acceso. La clave queda
en `~/.config/rafex/thinkpad-hotspot.conf`, con permisos `0600`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba dependencias, NetworkManager, Wi-Fi y archivo de clave. |
| `--plan` | `--dry-run` | Muestra el plan sin instalar paquetes ni crear perfiles. |
| `--set-key` | — | Solicita y guarda la clave WPA2 localmente, sin mostrarla. |
| `--apply` | — | Instala `iw`/`rfkill` si faltan y crea o actualiza el perfil. |
| `--status` | — | Muestra el estado del perfil y de la clave sin revelarla. |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `XDG_CONFIG_HOME` | Cambia la raíz del archivo privado de configuración. |
| `XDG_STATE_HOME` | Cambia la raíz del estado local del perfil. |

## Ejemplos

```bash
just install-thinkpad-hotspot --check
just install-thinkpad-hotspot --plan
just install-thinkpad-hotspot --set-key
just install-thinkpad-hotspot --apply
just install-thinkpad-hotspot --status
```

## Protecciones de seguridad

- La clave se solicita sin eco, se confirma y se guarda en un archivo `0600` bajo un directorio `0700`.
- Rechaza claves fuera de 8-63 caracteres ASCII imprimibles y no las muestra.
- El perfil usa WPA2-PSK, `autoconnect=false` y permisos para el usuario actual.
- No inicia el hotspot, no altera el perfil OXXO Cel ni cambia firewall o políticas Polkit.

## Fallos conocidos

### `la tarjeta Wi-Fi no declara soporte AP`

**Causa:** el adaptador o su controlador no ofrece modo punto de acceso, o `iw` no puede leer sus capacidades.
**Solución:** usar un adaptador compatible con modo AP e instalar `iw`.

### `HOTSPOT_PSK inválida`

**Causa:** la clave está ausente, tiene permisos inseguros o no cumple el formato WPA2.
**Solución:** ejecutar `just install-thinkpad-hotspot --set-key` e introducirla nuevamente.

### `NetworkManager no permitió cargar el perfil como usuario normal`

**Causa:** la política Polkit local no permite al usuario crear perfiles.
**Solución:** revisar la política existente de NetworkManager; el instalador no añade permisos administrativos.

## Changelog

### [Unreleased]

- **feat:** preparar un perfil independiente y visible `THINKPAD_RAFEX`.
