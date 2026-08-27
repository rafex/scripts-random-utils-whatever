---
title: deploy_configs_unix.sh
description: Despliega configuraciones de un perfil de dotfiles hacia un host remoto
tags:
  - referencia
  - desarrollo
  - seguridad
---

# deploy_configs_unix.sh

Despliega configuraciones de un perfil de `dotfiles` a un host remoto y permite incluir archivos de sistema mediante una operación explícita con `--sudo`.

- **Ruta:** `scripts/dev/deploy_configs_unix.sh`
- **SO requerido:** macOS, Linux
- **Dependencias:** Bash, `ssh`, `scp`, `find`, `awk`, `PATH.toml` y un perfil bajo `dotfiles/profiles/`

______________________________________________________________________

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

El perfil debe existir en `dotfiles/profiles/<perfil>/` y contener `config/`. El host debe estar definido en `PATH.toml` si se usa su nombre lógico; también puede emplearse el flujo de la tarea Just existente.

## Uso

La sintaxis real del script interpreta los dos argumentos posicionales como **perfil y host**, en ese orden:

```bash
bash scripts/dev/deploy_configs_unix.sh --deploy-verify <perfil> <host>
```

La tarea `deploy-configs` invoca actualmente el script como `--deploy-verify <perfil> <host>`, aunque algunos textos de ayuda antiguos muestran `<host> <profile>`; usa el orden anterior.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--deploy-verify <perfil> <host>` | — | Despliega configuraciones y deja un resumen de verificación |
| `--verify <perfil> <host>` | — | Ejecuta únicamente la verificación del perfil y host |
| `--deploy <perfil> <host>` | — | Ejecuta únicamente el despliegue del perfil y host |
| `--sudo` | — | Incluye archivos de sistema definidos en `DEPS.toml` |
| `--list-profiles` | — | Lista perfiles disponibles y termina |
| `--dry-run` | — | Muestra los archivos y destinos sin copiar |
| `--help` | `-h` | Muestra la ayuda incorporada |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `CONFIGS_TOML` | `PATH.toml` | Archivo de configuración usado para localizar mappings |

## Ejemplos

```bash
# Recomendado: despliegue de usuario hacia la ThinkPad
just deploy-configs thinkpad-x1-yoga-1st alqrab

# Simular el despliegue
bash scripts/dev/deploy_configs_unix.sh --deploy-verify thinkpad-x1-yoga-1st alqrab --dry-run

# Incluir explícitamente configuraciones bajo /etc
bash scripts/dev/deploy_configs_unix.sh --deploy-verify thinkpad-x1-yoga-1st alqrab --sudo

# Ver los perfiles
just deploy-profiles
```

## Protecciones de seguridad

- `--dry-run` no copia archivos.
- Los archivos de sistema se omiten si no se proporciona `--sudo`.
- `sudo -v` se solicita únicamente cuando se necesita escribir archivos bajo `/etc`.
- Revisar el perfil y el host antes de usar `scp`; el despliegue remoto modifica la configuración del usuario.

## Fallos conocidos

### Orden de argumentos confuso en la ayuda

**Causa:** la ayuda incorporada describe algunos ejemplos como `<host> <profile>`, pero el parser asigna el primer argumento a `PROFILE` y el segundo a `HOST`.

**Solución:** usar `perfil host`, como lo hace la tarea `deploy-configs`, y conservar este hallazgo hasta una futura corrección funcional.

### `Perfil no encontrado`

**Causa:** el nombre no coincide con una carpeta bajo `dotfiles/profiles/`.

**Solución:** ejecutar `just deploy-profiles` y usar uno de los nombres listados.

## Changelog

### [Unreleased]

- **docs:** documentar despliegue remoto, orden real de argumentos y límites de `--sudo`.
