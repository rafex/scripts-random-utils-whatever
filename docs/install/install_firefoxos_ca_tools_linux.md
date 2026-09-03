---
title: install_firefoxos_ca_tools_linux.sh
description: Prepara un runtime NSS legado aislado con Podman para Firefox OS en Debian.
tags:
  - instalación
  - firefox-os
  - seguridad
---

# install_firefoxos_ca_tools_linux.sh

Instala Podman y construye un runtime aislado con `certutil` NSS 3.21 para
validar y preparar una copia de `cert9.db`. No modifica el Flame, no descarga
certificados raíz y no inicia ADB.

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

- Debian o un derivado compatible con APT.
- Candidato APT para `podman`.
- Usuario normal con `sudo` disponible únicamente para `--apply`.
- El repositorio debe incluir `containers/firefoxos-ca/Containerfile`.

El instalador no usa el `certutil` moderno del host. Construye con Podman un
runtime rootless fijado a NSS 3.21, la generación histórica alineada con
Gecko 44 del Flame. El archivo fuente oficial de NSS se verifica durante la
construcción con SHA-256. No instala un navegador antiguo, WebIDE ni un
compilador ARM.

## Uso

```bash
just install-firefoxos-ca-tools --check
just install-firefoxos-ca-tools --plan
just install-firefoxos-ca-tools --apply
just install-firefoxos-ca-tools --status
```

La construcción del runtime es independiente de la adquisición y aplicación
de certificados. Después se utiliza `just firefoxos-ca`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba Debian, el candidato APT, el contexto y el estado local. |
| `--plan` | `--dry-run` | Muestra la instalación prevista sin usar `sudo`. |
| `--apply` | — | Instala Podman mediante APT si falta y construye el runtime NSS 3.21. |
| `--status` | — | Muestra el estado sin modificar el equipo ni el teléfono. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

El script no usa variables de configuración ni archivos `.env`. La selección
del paquete es fija para evitar instalar herramientas o fuentes no previstas.

## Ejemplos

### Instalación recomendada

```bash
just install-firefoxos-ca-tools --check
just install-firefoxos-ca-tools --plan
just install-firefoxos-ca-tools --apply
```

### Verificación posterior

```bash
just install-firefoxos-ca-tools --status
podman image inspect localhost/rafex/firefoxos-ca:nss-3.21
```

La ejecución de `certutil` durante el procesamiento se realiza con una
imagen rootless, sin red, sin capacidades y con solo el directorio temporal
de trabajo montado.

### Siguiente fase

```bash
just firefoxos-ca --acquire
just firefoxos-ca --verify-source
```

## Protecciones de seguridad

- `--check`, `--plan` y `--status` son de solo lectura.
- `--apply` solo instala el paquete declarado mediante APT y construye la
  imagen desde el `Containerfile` versionado.
- No se usa `sudo` para ADB ni para escribir el teléfono.
- El runtime de operación usa `--network=none`, `--cap-drop=all`,
  `--read-only` y `no-new-privileges`.
- No se añaden grupos, reglas udev, certificados ni excepciones HTTPS.
- No se compila ni se reemplaza `libnssckbi.so`.

## Fallos conocidos

### `sin candidato APT: podman`

**Causa:** las fuentes Debian no ofrecen el paquete en la configuración
actual.

**Solución:** revisa las fuentes APT y vuelve a ejecutar `--check`. No se
descargan paquetes externos como sustituto.

### `falta el contexto containers/firefoxos-ca/Containerfile`

**Causa:** la ThinkPad no está sincronizada con la revisión del repositorio
que contiene el runtime fijado.

**Solución:** sincroniza el repositorio y vuelve a ejecutar
`just install-firefoxos-ca-tools --check`.

### `runtime NSS legado ausente` o `la compilación del runtime falla`

**Causa:** Podman aún no construyó la imagen, el archivo oficial no pudo
descargarse o la compilación de NSS 3.21 es incompatible con el compilador
disponible.

**Solución:** revisa la salida de `just install-firefoxos-ca-tools --apply`.
La compilación es local, verifica el SHA-256 oficial y no modifica el
teléfono. No sustituyas la imagen por una etiqueta local no verificada.

## Changelog

### [Unreleased]

- **feat:** ejecutar `certutil` NSS 3.21 dentro de un runtime Podman rootless.

### v1.1.0 — 2026-09-02

**feat:** preparar componentes NSS históricos en Podman.

- Sustituir la dependencia host `libnss3-tools` por `podman`.
- Construir NSS 3.21 desde una fuente oficial fijada y verificada.
