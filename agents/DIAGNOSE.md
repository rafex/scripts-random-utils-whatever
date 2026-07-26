# Diagnóstico del Proyecto

_Fecha: 2026-07-22 | Repositorio: scripts-random-utils-whatever_

---

## 1. Exploración

### Estructura general

Colección de 24 scripts Bash de utilidad organizados en 6 categorías dentro de `scripts/`, con documentación Markdown paralela en `docs/` y automatización mediante `Makefile` (builder) + `Justfile` (task runner).

```
scripts/          ← 24 scripts en 6 categorías
  dev/            ← 3 scripts (jdtls, update_copilot ×2)
  display/        ← 5 scripts (xrandr screen management)
  hardware/       ← 4 scripts (brillo, volumen, batería, teclado)
  install/        ← 2 scripts (create_usb, format_usb) — los más grandes
  macos/          ← 1 script (clean_apple_meta)
  network/        ← 9 scripts (wifi, myip, connect_nas, polkit)
docs/             ← documentación Markdown por script
  dev/            ← vacío (sin docs)
  display/        ← 5 docs
  hardware/       ← 4 docs
  install/        ← 2 docs
  macos/          ← 2 docs (1 extra: Metadatos.md)
  network/        ← 9 docs + 1 extra (wifi_polkit_rules.md)
make/             ← módulos Makefile (check.mk, dist.mk)
just/             ← módulos Justfile (install.just, macos.just)
AGENTS.md         ← guía de convenciones para agentes y contribuidores
README.md         ← índice de navegación
LICENSE           ← MIT
.opencode/        ← infraestructura local de opencode (no versionada)
```

### Lenguajes y tecnologías

- **Bash** — 100% del código ejecutable, 24 scripts, 2220 líneas totales
- **Markdown** — 18 archivos de documentación
- **Makefile** — builder (verificación de sintaxis, empaquetado)
- **Justfile** — task runner (lanzar scripts desde raíz)

### Sistema de build / dependencias

Sin gestor de dependencias formal (bash puro, sin `requirements.txt` ni `package.json` funcional).

| Archivo | Rol | Targets |
|---------|-----|---------|
| `Makefile` | Builder | `check`, `shellcheck`, `dist`, `clean` |
| `Justfile` | Task runner | `create-usb`, `format-usb`, `clean-apple-meta` |

Dependencias externas requeridas por los scripts: `pv`, `gdd`, `nmcli`, `rfkill`, `xrandr`, `brightnessctl`, `mkfs.*`, `code`/`codium`.

### Puntos de entrada

Cada script `.sh` es un punto de entrada independiente. Se ejecutan directamente o mediante `just <tarea>`. No hay un `main` o `bootstrap` centralizado.

### Módulos y componentes clave

| Categoría | Scripts | Complejidad | Soporte |
|-----------|---------|-------------|---------|
| `install/` | 2 scripts | Alta (360–372 LOC) | macOS + Linux |
| `network/` | 9 scripts | Media (12–164 LOC) | Solo Linux |
| `display/` | 5 scripts | Media (13–144 LOC) | Solo Linux |
| `hardware/` | 4 scripts | Baja (20–36 LOC) | Solo Linux |
| `dev/` | 3 scripts | Media (22–130 LOC) | Solo Linux |
| `macos/` | 1 script | Media (190 LOC) | Solo macOS |

Relaciones: los scripts `install/create_usb_unix.sh` y `install/format_usb_unix.sh` comparten un alto grado de código duplicado (funciones de logging, colores, carga de `.env`, validación de SO). No existe librería compartida.

### Archivos de configuración relevantes

| Archivo | Tipo | Descripción |
|---------|------|-------------|
| `.gitignore` | config | 45 líneas, exclusión de binarios, archivos Apple, opencode local |
| `AGENTS.md` | convenciones | 264 líneas, guía completa para agentes y contribuidores |
| `README.md` | documentación | 42 líneas, índice de navegación |
| `LICENSE` | legal | MIT |
| `.opencode/` | infraestructura | sesiones y worktrees (local, no versionado) |

**Ausencias notables:** sin GitHub Actions, sin CI/CD, sin `spec-native/`, sin Dockerfile, sin framework de tests.

### Estado del repositorio

| Indicador | Valor |
|-----------|-------|
| Rama actual | `main` (única), sincronizada con `origin/main` |
| Último commit | `e743875` — 2026-05-02, "vamos" |
| Commits totales | 5 en el historial reciente |
| Archivos modificados | `.gitignore` (no staged) |
| Archivos sin trackear | `docs/network/`, `scripts/display/`, `scripts/hardware/`, `scripts/network/` |
| PRs abiertos | 0 |

---

## 2. Revisión de calidad

### Problemas estructurales o de diseño

1. **Duplicación masiva entre los dos scripts más grandes.** `create_usb_unix.sh` y `format_usb_unix.sh` comparten 116 líneas idénticas (6 funciones: `info()`, `error()`, `success()`, `warn()`, `usage()`, `load_env_file()`). Son el ~32% de cada archivo duplicado sin librería compartida.

2. **Sin librería común de utilidades.** El patrón de colores, funciones de logging, detección de SO y carga de `.env` se repite manualmente en la mayoría de los scripts. Cualquier cambio en estas utilidades requiere editar N archivos.

3. **Cobertura de Justfile casi nula.** Solo 3 de 24 scripts (12.5%) tienen tarea en Justfile. Las categorías `display`, `hardware`, `network`, `dev` no están representadas.

### Deuda técnica identificada

| Archivo/Módulo | Problema | Severidad |
|---------------|----------|-----------|
| `scripts/install/*.sh` | 116 líneas duplicadas entre ambos | Alta |
| `scripts/install/*.sh` | 360–372 LOC sin tests — código crítico que manipula discos | Alta |
| `scripts/dev/*.sh` | Sin documentación (docs/dev/ vacío) | Media |
| `scripts/network/wifi_connect_interactive_linux.sh` | 164 LOC, sin documentación, el más complejo de network | Media |
| Múltiples scripts | Sin tarea en Justfile, sin documentación | Media |

### Prácticas del lenguaje no seguidas

1. **Shebang inconsistente.** 23 scripts usan `#!/usr/bin/env bash`, pero `notify_brightness_linux.sh` usa `#!/bin/bash`. La convención del proyecto (AGENTS.md) no lo define explícitamente, pero debería unificarse.

2. **Sin versionado explícito en scripts.** AGENTS.md define versionado semántico (`vMAJOR.MINOR.PATCH`), pero ningún script declara su versión actual.

3. **Variables sin comillas en contextos inseguros.** El grep superficial detectó múltiples ocurrencias de variables expandidas sin comillas dobles en contextos donde podrían romperse con espacios. Requiere revisión caso por caso.

### Riesgos de seguridad

| Riesgo | Evaluación |
|--------|-----------|
| Secretos hardcodeados | No detectados — OK |
| `chmod 777` | No detectado — OK |
| `rm -rf` sin protección | No detectado — OK |
| `sudo` en scripts | Uso legítimo (dd, mount, mkfs, modprobe) — OK |
| `.env` con credenciales | AGENTS.md menciona soporte para `.env`; `.gitignore` lo excluye — OK |
| Dependencias sin versión fija | No aplica (sin gestor de paquetes) |

**Conclusión de seguridad:** sin riesgos altos detectados. Las operaciones con `sudo` están justificadas y contextualizadas.

### Cobertura de tests y documentación

| Indicador | Valor |
|-----------|-------|
| Tests | **0** — sin framework (bats, shunit2) ni tests manuales |
| Scripts con documentación | **18/24 (75%)** |
| Scripts sin documentación | **6/24 (25%)**: 3 en dev/, 4 en network/ |
| Scripts con tarea Justfile | **3/24 (12.5%)** |

---

## 3. Síntesis ejecutiva

### Resumen del proyecto

Repositorio personal de 24 scripts Bash (~2,220 LOC) que automatizan tareas de sistema en macOS y Linux: creación/formateo de USB booteables, gestión de pantallas vía xrandr, WiFi con nmcli, notificaciones de hardware, y utilidades de desarrollo. Organizado por categorías con documentación Markdown paralela, automatizado con Makefile (build/check) y Justfile (task runner). Sigue convenciones propias de nomenclatura por plataforma y documentación. Sin tests, sin CI/CD, y con duplicación significativa en los scripts más críticos.

### Estado de salud

**🟡 Amarillo** — El proyecto tiene bases sólidas (convenciones claras, `set -euo pipefail` universal, sin secretos expuestos), pero acumula deuda técnica importante: 25% de scripts sin documentar, 87.5% sin entrada en Justfile, 0 tests, y duplicación del 32% en los dos scripts más críticos. La ausencia de CI/CD impide detectar regresiones automáticamente.

### Top 3 fortalezas

1. **Disciplina de robustez Bash**: 100% de scripts con `set -euo pipefail` y shebang correcto. Sin secretos expuestos ni operaciones peligrosas injustificadas.
2. **Convenciones documentadas y aplicadas**: `AGENTS.md` es una guía excepcionalmente completa (264 líneas) que cubre nomenclatura, documentación, versionado, y separación Makefile/Justfile.
3. **Documentación estructurada**: 75% de scripts tienen documentación Markdown con plantilla consistente (requisitos, uso, opciones, ejemplos, fallos conocidos, changelog).

### Top 3 riesgos o deudas

1. **Duplicación crítica en scripts install/**: `create_usb_unix.sh` y `format_usb_unix.sh` comparten 116 líneas idénticas (32% de cada archivo). Cualquier bug en las funciones compartidas debe corregirse en dos lugares. Son los scripts más peligrosos del repo (manipulan discos con `dd` y `mkfs`).

2. **Cero tests en código que manipula hardware**: Los scripts `install/` ejecutan `dd` y `mkfs` — comandos que pueden destruir datos. Sin tests automatizados, cualquier cambio es un riesgo.

3. **Integración incompleta con Justfile**: Solo 3/24 scripts (12.5%) son accesibles vía `just`. El resto requiere conocer la ruta exacta del script. Esto reduce la usabilidad y no cumple la promesa del README de que `just` es el punto de entrada.

### Próximos pasos recomendados

1. **Extraer librería común de utilidades** — Crear `scripts/lib/utils.sh` con las funciones duplicadas (`info`, `error`, `success`, `warn`, `load_env_file`, detección de SO) y sourcearla desde todos los scripts. Elimina 116+ líneas duplicadas y centraliza el mantenimiento. (Impacto: alto)

2. **Completar cobertura de Justfile** — Crear `just/display.just`, `just/hardware.just`, `just/network.just`, `just/dev.just` con tareas para todos los scripts. Cumple la promesa del README y mejora la usabilidad. (Impacto: alto)

3. **Documentar los 6 scripts huérfanos** — Completar `docs/dev/` y los 4 docs faltantes en `docs/network/` siguiendo la plantilla de `AGENTS.md`. (Impacto: medio)

4. **Crear directorio `spec-native/`** — Inicializar el contexto SpecNative Development con `PRODUCT.md`, `ARCHITECTURE.md`, `STACK.md`, `CONVENTIONS.md`, `DECISIONS.md`, y `ROADMAP.md` para dar estructura a futuras decisiones de diseño. (Impacto: medio)

5. **Agregar CI/CD con GitHub Actions** — Workflow mínimo que ejecute `make check && make shellcheck` en cada push/PR. Detecta regresiones de sintaxis automáticamente. (Impacto: medio)

6. **Evaluar framework de tests para Bash** — Investigar `bats-core` o `shunit2` para testear los scripts `install/` (los más críticos). Aunque el ROI de testear scripts pequeños es bajo, los scripts que manipulan discos lo justifican. (Impacto: bajo a corto plazo, alto a largo plazo)

---

## 4. Archivos relevantes

| Archivo | Tipo | Relevancia |
|---------|------|------------|
| `AGENTS.md` | convenciones | Define naming, documentación, versionado, y separación Makefile/Justfile |
| `scripts/install/create_usb_unix.sh` | entry | Script más complejo (360 LOC), manipula discos con `dd`, 116 líneas duplicadas |
| `scripts/install/format_usb_unix.sh` | entry | Segundo más complejo (372 LOC), manipula discos con `mkfs`, 116 líneas duplicadas |
| `Makefile` | build | Verificación de sintaxis (`make check`), empaquetado (`make dist`) |
| `Justfile` | task runner | Punto de entrada documentado para usuarios, solo 3/24 scripts integrados |
| `make/check.mk` | build | Implementa `check-syntax` y `shellcheck` |
| `docs/install/create_usb_unix.md` | doc | Documentación de referencia — ejemplo de la plantilla definida en AGENTS.md |
| `.gitignore` | config | Excluye binarios, archivos Apple, `.env`, y `.opencode/` local |
| `scripts/macos/clean_apple_meta_macos.sh` | entry | Único script solo-macOS (190 LOC), referencia de script específico de plataforma |
| `scripts/network/wifi_connect_linux.sh` | entry | Ejemplo de script Linux bien documentado (100 LOC, doc completa, usa nmcli) |
