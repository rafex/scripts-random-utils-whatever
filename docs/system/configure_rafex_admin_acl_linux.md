---
title: configure_rafex_admin_acl_linux.sh
description: ACL reversibles para que admin pueda modificar el home de rafex en la TNAS.
tags:
  - sistema
  - TNAS
  - permisos
  - ACL
---

# configure_rafex_admin_acl_linux.sh

Revisa y administra ACL para que `admin` pueda leer, escribir y borrar dentro
de `/home/rafex` sin usar `sudo` en cada operación. Guarda una copia antes de
aplicar cambios y permite restaurarla.

- **Ruta:** `scripts/system/configure_rafex_admin_acl_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, ACL tools (`getfacl`, `setfacl`), `find`, coreutils, `awk`, `sudo` (solo para elevar permisos cuando sea necesario)

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

- Linux con soporte ACL y las herramientas `getfacl` y `setfacl`.
- El usuario `admin` debe existir en el sistema.
- Para cambiar `/home/rafex`, el script solicitará `sudo` una vez al ejecutar
  `--apply` o `--restore`. `--check` y `--dry-run` no elevan privilegios.
- En la TNAS, ACL v2.2.53 y `find` de BusyBox fueron comprobados.

## Uso

Desde la raíz del repositorio:

```bash
just rafex-admin-acl --check
just rafex-admin-acl --dry-run
just rafex-admin-acl --apply
```

El script predetermina `/home/rafex`. `--apply` respalda las ACL, da a `admin`
permisos efectivos `rwX` sobre archivos y directorios existentes y agrega ACL
predeterminadas a los directorios para el contenido creado después.

Al terminar, usa la ruta de respaldo que muestra el script para revertir. La
restauración quita ACL de `admin` y valores predeterminados de directorios
creados después del respaldo, y repone las ACL que existían al tomarlo.

```bash
just rafex-admin-acl --restore /home/admin/var/rafex-admin-acl-backups/rafex-home-acl-AAAAMMDD-HHMMSS-PID.acl
```

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra cuántos objetos y directorios tienen ACL efectivas para `admin`; es la acción predeterminada. |
| `--dry-run` | — | Simula la asignación de ACL sin modificar archivos. |
| `--apply` | — | Respalda las ACL y concede permisos de escritura a `admin`. Revierte automáticamente si detecta que se ampliarían permisos efectivos de otros usuarios o grupos. |
| `--restore <respaldo>` | — | Restaura las ACL desde un respaldo generado por este script. |
| `--root <ruta>` | — | Árbol que se revisará o cambiará. Debe ser absoluto y existente; predeterminado `/home/rafex`. Útil para pruebas. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `XDG_STATE_HOME` | Define dónde guardar respaldos si se aplica a un árbol propiedad del usuario actual; por defecto `~/.local/state`. Para el uso elevado en la TNAS, se usa `/home/admin/var/rafex-admin-acl-backups`. |

Los argumentos CLI definen la acción y la ruta; no se leen archivos `.env`.

## Ejemplos

### Uso recomendado en la TNAS

```bash
just rafex-admin-acl --check
just rafex-admin-acl --dry-run
just rafex-admin-acl --apply
```

### Revisar un árbol de prueba

```bash
just rafex-admin-acl --check --root /home/admin/acl-fixture
just rafex-admin-acl --dry-run --root /home/admin/acl-fixture
just rafex-admin-acl --apply --root /home/admin/acl-fixture
```

### Restaurar un respaldo

```bash
just rafex-admin-acl --restore /home/admin/var/rafex-admin-acl-backups/rafex-home-acl-AAAAMMDD-HHMMSS-PID.acl
```

## Protecciones de seguridad

- El valor predeterminado es `/home/rafex`; no permite `/` ni `/home` como raíz.
- No sigue enlaces simbólicos al aplicar ACL.
- No cambia propietarios. Antes de escribir, guarda ACL en un directorio con
  permisos `0700` y el respaldo con `0600`.
- Compara permisos efectivos de las ACL de acceso y de las ACL predeterminadas
  existentes. Si alguno cambia para otra entrada ACL, restaura el respaldo y
  falla sin dejar el cambio aplicado.
- Añadir ACL predeterminadas puede cambiar la herencia de permisos en
  directorios que antes no tenían ACL predeterminada. Al restaurar, los
  directorios incorporados después del respaldo vuelven a no tener ACL
  predeterminada.
- La ruta elegida incluye `.ssh` y demás archivos privados de `rafex`; por eso
  `admin` podrá modificarlos mientras las ACL estén activas.
- La operación es explícita: crear el script no aplica permisos.

## Fallos conocidos

### `se requieren privilegios root`

**Causa:** el usuario actual no es propietario del árbol seleccionado y no
puede cambiar sus ACL.

**Solución:** permite que el script solicite `sudo` para `--apply` o
`--restore`.

### `el cambio alteraría permisos efectivos de otras entradas ACL`

**Causa:** ampliar la máscara ACL para dar escritura a `admin` también ampliaría
el acceso efectivo de otro usuario o grupo.

**Solución:** el script restaura las ACL anteriores. Revisa las ACL existentes
antes de decidir cómo conservar esos permisos y vuelve a ejecutar después.

### `faltan permisos ACL efectivos o ACL predeterminadas`

**Causa:** el árbol todavía no tiene ACL de escritura para `admin`, o se añadió
contenido con permisos heredados más restrictivos.

**Solución:** revisa `--dry-run` y ejecuta `--apply` cuando quieras conceder
acceso.

## Changelog

### [Unreleased]
- Cambios pendientes de release.

### v1.0.0 — 2026-10-09

**feat:** añadir ACL reversibles para que `admin` modifique el home de `rafex`.

- Añade verificación, simulación, aplicación con respaldo y restauración.
- Mantiene iguales los permisos efectivos de otros usuarios y grupos.
