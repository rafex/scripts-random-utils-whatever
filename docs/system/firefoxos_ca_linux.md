---
title: firefoxos_ca_linux.sh
description: Identifica el runtime NSS del Flame y prepara un cambio reversible sin usar NSS genérico.
tags:
  - sistema
  - firefox-os
  - seguridad
  - usb
---

# firefoxos_ca_linux.sh

Valida el runtime real del Mozilla Flame antes de actualizar sus raíces CA.
La operación se limita al perfil NSS y solo puede continuar con una imagen
Podman construida desde los subárboles NSS/NSPR del commit exacto de
Gecko/B2G que declara el build.

- **Ruta:** `scripts/system/firefoxos_ca_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `adb`, `podman`, `python3`, `curl` solo para `--acquire`, `sha256sum`, `awk`, `grep`, `sed`, `find`, `mktemp` y utilidades POSIX.

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

- Un Mozilla Flame autorizado en ADB normal (`uid=2000(shell)`).
- Build observado: `46.0a1`, Build ID `20151221215202`,
  `SourceRepository=4a4a0bcf45995fdc29caefba2766932dfc25be7d`.
- Podman con `localhost/rafex/firefoxos-ca:b2g46-flame` etiquetado
  `runtime-status=matched` y cuyo hash de `libnss3.so` coincida.
- La fuente de raíces NSS moderna adquirida mediante `--acquire`.

El árbol exacto del teléfono declara NSS 3.21 y NSPR 4.11 en el commit
`4a4a0bcf45995fdc29caefba2766932dfc25be7d` de
[mozilla-b2g/gecko-b2g](https://github.com/mozilla-b2g/gecko-b2g). Las
correcciones históricas se consideran integradas en ese commit; no se aplica
un conjunto externo de parches. La evidencia del build `46.0a1` del
dispositivo se conserva separada mediante [Bugzilla
1232399](https://bugzilla.mozilla.org/show_bug.cgi?id=1232399). Solo el hash
de `libnss3.so`, el Build ID, el `SourceRepository` y un bundle reproducible
de ese árbol pueden autorizar el runtime `b2g46-flame`.

El perfil se trata como un conjunto indivisible:

```text
cert9.db · key4.db · pkcs11.txt
```

El runtime debe leer los tres. El baseline `nss-3.21` se conserva únicamente
como diagnóstico histórico; no es una aproximación autorizada para escribir.

## Uso

Primero identifica el teléfono, sin root y sin modificarlo:

```bash
just firefoxos-ca --identify-runtime
```

Después prepara y verifica la fuente raíz:

```bash
just firefoxos-ca --acquire
just firefoxos-ca --verify-source
just firefoxos-ca --preflight
just firefoxos-ca --plan
```

La aplicación queda bloqueada hasta que exista el runtime exacto:

```bash
just firefoxos-ca --apply --confirm FLAME-MOZILLA-CA-WIPE
```

La lectura no destructiva del conjunto y la reversión son explícitas:

```bash
just firefoxos-ca --test
just firefoxos-ca --rollback --confirm FLAME-CA-ROLLBACK
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--status` | `--check` | Muestra Podman, imágenes, manifiesto local y estado ADB. |
| `--plan` | `--dry-run` | Describe la operación sin tocar el teléfono. |
| `--acquire` | — | Descarga `certdata.txt` de NSS 3.128 y verifica SHA-256. |
| `--verify-source` | — | Valida la fuente ya adquirida y sus raíces `serverAuth`. |
| `--identify-runtime` | — | Lee Build ID, Gaia/Gonk, hash/arquitectura de `libnss3.so` y guarda un manifiesto local. |
| `--preflight` | — | Exige Flame, ADB normal, runtime `matched`, fuente verificada y `libnss3.so`. |
| `--apply` | — | Detiene B2G, valida y sustituye únicamente `cert9.db`, con confirmación exacta. |
| `--test` | — | Extrae y lee el conjunto NSS completo; detiene B2G y usa `adb root` temporalmente, pero no sustituye archivos. |
| `--rollback` | — | Restaura el `cert9.db` del rollback más reciente. |
| `--confirm <texto>` | — | Requerido para `--apply` o `--rollback`; nunca se almacena. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

No se leen variables de configuración ni archivos `.env`. El estado privado se
guarda bajo:

```text
~/.local/share/rafex/firefoxos-ca/runtime/flame-runtime.env
~/.local/share/rafex/firefoxos-ca/sources/
~/.local/share/rafex/firefoxos-ca/rollback/<fecha>/
```

## Ejemplos

### Identificación reproducible

```bash
just firefoxos-ca --identify-runtime
just firefoxos-ca --status
```

El hash de `libnss3.so` se conserva; la biblioteca no queda almacenada en el
estado. La función `NSS_GetVersion()` no se ejecuta sobre el binario ARM
extraído desde una ThinkPad x86_64: si aparece una cadena de versión, se marca
solo como indicio. El manifiesto conserva `unresolved` para la llamada real y
la imagen exacta no se autoriza por inferencia.

### Fuente Mozilla

```bash
just firefoxos-ca --acquire
just firefoxos-ca --verify-source
```

Se fija `NSS_3_128_RTM` con SHA-256
`81b7f2576333a2e360e673f912d7b0b7a765d836c731003e348a46cac5d37198`.

### Prueba y reversión

```bash
just firefoxos-ca --preflight
just firefoxos-ca --test
just firefoxos-ca --rollback --confirm FLAME-CA-ROLLBACK
```

La prueba HTTPS del navegador se realiza manualmente y sin excepciones
permanentes. Una base NSS legible no corrige limitaciones de TLS, HSTS,
JavaScript o APIs del Gecko antiguo.

## Protecciones de seguridad

- El script no usa el `flash.sh` del teléfono, `fastboot`, `adb kill-server`,
  `adb shell` arbitrario, ADB por red ni `sudo`.
- `--identify-runtime`, `--preflight`, `--plan` y `--verify-source` son de solo
  lectura. `--test` tampoco sustituye archivos, pero detiene B2G y usa `adb
  root` temporalmente para comprobar el conjunto real; siempre intenta devolver
  ADB a `uid=2000`.
- `--apply` exige exactamente `FLAME-MOZILLA-CA-WIPE`, un único Flame y ADB
  normal antes de activar `adb root` temporalmente.
- Se extraen `cert9.db`, `key4.db` y `pkcs11.txt`; el rollback conserva los
  tres, con permisos restrictivos.
- Solo se modifica `cert9.db`, porque es el único archivo cambiado por
  `certutil`; los otros dos se validan y permanecen intactos.
- El runtime se ejecuta rootless, sin red, sin capacidades, con filesystem de
  solo lectura y solo el directorio temporal montado.
- La limpieza intenta primero `adb unroot`. Si el adbd antiguo no lo acepta,
  usa un reinicio controlado; nunca usa `stop adbd` como mecanismo principal.
- Si el teléfono desaparece de USB, se detiene el flujo y se solicita
  desconectar/reconectar el cable.
- No se reemplaza `libnssckbi.so`, no se toca `/system`, el módem, particiones,
  bootloader, red ni la configuración de seguridad.

## Fallos conocidos

### `NO-GO: la imagen no corresponde al runtime B2G/Flame identificado`

**Causa:** el contenedor es NSS genérico, usa otro Build ID, otro
`SourceRepository` o un hash distinto de `libnss3.so`.

**Solución:** no fuerces etiquetas. Obtén los subárboles `security/nss` y
`nsprpub` del commit exacto, prepara el bundle en la ruta documentada por el
instalador y reconstruye el runtime.

### `NO-GO: falta el bundle B2G exacto`

**Causa:** no se encontró una fuente reproducible del runtime B2G 46 del Flame.

**Solución:** el resultado correcto es detenerse sin modificar el teléfono.
El baseline 3.21 sin el commit exacto solo sirve para diagnóstico.

### `NO-GO: el runtime B2G no puede leer el conjunto NSS completo`

**Causa:** `cert9.db`, `key4.db` y `pkcs11.txt` no corresponden al runtime o
alguno fue omitido.

**Solución:** no uses SQLite ni `certutil` moderno para forzar la base; revisa
el bundle y conserva el Flame intacto.

### `NSS_GetVersion: unresolved`

**Causa:** el `libnss3.so` ARM está despojado y no contiene una cadena de
versión demostrable mediante lectura no destructiva.

**Solución:** documenta el hash y proporciona el árbol exacto que lo produjo.
La coincidencia de año o de versión Firefox no basta.

### `adb unroot no fue aceptado`

**Causa:** algunos `adbd` antiguos cierran la conexión y no implementan
`unroot` correctamente.

**Solución:** el wrapper espera la reconexión y usa un reinicio controlado si
la conexión sigue disponible. Si no aparece, reconecta el cable y comprueba
`adb shell id`; no ejecutes `stop adbd` manualmente.

### `el hash remoto de cert9.db.new no coincide`

**Causa:** las versiones antiguas de Android del Flame no incluyen
`sha256sum` en su shell. Un hash remoto vacío se interpretaba erróneamente
como corrupción del archivo.

**Solución:** la versión actual descarga `cert9.db.new` de vuelta a la
ThinkPad y calcula el SHA-256 localmente. Si falla la validación, elimina el
temporal creado por esa ejecución antes de reanudar B2G y no sustituye la
base original. Una ejecución posterior con la confirmación requerida también
retira un `cert9.db.new` huérfano de esta operación antes de volver a preparar
el archivo.

## Changelog

### [Unreleased]

- **feat:** identificar el build B2G, la biblioteca NSS y el conjunto completo
  de bases del perfil Flame.
- **fix:** bloquear NSS genérico y corregir la limpieza de ADB root.
- **fix:** validar temporales mediante hash local y limpiar `cert9.db.new`
  cuando el Flame no dispone de `sha256sum`.
- **fix:** retirar de forma controlada un temporal huérfano antes de reintentar
  la operación confirmada.

### v1.1.0 — 2026-09-02

**feat:** instalar raíces Mozilla de forma reversible mediante un runtime
NSS legado aislado.
