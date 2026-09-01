---
title: install_clipboard_linux.sh
description: Instala CopyQ y configura un historial visual de portapapeles para i3 y Openbox.
tags:
  - instalación
  - portapapeles
  - thinkpad
---

# install_clipboard_linux.sh

Instala CopyQ desde Debian y registra su inicio automático en i3 y Openbox.
El historial se abre con `Super+Shift+V` y también queda disponible en la
bandeja del sistema.

- **Ruta:** `scripts/install/install_clipboard_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** bash, `apt-cache`, `apt-get`, `dpkg-query`, `sudo` solo durante `--apply`.

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Protecciones de seguridad](#protecciones-de-seguridad)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

- Debian con un candidato APT para `copyq`.
- Una sesión X11 con bandeja del sistema; no se configura Wayland.
- Ejecutar el instalador como usuario normal. Solo `--apply` puede solicitar
  sudo para instalar el paquete.

## Uso

```bash
just install-clipboard --check
just install-clipboard --plan
just install-clipboard --apply
just install-clipboard --status
```

Después de aplicar, abre el historial con:

```bash
just clipboard-menu --show
```

o con `Super+Shift+V` dentro de i3/Openbox.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba el paquete, helper y bloques administrados sin escribir. |
| `--plan` | `--dry-run` | Muestra los cambios previstos sin modificar archivos. |
| `--apply` | — | Instala CopyQ y actualiza i3/Openbox con respaldos fechados. |
| `--status` | — | Muestra la instalación y si existe el bloque de integración. |
| `--help` | `-h` | Muestra la ayuda. |

El helper instalado admite `--show`, `--menu`, `--status` y `--check`.

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `I3_CONFIG` | `~/.config/i3/config` | Configuración i3 que recibirá el bloque administrado. |
| `OPENBOX_AUTOSTART` | `~/.config/openbox/autostart` | Autostart de Openbox que recibirá CopyQ. |
| `XDG_CONFIG_HOME` | — | CopyQ usa su ubicación estándar si está definida por la aplicación. |

No se leen archivos `.env` ni se aceptan contraseñas por argumento.

## Ejemplos

### Instalación recomendada

```bash
just install-clipboard --check
just install-clipboard --plan
just install-clipboard --apply
```

### Abrir la interfaz o el menú de bandeja

```bash
just clipboard-menu --show
just clipboard-menu --menu
just clipboard-menu --status
```

### Verificar sin iniciar la aplicación

```bash
just install-clipboard --status
```

## Protecciones de seguridad

- `--check`, `--plan` y `--status` son de solo lectura.
- El historial de CopyQ se guarda en el espacio del usuario; no se copia al
  repositorio ni al respaldo de scripts.
- El portapapeles puede contener contraseñas, tokens, códigos o datos privados.
  No copies secretos mientras el historial esté habilitado; elimina el
  historial desde la interfaz de CopyQ cuando sea necesario.
- El instalador no concede privilegios, no crea reglas Polkit y no expone el
  portapapeles por red.
- Los bloques se actualizan por marcadores y no se duplican al repetir la
  instalación. Configuraciones fuera de esos bloques no se reemplazan.

## Fallos conocidos

### `copyq no tiene candidato APT`

**Causa:** los índices Debian no están actualizados o la fuente no incluye el
  paquete.

**Solución:** revisa las fuentes Debian, ejecuta `apt-get update` y repite
`just install-clipboard --apply`.

### `CopyQ no respondió`

**Causa:** el comando se ejecutó sin una sesión X11 válida o el servidor aún no
  terminó de iniciar.

**Solución:** entra a i3/Openbox, verifica `echo "$DISPLAY"`, ejecuta
`copyq` una vez y vuelve a usar `just clipboard-menu --show`.

### El historial contiene un secreto

**Causa:** CopyQ almacena el contenido del portapapeles automáticamente por
  defecto. Consulta la documentación oficial de [CopyQ](https://copyq.readthedocs.io/en/latest/security.html).

**Solución:** abre CopyQ, elimina el elemento o limpia el historial desde su
  interfaz. Para datos de alta sensibilidad, desactiva temporalmente el
  almacenamiento del portapapeles en CopyQ.

## Changelog

### [Unreleased]

- **feat:** añadir CopyQ, helper de acceso y autoinicio idempotente para X11.
