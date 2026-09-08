---
title: thinkpad_config_audit_linux.sh
description: Audita propietarios y dependencias de la configuración ThinkPad.
tags:
  - sistema
  - thinkpad
  - auditoría
---

# thinkpad_config_audit_linux.sh

Audita la propiedad de configuraciones del perfil ThinkPad y detecta regresiones
sin cambiar la sesión ni archivos del sistema.

- **Ruta:** `scripts/system/thinkpad_config_audit_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, `rg`; opcionalmente i3, systemd y procps para comprobaciones ampliadas.

---

## Índice

## Requisitos

Debe ejecutarse desde el repositorio que contiene el perfil
`thinkpad-x1-yoga-1st`. No requiere `sudo`.

## Uso

```bash
just thinkpad-config-audit --status
just thinkpad-config-audit --check
just thinkpad-config-audit --report
```

El informe incluye, para cada recurso, su propietario único, archivo o bloque,
dependencias, validador, exclusiones y política. El inventario de scripts se
genera en cada ejecución para que refleje los scripts presentes en el checkout.
También separa los destinos físicos compartidos —por ejemplo,
`~/.config/i3/config`— de sus bloques administrados y lista los candidatos que
escriben esas superficies, indicando si usan fragmentos generados, un guard de
propietario, una política de archivo exclusivo o si están clasificados como
`seed-only`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--status` | — | Muestra el estado de recursos y regresiones conocidas. |
| `--check` | — | Igual que estado, pero falla si encuentra una inconsistencia. |
| `--report` | — | Emite un informe Markdown con tabla de scripts y grafo Mermaid. |
| `--output <archivo>` | — | Guarda el informe fuera del repositorio con permisos `0600`. |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `XDG_CONFIG_HOME` | Directorio de configuración a auditar; por defecto `~/.config`. |
| `XDG_STATE_HOME` | Directorio de estado Rafex; por defecto `~/.local/state`. |
| `RAFEX_THINKPAD_HISTORY` | Repositorio local que registra lo instalado en la ThinkPad; por defecto `~/.local/share/rafex-thinkpad`. |

## Ejemplos

```bash
# Recomendado: revisión sin cambios.
just thinkpad-config-audit --check

# Guardar evidencia privada antes de instalar otro componente.
just thinkpad-config-audit --report \
  --output "$HOME/.local/state/rafex/thinkpad-config/audit-$(date +%F).md"
```

## Protecciones de seguridad

- Nunca modifica i3, EWW, Picom, Conky, Openbox, Xorg ni `/etc`.
- Solo escribe un informe cuando se proporciona explícitamente `--output`.
- No incluye secretos, contenido de mensajes ni configuraciones completas.
- Clasifica Firefox OS, Android y runtimes de desarrollo como fuera de la
  superficie del escritorio: aparecen en el inventario, pero no se tratan como
  propietarios de i3, EWW, Picom, Conky o energía.
- Rechaza un registro que asigne el mismo recurso o el mismo destino/bloque a
  más de un propietario.
- Señala los destinos físicos compartidos como una condición que requiere
  composición por fragmentos; no los considera seguros solo porque cada bloque
  tenga una etiqueta diferente.
- Comprueba que `~/.local/share/rafex-thinkpad` sea un repositorio Git con al
  menos un commit y sin cambios pendientes. Esa carpeta es historial local de
  lo instalado, no un clon fuente del repositorio replicador.

## Fallos conocidos

### `Picom no está activo`

**Causa:** la unidad `rafex-picom.service` no está instalada o el autostart
genérico de Dex sigue siendo el único mecanismo disponible.

**Solución:** instalar y validar el servicio Rafex antes de modificar Picom.

### `EWW SCSS ausente`

**Causa:** el perfil fue copiado sin ejecutar el instalador EWW o el selector de
tema no pudo materializar la hoja de estilo.

**Solución:** ejecutar `just install-eww --apply` después de revisar el plan.

### `historial ThinkPad sin commits`

**Causa:** todavía no se ha adoptado el estado instalado en
`~/.local/share/rafex-thinkpad`.

**Solución:** no ejecutar aún una migración destructiva; primero generar un
manifiesto de archivos instalados, conservar respaldos y crear el primer commit
local de adopción.

## Changelog

### [Unreleased]

**feat:** incorpora auditoría de propietarios, recursos y dependencias ThinkPad.

**fix:** detecta colisiones por destino físico y valida el historial local de la
ThinkPad.
