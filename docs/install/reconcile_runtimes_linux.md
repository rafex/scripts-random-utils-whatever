---
title: reconcile_runtimes_linux.sh
description: Audita y elimina instalaciones legacy creadas directamente por mise
tags:
  - instalación
  - runtimes
  - seguridad
---

# reconcile_runtimes_linux.sh

Audita el registro propio y las rutas legacy conocidas de mise. En `--apply`
reintegra los enlaces manuales en mise y corrige la selección global sin
descargar runtimes. Solo elimina con `--apply --purge-legacy` y después de
verificar reemplazos propios.

También informa de directorios reales encontrados dentro de los backends de
mise que no estén en la lista legacy explícita. Esos directorios quedan fuera
de toda eliminación automática.

- **Ruta:** `scripts/install/reconcile_runtimes_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, `mise`, `awk`, `readlink`

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

Instala primero los reemplazos con `install-java-runtime`,
`install-node-runtime` e `install-build-runtime`.

## Uso

```bash
just reconcile-runtimes --check
just reconcile-runtimes --plan
just reconcile-runtimes --apply
just reconcile-runtimes --apply --purge-legacy
```

Para reparar una instalación directa de GraalVM hecha anteriormente con
`mise`, usa primero únicamente:

```bash
just reconcile-runtimes --check
just reconcile-runtimes --plan
just reconcile-runtimes --apply
```

`--apply` vuelve a registrar las rutas propias, corrige la selección global y
regenera los shims sin eliminar runtimes. No uses `--purge-legacy` si solo
quieres reparar GraalVM: esa opción puede purgar también rutas legacy de
Node.js, Maven y Gradle. Consulta la [guía central de runtimes](runtime_runtimes_linux.md)
para verificación y selección mediante `runtime-use`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Audita sin modificar. |
| `--plan` | `--dry-run` | Muestra la purga prevista sin modificar. |
| `--apply` | — | Reintegra el registro, corrige selecciones y recalcula shims. |
| `--purge-legacy` | — | Autoriza borrar solo rutas legacy explícitas. |

## Variables de entorno

| Variable | Prioridad | Descripción |
|---|---|---|
| `HOME` | Entorno | Define las rutas a auditar. |
| `XDG_DATA_HOME` | Entorno | Define la ubicación del registro propio. |

## Ejemplos

```bash
just reconcile-runtimes --check
just reconcile-runtimes --apply --purge-legacy
```

## Protecciones de seguridad

- `--check` y `--plan` son no destructivos.
- Sin `--purge-legacy` no elimina archivos.
- Solo opera sobre rutas legacy codificadas explícitamente.
- Exige un reemplazo registrado con el binario esperado.
- Comprueba que ningún runtime que se vaya a borrar siga siendo el activo.
- No toca otros directorios de `mise`.

## Fallos conocidos

### `falta reemplazo verificado`

**Causa:** todavía no se instaló manualmente el runtime sustituto.

**Solución:** ejecuta primero el instalador propio y repite `--check`.

### `todavía es el runtime activo de <identifier>` (falso positivo tras `--apply`)

**Causa:** `integrate_registry()` ejecuta `mise link --force` en cada
`--apply`, lo que convierte la ruta legacy en un symlink hacia el reemplazo
propio antes de que `--purge-legacy` la valide. La versión anterior de
`validate_purge_candidates()` resolvía ese symlink con `readlink -f` y lo
comparaba contra `mise where`, que también apuntaba ya al reemplazo,
disparando el `die` de "todavía activo" sobre una ruta que en realidad ya
era segura de borrar.

**Solución:** corregido — cuando la ruta legacy ya es un symlink, se compara
directamente contra el reemplazo verificado en vez de consultar
`mise where`; la consulta a mise solo se conserva para el caso de un
directorio real todavía activo.

### `symlink legacy apunta a un destino inesperado` con dos versiones del mismo proveedor

**Causa:** el registro propio puede tener más de una versión instalada del
mismo tool/proveedor a la vez (p. ej. dos GraalVM). Un alias legacy de mise
("25", "25.0", ...) puede apuntar legítimamente a cualquiera de ellas, pero
`replacement_for()` solo devuelve la primera fila del archivo — si el alias
apunta a la otra, el chequeo la marcaba como "destino inesperado".

**Solución:** corregido — la rama symlink ahora compara contra todas las
rutas verificadas para ese tool (`replacement_targets_for()`), no solo
contra la primera.

### `node`/`java`/`mvn`/`gradle` dejan de resolver justo después de `--purge-legacy`

**Causa:** en esta versión de mise, los shims son symlinks al propio binario
de mise que resuelven en vivo contra `mise/installs/<tool>/<version>` en
cada ejecución — no rutas fijas. Borrar esa ruta con `--purge-legacy`
desregistraba la versión de mise de inmediato.

**Solución:** corregido — tras `purge_legacy()`, el script vuelve a correr
`integrate_registry()` y `mise reshim` en la misma invocación, dejando la
versión exacta seleccionada (`node@X`, `java@X`/`graalvm@X`, `maven@X`,
`gradle@X`) resoluble de nuevo sin pasos manuales. Los alias parciales de
mise (`25`, `24`, `latest`, ...) los regenera mise por su cuenta al
enlazar.

## Changelog

### [Unreleased]

- **feat:** auditar y purgar runtimes legacy con autorización explícita.
- **fix:** `validate_purge_candidates()` ya no rechaza rutas legacy que
  `integrate_registry()` convirtió en symlink hacia el reemplazo verificado;
  el chequeo de "runtime activo" vía `mise where` solo aplica cuando la ruta
  legacy sigue siendo un directorio real.
- **fix:** la rama symlink compara contra todas las rutas propias
  registradas para ese tool (`replacement_targets_for()`), no solo contra
  la primera fila, para no bloquear el purgado cuando hay dos versiones
  del mismo proveedor instaladas a la vez.
- **fix:** `--apply --purge-legacy` vuelve a enlazar (`integrate_registry` +
  `mise reshim`) inmediatamente después de purgar, para que node/java/mvn/
  gradle sigan resolviendo sin correr `--apply` una segunda vez.
