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
contenga el árbol NSS/B2G y los parches exactos del build observado.

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
B2G 46.0a1 · Build ID 20151221215202 · NSS 3.22.3 · NSPR 4.12
```

La correspondencia Firefox 46 → NSS 3.22.3/NSPR 4.12 se usa únicamente como
baseline histórica y se contrasta con [Mozilla
NSS:Versions](https://wiki.mozilla.org/NSS%3AVersions). El build concreto del
Flame se documenta en [Bugzilla
1232399](https://bugzilla.mozilla.org/show_bug.cgi?id=1232399); una imagen
Debian del mismo periodo no es suficiente para autorizar la aplicación.

## Uso

```bash
just install-firefoxos-ca-tools --check
just install-firefoxos-ca-tools --plan
just install-firefoxos-ca-tools --apply
just install-firefoxos-ca-tools --status
```

Por diseño, el instalador no descarga fuentes B2G ni crea un runtime “parecido”
si el bundle exacto no está disponible.

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
`nss-3.22.3-with-nspr-4.12.tar.gz`, el árbol `b2g/`,
`b2g-source.sha256`, `patches.sha256` y uno o más parches `patches/*.patch`.
Los dos manifiestos de hashes deben validar todo el árbol/parches. El
manifiesto principal debe declarar el Build ID, SourceRepository, hash de
`libnss3.so`, NSS 3.22.3, NSPR 4.12 y estados `matched`.

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

**Causa:** no se ha localizado el árbol NSS/B2G y sus parches del build
`20151221215202`; NSS genérico 3.21–3.23 no demuestra compatibilidad exacta.

**Solución:** no fuerces etiquetas ni uses el baseline para aplicar cambios.
Proporciona un bundle con origen, hashes y parches verificables.

### `sin candidato APT: podman`

**Causa:** las fuentes Debian no ofrecen Podman en la configuración activa.

**Solución:** revisa las fuentes APT. No se usa un paquete externo como sustituto.

### `la compilación del runtime exacto falla`

**Causa:** el bundle no coincide con NSS 3.22.3/NSPR 4.12, sus parches no
aplican o el toolchain no puede reproducirlo.

**Solución:** conserva el teléfono intacto, revisa el manifiesto y no continúes
con `firefoxos-ca --apply`.

## Changelog

### [Unreleased]

- **feat:** añadir validación de bundle y etiquetas del runtime B2G/Flame.
- **fix:** impedir que una imagen NSS genérica se use durante la aplicación.

### v1.1.0 — 2026-09-02

**feat:** preparar componentes NSS históricos en Podman.

- Construir un baseline NSS legado aislado sin modificar el teléfono.
