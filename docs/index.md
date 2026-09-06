---
title: Inicio
description: Guía de uso de scripts portables para macOS y Linux
tags:
  - onboarding
  - referencia
---

# scripts-random-utils-whatever

Colección de scripts de utilidad para macOS y Linux, organizada por categoría y con tareas de ejecución mediante `just`.

## Inicio rápido

Clona el repositorio y lista las tareas disponibles:

```bash
git clone https://github.com/rafex/scripts-random-utils-whatever.git
cd scripts-random-utils-whatever
just
```

Para validar scripts y documentación:

```bash
make check
make docs
```

Para previsualizar el sitio:

```bash
make serve
```

## Organización

- `scripts/`: scripts ejecutables por categoría.
- `docs/`: documentación operativa y conceptual.
- `just/`: tareas que ejecutan scripts.
- `make/`: validación, checksums, documentación y empaquetado.
- `site/`: sitio MkDocs generado; no se versiona.

## Convención de plataformas

El sufijo del nombre indica el soporte declarado:

| Sufijo | Plataforma |
|---|---|
| `_macos` | macOS |
| `_linux` | Linux |
| `_unix` | macOS y Linux |

Consulta el [catálogo de scripts](catalogo-scripts.md) para conocer dependencias, privilegios y riesgos antes de ejecutar una operación.

## Documentos relacionados

- [Instalación segura de Ether-rules MCP](install/install_ether_rules_mcp_unix.md).
- [Instalación de la estación de terminal](install/install_terminal_workstation_linux.md).
- [Guía de runtimes Java, GraalVM y Node.js](install/runtime_runtimes_linux.md).
- [Migración segura de laptop](install/migrate_laptop_linux.md).
