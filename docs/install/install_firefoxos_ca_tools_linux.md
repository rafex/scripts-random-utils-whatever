---
title: install_firefoxos_ca_tools_linux.sh
description: Prepara runtimes NSS reproducibles en Podman para el Firefox OS Flame.
tags:
  - instalación
  - firefox-os
  - seguridad
---

# install_firefoxos_ca_tools_linux.sh

Instala Podman y conserva un baseline NSS histórico para diagnóstico. El
runtime que puede editar el Flame solo se construye con un bundle local que
contenga los subárboles NSS/NSPR del commit exacto de Gecko/B2G observado.

- **Ruta:** `scripts/install/install_firefoxos_ca_tools_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `apt-cache`, `apt-get`, `dpkg-query`, `podman`, `sudo` solo durante `--apply`.

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

- Debian/Forky o derivado con candidato APT para `podman`.
- Usuario normal con `sudo` disponible únicamente para `--apply`.
- `containers/firefoxos-ca/Containerfile`, `Containerfile.b2g46` y
  `runtime-manifest.env` presentes en el repositorio.

El baseline `localhost/rafex/firefoxos-ca:nss-3.21` sirve solo para comprobar
que Podman y `certutil` funcionan. No se acepta para modificar el teléfono.

El runtime exacto esperado es:

```text
localhost/rafex/firefoxos-ca:b2g46-flame
B2G 46.0a1 · Build ID 20151221215202 · NSS 3.21 · NSPR 4.11
```

El teléfono declara el commit `4a4a0bcf45995fdc29caefba2766932dfc25be7d` en
`application.ini`. Ese commit del repositorio archivado
[mozilla-b2g/gecko-b2g](https://github.com/mozilla-b2g/gecko-b2g) contiene
NSS 3.21 y NSPR 4.11 (`TAG-INFO` y cabeceras del árbol). Por eso se usa la
fuente exacta, no una imagen Debian elegida por año ni la correspondencia
genérica Firefox 46 → otra versión de NSS. El build concreto del Flame se
documenta en [Bugzilla 1232399](https://bugzilla.mozilla.org/show_bug.cgi?id=1232399);
una imagen Debian del mismo periodo no es suficiente para autorizar la
aplicación.

## Uso

```bash
just install-firefoxos-ca-tools --check
just install-firefoxos-ca-tools --plan
just install-firefoxos-ca-tools --apply
just install-firefoxos-ca-tools --status
```

Por diseño, el instalador no descarga fuentes B2G ni crea un runtime “parecido”
si el bundle exacto no está disponible.

El bundle debe prepararse desde el repositorio oficial archivado, fijando el
commit que el propio Flame declara. La descarga se realiza fuera del
repositorio de scripts y se valida antes de construir:

```bash
bundle="$HOME/.local/share/rafex/firefoxos-ca/b2g46-source"
work="$(mktemp -d)"
git -C "$work" init
git -C "$work" remote add origin https://github.com/mozilla-b2g/gecko-b2g.git
git -C "$work" fetch --filter=blob:none --depth=1 origin \
  4a4a0bcf45995fdc29caefba2766932dfc25be7d
git -C "$work" sparse-checkout set security/nss nsprpub
git -C "$work" checkout --detach FETCH_HEAD
mkdir -p "$bundle/b2g"
cp -a "$work/security" "$bundle/b2g/"
cp -a "$work/nsprpub" "$bundle/b2g/"
(cd "$bundle" && find b2g/security/nss b2g/nsprpub -type f -print0 \
  | sort -z | xargs -0 sha256sum > b2g-source.sha256)
```

El `source-manifest.env` debe declarar el Build ID, `B2G_SOURCE_COMMIT`, el
hash de `libnss3.so` observado y el hash de `b2g-source.sha256`; el instalador lo
comprueba junto con la lista exacta de rutas antes de invocar Podman. No se
debe copiar el repositorio Git completo ni añadir fuentes no relacionadas.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba Debian, APT, contexto y disponibilidad del bundle. |
| `--plan` | `--dry-run` | Muestra acciones sin usar `sudo`, construir imágenes ni escribir. |
| `--apply` | — | Instala Podman y construye el baseline; construye el runtime exacto solo con un bundle validado. |
| `--status` | — | Muestra imágenes, manifiesto del Flame y estado del bundle. |
| `--source-bundle DIR` | — | Usa un bundle local distinto al predeterminado. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

No se usan variables de configuración ni archivos `.env`. El único valor
alternativo es el directorio pasado explícitamente con `--source-bundle`; en
su ausencia se usa:

```text
~/.local/share/rafex/firefoxos-ca/b2g46-source/
```

## Ejemplos

### Diagnóstico recomendado

```bash
just install-firefoxos-ca-tools --check
just install-firefoxos-ca-tools --status
```

### Bundle exacto proporcionado manualmente

El directorio debe contener `source-manifest.env`,
`b2g-source.sha256` y los subárboles sin enlaces simbólicos
`b2g/security/nss/` y `b2g/nsprpub/`. El manifiesto de hashes debe validar
todos sus archivos. El manifiesto principal debe declarar el Build ID,
SourceRepository/`B2G_SOURCE_COMMIT`, hash de `libnss3.so`, NSS 3.21, NSPR 4.11,
`B2G_PATCH_STATUS=embedded-in-source` y `B2G_PATCHES_SHA256=embedded-in-source`.
Las correcciones históricas no se aplican como parches externos: ya forman
parte del commit de Gecko/B2G fijado.

```bash
just install-firefoxos-ca-tools --apply \
  --source-bundle ~/.local/share/rafex/firefoxos-ca/b2g46-source
```

### Verificación posterior

```bash
podman image inspect localhost/rafex/firefoxos-ca:b2g46-flame
```

## Protecciones de seguridad

- `--check`, `--plan` y `--status` no modifican el teléfono.
- No se descargan ni ejecutan fuentes B2G desconocidas automáticamente.
- El baseline 3.21 se etiqueta `baseline-only` y el helper CA lo rechaza.
- El runtime de operación usa Podman rootless, sin red, sin capacidades,
  `no-new-privileges`, filesystem de solo lectura y un directorio temporal.
- No se instala `certutil` moderno en el host ni se reemplaza `libnssckbi.so`.

## Fallos conocidos

### `NO-GO: falta el bundle B2G exacto`

**Causa:** no se han localizado los subárboles NSS/NSPR del commit Gecko/B2G
del build `20151221215202`; NSS genérico no demuestra compatibilidad exacta.

**Solución:** no fuerces etiquetas ni uses el baseline para aplicar cambios.
Proporciona un bundle con origen, commit y hashes verificables.

### `sin candidato APT: podman`

**Causa:** las fuentes Debian no ofrecen Podman en la configuración activa.

**Solución:** revisa las fuentes APT. No se usa un paquete externo como sustituto.

### `la compilación del runtime exacto falla`

**Causa:** el bundle no coincide con NSS 3.21/NSPR 4.11 del commit fijado, o
el toolchain no puede reproducirlo.

**Solución:** conserva el teléfono intacto, revisa el manifiesto y no continúes
con `firefoxos-ca --apply`.

## Changelog

### [Unreleased]

- **feat:** añadir validación de bundle y etiquetas del runtime B2G/Flame.
- **fix:** impedir que una imagen NSS genérica se use durante la aplicación.
- **fix:** reproducir NSS 3.21/NSPR 4.11 desde el commit Gecko/B2G exacto del Flame.

### v1.1.0 — 2026-09-02

**feat:** preparar componentes NSS históricos en Podman.

- Construir un baseline NSS legado aislado sin modificar el teléfono.
