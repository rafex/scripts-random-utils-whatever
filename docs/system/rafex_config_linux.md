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
copia versionada de lo instalado en un repositorio local separado. Actualmente
el manifiesto central publica únicamente recursos generados; las configuraciones
estáticas tienen como propietario su instalador especializado y se registran
mediante snapshots.

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
├── installed/       # reservado para artefactos centrales estáticos
├── files/           # snapshots de reversión del guard compartido
└── source-revision  # revisión del replicador usada en el último despliegue
```

El repositorio remoto no se clona dentro de `~/.config` ni en
`~/.local/share/rafex-thinkpad`. El checkout actual del replicador es la fuente
de entrada; `rafex-thinkpad` solo registra el resultado instalado, snapshots y
metadatos locales. No se hace `git push` desde el publicador.

Los generados transitorios y los respaldos de publicación permanecen fuera de
Git en `~/.local/state/rafex/`.

Los scripts que todavía tienen un instalador especializado no se enlazan desde
este publicador: su propietario sigue siendo ese instalador y el guard conserva
su snapshot en `files/home/.local/bin/`. Así se evita que un helper especializado
rompa un symlink central. Cuando un script se migre al publicador, se añadirá al
manifiesto junto con su propietario único. El checkout remoto sigue siendo el
replicador y no se convierte en un repositorio adicional dentro de `HOME`.

La configuración de i3 se compone por piezas, no mediante ediciones acumulativas
del archivo final:

```text
~/.local/state/rafex/config-generated/thinkpad/i3/
├── base.conf       # contenido no administrado conservado durante adopción
├── config          # composición estable
└── fragments/      # un archivo por propietario Rafex
```

Una vez publicado, los instaladores que ya usan el guard común detectan el
encabezado del compositor y escriben solo su fragmento. Si el archivo aún es
manual, continúan bloqueando únicamente su bloque marcado y no se fuerza la
migración automáticamente.

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

`--adopt` es la migración inicial: respalda los destinos reconocidos, prepara
los artefactos generados en `~/.local/state/rafex/config-generated/thinkpad/`
y convierte únicamente esos destinos en enlaces al árbol generado.
Para i3 y `eww.scss`, si ya existe una configuración regular, la adopta como
base instalada antes de componer; no la sustituye silenciosamente por la
plantilla del checkout.
`--deploy` reaplica únicamente destinos ausentes o ya administrados.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Valida manifiesto, fuentes y rutas sin escribir. |
| `--status` | — | Muestra checkout, revisión y estado de cada recurso. |
| `--sync` | — | Valida el checkout ejecutor e inicializa el historial local; no clona ni hace pull remoto. |
| `--plan` | — | Explica la publicación prevista sin modificar archivos. |
| `--adopt` | — | Adopta explícitamente destinos reconocidos y crea respaldos. |
| `--deploy` | — | Publica sin sobrescribir destinos manuales. |
| `--doctor` | — | Detecta checkout sucio, enlaces rotos y propietarios divergentes. |
| `--rollback` | — | Restaura el último conjunto de respaldos del publicador. |

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

- El repositorio actual solo replica y ejecuta; el historial local registra lo
  que se instaló, no reemplaza al repositorio remoto.
- `--sync` valida un checkout ejecutor limpio e inicializa el historial local;
  la actualización Git del replicador se realiza fuera de este publicador.
- Los recursos generados de i3, EWW y el estado de barra se escriben
  atómicamente bajo `~/.local/state/rafex/config-generated/thinkpad/` y los
  destinos administrados apuntan allí. Conky, EWW Yuck, Picom, barras y
  Ratmenu no se enlazan desde este publicador mientras sus instaladores
  especializados sean sus propietarios.
- El compositor de i3 conserva una base sin bloques administrados y recompone
  los fragmentos en orden fijo. Esto evita que instalar Conky, EWW, barras o
  controles elimine los atajos de otro componente.
- No se usan hard links ni `git push`. El publicador puede usar la sesión
  `sudo` ya autorizada únicamente para leer snapshots de archivos de sistema;
  no la usa para escribir configuraciones de usuario. Crea commits
  locales para conservar el historial de instalaciones; no crea commits en el
  repositorio ejecutor.
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

**Causa:** el destino apunta fuera de `~/.local/share/rafex-thinkpad/installed`.

**Solución:** no seguir el enlace automáticamente; corregirlo mediante
`--adopt` o restaurar con `--rollback`.

## Changelog

### [Unreleased]

**feat:** añade publicación híbrida, composición inicial de i3, adopción,
doctor, backups y rollback.
