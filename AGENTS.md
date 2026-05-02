# AGENTS.md

Guía de convenciones para documentar scripts en este repositorio.

---

## Estructura de documentación para scripts

Cada script debe tener un archivo Markdown de documentación en:

```
docs/<categoria>/<nombre-del-script>.md
```

Donde `<categoria>` refleja el subdirectorio dentro de `scripts/`.

**Ejemplo:**

| Script | Documentación |
|---|---|
| `scripts/install/create_usb_macos_debian.sh` | `docs/install/create_usb_macos_debian.md` |

---

## Plantilla de documento

El archivo Markdown debe seguir esta estructura en orden:

```markdown
# <nombre-del-script>

Descripción breve en una o dos líneas.

- **Ruta:** `scripts/<categoria>/<nombre>.sh`
- **SO requerido:** <macOS | Linux | ambos>
- **Dependencias:** <lista de herramientas externas>

---

## Índice
## Requisitos
## Uso
## Opciones
## Variables de entorno
## Archivo .env        ← solo si el script soporta .env
## Ejemplos
## Protecciones de seguridad   ← solo si aplica
## Fallos conocidos
## Changelog
```

---

## Sección: Opciones

Documentar cada opción en tabla:

```markdown
| Opción | Alias | Descripción |
|---|---|---|
| `--from <archivo>` | `-f` | Descripción |
```

---

## Sección: Variables de entorno

Documentar variables en tabla. Indicar el orden de prioridad cuando
coexisten argumentos CLI, variables de entorno y `.env`.

---

## Sección: Ejemplos

Incluir al menos:
- Forma explícita/recomendada
- Forma con variables de entorno
- Forma con archivo `.env` (si aplica)
- Modo legacy / compatibilidad (si aplica)

---

## Sección: Fallos conocidos

Formato por entrada:

```markdown
### `mensaje de error o título del fallo`

**Causa:** ...
**Solución:** ...
```

Agregar aquí los errores que se encuentren en uso real, con su causa y solución.

---

## Sección: Changelog

Usar formato [Keep a Changelog](https://keepachangelog.com/es/1.0.0/) adaptado con conventional commits.

```markdown
### [Unreleased]
- Cambios pendientes de release.

### vX.Y.Z — YYYY-MM-DD

**<tipo>:** resumen del cambio.

- Detalle 1
- Detalle 2
```

**Tipos válidos:** `feat`, `fix`, `style`, `refactor`, `docs`, `chore`.

---

## Convención de versiones para scripts

Usar versionado semántico **vMAJOR.MINOR.PATCH**:

| Tipo de cambio | Incremento |
|---|---|
| Cambio incompatible o reescritura | MAJOR |
| Nueva funcionalidad sin romper compatibilidad | MINOR |
| Corrección de bug o ajuste menor | PATCH |

---

## Referencias

- Documentación de ejemplo: [docs/install/create_usb_macos_debian.md](docs/install/create_usb_macos_debian.md)
