---
title: scan_document_linux.sh
description: Escanea documentos con SANE y guarda PNG sin privilegios administrativos.
tags:
  - sistema
  - escáner
  - sane
---

# scan_document_linux.sh

Escanea preferentemente el Epson XP-241 mediante SANE y guarda el resultado en
un archivo PNG. No usa `sudo`; la Xerox Phaser 3020 no tiene función de escáner.

- **Ruta:** `scripts/system/scan_document_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** bash, `scanimage`, `realpath`, `mktemp`, `mv`.

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

Instala y configura primero CUPS/SANE:

```bash
just install-printers --apply
just configure-printers --apply
```

Conecta la Epson por USB o asegúrate de que esté en la misma red local. Para
ver el backend y la URI detectada:

```bash
just scan-document --list
```

## Uso

```bash
just scan-document --output ~/Documents/escaneo.png
```

El modo predeterminado usa color y 300 DPI.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--output <archivo.png>` | `-o` | Archivo PNG de salida; obligatorio salvo con `--list`. |
| `--device <URI>` | `-d` | Selecciona explícitamente la URI de `scanimage -L`. |
| `--resolution <DPI>` | `-r` | Resolución positiva; predeterminada: 300. |
| `--mode Color\|Gray\|Lineart` | `-m` | Modo de imagen; predeterminado: `Color`. |
| `--force` | — | Permite reemplazar el archivo de salida existente. |
| `--list` | — | Lista los dispositivos SANE sin escanear. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

No requiere variables de configuración. La selección se realiza mediante
argumentos y la salida se limita al `HOME` del usuario o `/tmp`.

## Ejemplos

```bash
just scan-document --list
just scan-document --output ~/Documents/escaneo.png
just scan-document --output /tmp/prueba.png --resolution 600 --mode Gray
just scan-document --device 'epson2:net:192.168.1.40' --output ~/Documents/hoja.png
just scan-document --output ~/Documents/escaneo.png --force
```

## Protecciones de seguridad

- No usa sudo ni accede a dispositivos internos.
- Solo escribe bajo `HOME` o `/tmp`.
- Rechaza rutas de sistema y no reemplaza archivos sin `--force`.
- Escanea mediante un archivo temporal en el mismo directorio y lo mueve al
  finalizar correctamente.
- No guarda contraseñas, identificadores del escáner ni configuraciones de red.

## Fallos conocidos

### `no se detecta un escáner Epson`

**Causa:** la XP-241 está apagada, no está conectada, no está en la misma red o
SANE no reconoce el backend para esa interfaz.

**Solución:** ejecuta `sane-find-scanner`, `scanimage -L` y
`just configure-printers --status`; prueba USB y red por separado.

### `SANE no pudo completar el escaneo`

**Causa:** la tapa está abierta, el dispositivo está ocupado, la resolución o
modo no son aceptados, o la conexión se interrumpió.

**Solución:** vuelve a colocar el original, cierra otras aplicaciones de
escaneo y prueba 300 DPI en color.

## Changelog

### [Unreleased]

- **feat:** añadir escaneo PNG seguro mediante SANE sin sudo.
