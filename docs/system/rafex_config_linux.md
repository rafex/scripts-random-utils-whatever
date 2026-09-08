---
title: rafex_config_linux.sh
description: Publicador central y reversible de configuración ThinkPad.
tags:
  - sistema
  - thinkpad
  - configuración
---

# rafex_config_linux.sh

Mantiene un checkout local del repositorio y publica la configuración ThinkPad
con symlinks estáticos y archivos dinámicos generados atómicamente.

- **Ruta:** `scripts/system/rafex_config_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, Git, coreutils, `flock`; `i3` es opcional para la validación posterior

---

## Índice

## Requisitos

Ejecutar como usuario normal desde un checkout del repositorio. El checkout
persistente se crea en:

```text
~/.local/share/rafex/thinkpad-config-repo/
```

El estado generado y los respaldos permanecen fuera de Git en
`~/.local/state/rafex/`.

## Uso

```bash
just rafex-config --check
just rafex-config --status
just rafex-config --sync
just rafex-config --plan
just rafex-config --adopt
just rafex-config --deploy
just rafex-config --doctor
just rafex-config --rollback
```

`--adopt` es la migración inicial: respalda los destinos reconocidos y convierte
los archivos administrados en enlaces al checkout o al árbol generado.
`--deploy` reaplica únicamente destinos ausentes o ya administrados.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Valida manifiesto, fuentes y rutas sin escribir. |
| `--status` | — | Muestra checkout, revisión y estado de cada recurso. |
| `--sync` | — | Crea el checkout local o ejecuta `git pull --ff-only`. |
| `--plan` | — | Explica la publicación prevista sin modificar archivos. |
| `--adopt` | — | Adopta explícitamente destinos reconocidos y crea respaldos. |
| `--deploy` | — | Publica sin sobrescribir destinos manuales. |
| `--doctor` | — | Detecta checkout sucio, enlaces rotos y propietarios divergentes. |
| `--rollback` | — | Restaura el último conjunto de respaldos del publicador. |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `XDG_CONFIG_HOME` | Configuración de aplicaciones; por defecto `~/.config`. |
| `XDG_DATA_HOME` | Checkout local; por defecto `~/.local/share`. |
| `XDG_STATE_HOME` | Generados, bitácora, lock y respaldos; por defecto `~/.local/state`. |

Los argumentos CLI son la interfaz principal. No se carga ningún archivo `.env`.

## Ejemplos

```bash
just rafex-config --check
just rafex-config --status
just rafex-config --plan
just rafex-config --adopt
just rafex-config --doctor
just rafex-config --deploy
just rafex-config --rollback
```

## Protecciones de seguridad

- El repositorio actual sigue siendo la fuente canónica; no se crea un segundo
  repositorio dentro de `~/.config`.
- `--sync` exige checkout limpio y `git pull --ff-only`.
- Los archivos estáticos se enlazan desde el checkout; i3, EWW y el estado de
  barra se generan bajo `~/.local/state/rafex/config-generated/thinkpad/`.
- No se usan hard links, `sudo`, `git commit`, `git push` ni reinicios.
- Un archivo manual o un enlace fuera del árbol permitido bloquea `--deploy`.
- Los respaldos se guardan con permisos restrictivos y se registra una bitácora
  JSONL con hashes, no con el contenido de las configuraciones.
- El publicador no modifica BIOS, TPM, GRUB, initramfs, red o suspensión.

## Fallos conocidos

### `checkout sucio`

**Causa:** el checkout local tiene cambios sin guardar o staged.

**Solución:** revisar con `git -C ~/.local/share/rafex/thinkpad-config-repo status`,
guardar los cambios en el repositorio canónico o retirarlos de forma segura y
volver a ejecutar `--sync`.

### `destino no administrado`

**Causa:** una aplicación o un instalador reemplazó un symlink por un archivo
regular, o el archivo fue creado manualmente.

**Solución:** ejecutar `--doctor`, conservar el archivo si corresponde y usar
`--adopt` solo después de revisar el respaldo que se generará.

### `enlace apunta a otra fuente`

**Causa:** el destino apunta a otro checkout o a una ruta externa.

**Solución:** no seguir el enlace automáticamente; corregirlo mediante
`--adopt` o restaurar con `--rollback`.

## Changelog

### [Unreleased]

**feat:** añade publicación híbrida, composición inicial de i3, adopción,
doctor, backups y rollback.
