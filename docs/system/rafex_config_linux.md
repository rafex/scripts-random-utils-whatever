---
title: rafex_config_linux.sh
description: Publicador central y reversible de configuración ThinkPad.
tags:
  - sistema
  - thinkpad
  - configuración
---

# rafex_config_linux.sh

Replica la configuración ThinkPad desde el checkout ejecutor y conserva una
copia versionada de lo instalado en un repositorio local separado. El checkout
principal es un replicador; el historial operativo y la fuente de los archivos
ya instalados son los snapshots de `~/.local/share/rafex-thinkpad`.

- **Ruta:** `scripts/system/rafex_config_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, Git, coreutils, `flock`; `i3` es opcional para la validación posterior

---

## Índice

## Requisitos

Ejecutar como usuario normal desde el checkout del repositorio. El estado
instalado se conserva en:

```text
~/.local/share/rafex-thinkpad/
├── snapshots/<fecha>/{home,system,metadata}/
├── active -> snapshots/<fecha>
├── manifest.tsv
└── source-revision
```

El repositorio remoto no se clona dentro de `~/.config`. Antes de `--deploy` o
`--adopt`, el publicador exige checkout limpio y ejecuta `git pull --ff-only`.
No se hace `git push` desde el publicador. Cada snapshot publicado crea un
commit local con identidad Git local, nunca global.

Los generados transitorios y los respaldos de publicación permanecen fuera de
Git en `~/.local/state/rafex/`.

El manifiesto `thinkpad-state-manifest.tsv` define propietario, destino,
estrategia, modo, validador, exclusiones y riesgo. Los archivos estáticos de
usuario se enlazan hacia `active/home`; los archivos dinámicos que deben poder
ser reemplazados atómicamente por un helper (Dunst, tema EWW, perfil de barra
y la inclusión de barra activa)
se copian desde el snapshot. Los archivos de `/etc` se copian desde
`active/system` con `install`, `mv` atómico y `root:root`. Nunca se enlazan
archivos de `/etc` a `HOME`.

La configuración instalada se registra como contenido de un snapshot; no se
mantiene otro repositorio fuente dentro de `~/.config`. La adopción es
explícita: `--snapshot` solo captura el estado actual y `--adopt` además
publica los destinos reconocidos desde el snapshot activo. Los archivos
manuales no reconocidos bloquean `--deploy`; no se sobrescriben.

## Uso

```bash
just rafex-config --check
just rafex-config --status
just rafex-config --sync
just rafex-config --snapshot
just rafex-config --plan
just rafex-config --adopt --component all
just rafex-config --deploy --component all
just rafex-config --doctor
just rafex-config --rollback --component i3
```

`--adopt` es la migración inicial: respalda los destinos reconocidos, captura
el estado instalado en `snapshots/<fecha>/` y publica únicamente los destinos
reconocidos. Si un recurso de usuario reconocido todavía no existe en la
ThinkPad (por ejemplo, un helper nuevo), se toma como semilla desde el
checkout replicador; los recursos existentes siempre se conservan desde el
estado vivo. Los archivos estáticos de usuario quedan enlazados a
`active/home`; los dinámicos conservan una copia atómica para que los helpers
puedan actualizarla. `--deploy` reaplica únicamente destinos ausentes o ya
administrados y conserva los valores dinámicos del snapshot activo.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Valida manifiesto, fuentes y rutas sin escribir. |
| `--status` | — | Muestra checkout, revisión y estado de cada recurso. |
| `--sync` | — | Rechaza cambios locales, hace `git pull --ff-only` y prepara el historial. |
| `--snapshot` | — | Captura configuración instalada sin cambiar destinos vivos y crea commit local. |
| `--plan` | — | Explica la publicación prevista sin modificar archivos. |
| `--adopt` | — | Adopta explícitamente destinos reconocidos y crea respaldos. |
| `--deploy` | — | Sincroniza, genera snapshot desde el replicador y publica el componente indicado. |
| `--doctor` | — | Detecta checkout sucio, enlaces rotos y propietarios divergentes. |
| `--rollback --component <nombre>` | — | Restaura el último respaldo del componente (`i3`, `visual`, `hardware`, `network` o `lab`). |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `XDG_CONFIG_HOME` | Configuración de aplicaciones; por defecto `~/.config`. |
| `XDG_DATA_HOME` | Raíz del historial instalado; por defecto `~/.local/share`. |
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

- El repositorio actual solo replica y ejecuta; `rafex-thinkpad` es el control
  histórico de configuraciones instaladas.
- `--sync` actualiza el replicador con fast-forward-only y fija la identidad
  Git únicamente dentro del historial local.
- Los symlinks solo apuntan a `active/home` dentro del historial. `/etc` se
  publica como copia atómica root-owned, nunca como symlink.
- `--snapshot` no despliega. `--adopt` y `--deploy` generan respaldo fechado,
  validan el manifiesto y publican solo el componente solicitado.
- No se usan hard links, commits ni push en el checkout replicador.
- Las acciones destructivas de BIOS, bootloader, particiones, flasheos,
  teléfonos y red quedan fuera de este publicador.
- Un archivo manual o un enlace fuera del árbol permitido bloquea `--deploy`.
- Los respaldos se guardan con permisos restrictivos y se registra una bitácora
  JSONL con hashes, no con el contenido de las configuraciones.
- El publicador no modifica BIOS, TPM, GRUB, initramfs, red o suspensión.

## Fallos conocidos

### `historial local modificado`

**Causa:** el historial local tiene cambios sin guardar o staged fuera del
publicador, normalmente porque una aplicación modificó un symlink administrado.

**Solución:** revisar con `git -C ~/.local/share/rafex-thinkpad status` y
conservar cualquier cambio manual antes de volver a desplegar.

### `destino no administrado`

**Causa:** una aplicación o un instalador reemplazó un symlink por un archivo
regular, o el archivo fue creado manualmente.

**Solución:** ejecutar `--doctor`, conservar el archivo si corresponde y usar
`--adopt` solo después de revisar el respaldo que se generará.

### `enlace apunta a otra fuente`

**Causa:** el destino apunta fuera de `~/.local/share/rafex-thinkpad/active`.

**Solución:** no seguir el enlace automáticamente; corregirlo mediante
`--adopt` o restaurar con `--rollback`.

## Changelog

### [Unreleased]

**feat:** añade snapshots locales con commits, symlinks de usuario, copias
atómicas root-owned y rollback por componente.
