---
title: firefoxos_ca_linux.sh
description: Actualiza de forma reversible el almacén NSS de un Mozilla Flame mediante ADB.
tags:
  - sistema
  - firefox-os
  - seguridad
  - usb
---

# firefoxos_ca_linux.sh

Prepara el almacén raíz Mozilla para el navegador legado del Flame y, con una
confirmación explícita, instala las raíces serverAuth dentro de `cert9.db`.
No compila B2G, no reemplaza `libnssckbi.so` y no modifica particiones.

- **Ruta:** `scripts/system/firefoxos_ca_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `adb`, `certutil` de `libnss3-tools`, `curl` solo para `--acquire`, `python3`, `sha256sum`, `find`, `mktemp` y utilidades POSIX.

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

- ThinkPad con Debian y `adb` funcionando.
- Teléfono Mozilla Flame con ADB autorizado y `ro.debuggable=1`.
- `libnss3-tools` instalado con `just install-firefoxos-ca-tools --apply`.
- Conexión USB directa, un solo dispositivo ADB y batería suficiente.
- Conectividad HTTPS a Mozilla solo para `--acquire`.

La fuente se fija en NSS `3.128` (`NSS_3_128_RTM`) y se descarga desde el
árbol oficial de Mozilla:

```text
https://hg.mozilla.org/projects/nss/raw-file/NSS_3_128_RTM/lib/ckfw/builtins/certdata.txt
SHA-256: 81b7f2576333a2e360e673f912d7b0b7a765d836c731003e348a46cac5d37198
```

Mozilla documenta que `certdata.txt` es la fuente autoritativa del almacén
raíz NSS y que el módulo tradicional `libnssckbi` se genera a partir de ella:
[NSS Root Store](https://firefox-source-docs.mozilla.org/security/nss/runbooks/rootstore.html).

El navegador Firefox OS es software legado. Mozilla-B2G está archivado y no
recibe mantenimiento moderno: [Mozilla-B2G](https://github.com/mozilla-b2g/B2G).

## Uso

Instala primero las herramientas del host:

```bash
just install-firefoxos-ca-tools --check
just install-firefoxos-ca-tools --plan
just install-firefoxos-ca-tools --apply
```

Después, con el teléfono desbloqueado y ADB autorizado:

```bash
just firefoxos-ca --status
just firefoxos-ca --acquire
just firefoxos-ca --verify-source
just firefoxos-ca --preflight
just firefoxos-ca --plan
```

La aplicación directa requiere:

```bash
just firefoxos-ca --apply --confirm FLAME-MOZILLA-CA-WIPE
```

La prueba y la reversión son explícitas:

```bash
just firefoxos-ca --test
just firefoxos-ca --rollback --confirm FLAME-CA-ROLLBACK
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--status` | `--check` | Muestra herramientas, fuente y estado ADB sin escribir. |
| `--plan` | `--dry-run` | Detalla la operación sin descargar ni modificar. |
| `--acquire` | — | Descarga la fuente NSS fijada y verifica su SHA-256. |
| `--verify-source` | — | Valida la fuente ya adquirida sin modificar el teléfono. |
| `--preflight` | — | Comprueba un Flame, ADB, `ro.debuggable` y la biblioteca B2G. |
| `--apply` | — | Instala las raíces en `cert9.db` con confirmación exacta. |
| `--test` | — | Lee una copia de `cert9.db` y busca raíces administradas. |
| `--rollback` | — | Restaura el rollback más reciente con confirmación exacta. |
| `--confirm <texto>` | — | Requerido para `--apply` o `--rollback`; no se guarda. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

El script no lee variables de configuración ni archivos `.env`. Las rutas de
fuente y rollback son fijas y privadas:

```text
~/.local/share/rafex/firefoxos-ca/sources/
~/.local/share/rafex/firefoxos-ca/rollback/
```

## Ejemplos

### Forma explícita/recomendada

```bash
just firefoxos-ca --acquire
just firefoxos-ca --verify-source
just firefoxos-ca --preflight
just firefoxos-ca --plan
just firefoxos-ca --apply --confirm FLAME-MOZILLA-CA-WIPE
```

### Comprobación posterior

```bash
just firefoxos-ca --test
```

Después de reiniciar el Flame, prueba manualmente `support.mozilla.org`,
`letsencrypt.org`, `www.mozilla.org` y `example.com`, sin iniciar sesión ni
aceptar excepciones permanentes. El certificado `ISRG Root X1` puede
consultarse en [Let’s Encrypt](https://letsencrypt.org/certs/isrgrootx1.pem),
pero la primera instalación usa el conjunto validado por Mozilla NSS.

### Reversión

```bash
just firefoxos-ca --rollback --confirm FLAME-CA-ROLLBACK
```

La reversión restaura solo `cert9.db`; no es un respaldo de fotos, contactos,
mensajes, aplicaciones ni configuraciones.

## Protecciones de seguridad

- No se ejecuta el `flash.sh` del teléfono ni se usan `fastboot`, `adb push`
  arbitrario, `adb shell` arbitrario, `adb kill-server` o ADB por red.
- Solo se aceptan los comandos ADB fijos necesarios para identificar el Flame,
  controlar B2G, copiar `cert9.db`, validar hashes, reiniciar y revertir.
- `--apply` exige exactamente `FLAME-MOZILLA-CA-WIPE`.
- `--rollback` exige exactamente `FLAME-CA-ROLLBACK`.
- Se exige un único dispositivo ADB autorizado y `ro.product.device=flame`.
- `adb root` se usa temporalmente y se comprueba que vuelva a uid 2000 tras el
  reinicio.
- La fuente Mozilla se valida por SHA-256 antes y durante la aplicación.
- Solo se importan raíces marcadas por Mozilla para autenticación web
  `serverAuth`; no se importan certificados arbitrarios ni intermediarios.
- La copia de rollback contiene únicamente `cert9.db`, queda fuera del
  repositorio y se crea con permisos restrictivos.
- El archivo original se reemplaza mediante `cert9.db.new` y una operación
  `mv` después de comparar su hash remoto.
- No se modifica `/system`, `libnssckbi.so`, particiones, bootloader, red ni
  configuraciones de seguridad.
- Una CA instalada no corrige limitaciones de TLS, JavaScript, HSTS o
  compatibilidad del motor Gecko 44.

## Fallos conocidos

### `fuente no adquirida`

**Causa:** `--verify-source`, `--preflight` o `--apply` se ejecutó antes de
adquirir la fuente.

**Solución:** ejecuta `just firefoxos-ca --acquire` y después
`--verify-source`.

### `SHA-256 de certdata.txt no coincide`

**Causa:** la descarga no corresponde exactamente a NSS 3.128 fijado o fue
alterada.

**Solución:** no fuerces la operación ni uses el archivo. Conserva la fuente
solo si vuelve a coincidir con el hash documentado.

### `se requiere exactamente un Flame autorizado`

**Causa:** ADB no ve un dispositivo, hay varios dispositivos o falta aceptar
la autorización en el teléfono.

**Solución:** desconecta otros dispositivos, activa **ADB and DevTools**,
acepta la autorización RSA y ejecuta `adb devices`.

### `adb root no está disponible`

**Causa:** el firmware no es root-capable o no anuncia `ro.debuggable=1`.

**Solución:** detener el proceso. No se intentará desbloquear el bootloader ni
se escribirá `cert9.db` por otra vía automática.

### `adb root no confirmó uid 0 después de esperar la reconexión`

**Causa:** el `adbd` antiguo del Flame reinició la conexión y la comprobación
ocurrió mientras el daemon todavía reaparecía.

**Solución:** el wrapper espera la reconexión y reintenta la comprobación. Si
una operación aborta después de activar ADB root, intenta `unroot` y, si ese
firmware no lo acepta, reinicia de forma controlada para volver a uid 2000.

En el Flame antiguo, `adb shell id -u` puede devolver la línea completa de
identidad en lugar de un número. El wrapper extrae el UID desde `uid=...` para
aceptar correctamente tanto `uid=0(root)` como `uid=2000(shell)`.

El shell del Flame también interpreta de forma distinta `adb shell sh -c` con
varios argumentos. El descubrimiento del perfil usa un glob remoto fijo con
`ls -d` y rechaza cualquier salida que no sea una ruta `.default` segura.

### `certutil no puede leer la copia de cert9.db`

**Causa:** la base está bloqueada, tiene un formato incompatible o falta una
herramienta NSS compatible.

**Solución:** no se sube la copia. Mantén el Flame intacto y evalúa una
recompilación compatible de NSS como proyecto independiente.

### `la CA aparece instalada pero el navegador continúa fallando`

**Causa:** Gecko 44 no soporta el TLS, algoritmo, cadena, HSTS o JavaScript
que requiere el sitio.

**Solución:** no añadas excepciones permanentes. Usa `--rollback` si deseas
retirar el cambio y documenta el sitio como incompatible.

## Changelog

### [Unreleased]

- **feat:** añadir adquisición y validación reproducible del almacén Mozilla NSS.
- **feat:** añadir instalación reversible de raíces serverAuth en `cert9.db`.
- **docs:** documentar ADB root temporal, límites de Gecko legado y rollback.

### v1.0.1 — 2026-09-02

**fix:** esperar la reconexión de `adbd` y restaurar ADB normal tras un fallo.

- Evitar falsos fallos durante el reinicio causado por `adb root`.
- Documentar el comportamiento de recuperación en firmwares Flame antiguos.

### v1.0.2 — 2026-09-02

**fix:** interpretar la salida de identidad de los firmwares Android antiguos.

- Extraer el UID desde la salida completa de `adb shell id`.
- Confirmar y restaurar correctamente ADB normal en el flujo temporal root.

### v1.0.3 — 2026-09-02

**fix:** localizar el perfil NSS con el shell compatible del Flame.

- Reemplazar el `sh -c` frágil por `ls -d` sobre un glob fijo.
- Evitar que mensajes de error del shell se interpreten como rutas remotas.

### v1.0.4 — 2026-09-02

**fix:** interpretar correctamente la metadata de archivos en Android antiguo.

- Leer UID y GID desde las columnas reales de `ls -ln` del Flame.
- Mantener la protección `root:root` y modo `600` antes de sobrescribir.
