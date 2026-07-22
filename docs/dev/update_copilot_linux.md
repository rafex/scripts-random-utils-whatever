# update_copilot_linux.sh

Variante de `update_copilot_chat_linux.sh` con múltiples flags de API (914, 2151, 103, 870, 0) para mayor compatibilidad con el Marketplace de VS Code cuando el flag por defecto no devuelve resultados.

Mismas opciones, variables y funcionamiento que `update_copilot_chat_linux.sh`. La diferencia es que prueba varios valores de `flags` en la query hasta encontrar uno que devuelva versiones suficientes.

- **Ruta:** `scripts/dev/update_copilot_linux.sh`
- **SO requerido:** Linux, macOS
- **Dependencias:** `curl`, `jq`, `sort`, `awk`

---

## Uso

```sh
./scripts/dev/update_copilot_linux.sh [opciones]
```

---

## Opciones

| Opción | Descripción |
|---|---|
| `--install` | Instala la extensión tras descargar |
| `--no-force` | Instala sin `--force` |
| `--out DIR` | Directorio de salida (default: `./vsix`) |
| `--bin codium\|code` | Binario del editor |
| `-h, --help` | Mostrar ayuda |

---

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `OUT_DIR` | `./vsix` | Directorio de descarga |
| `INSTALL` | `0` | Instalar tras descargar |
| `FORCE` | `1` | Usar `--force` al instalar |
| `EDITOR_BIN` | auto | Binario del editor |

---

## Ejemplos

```sh
./scripts/dev/update_copilot_linux.sh

./scripts/dev/update_copilot_linux.sh --install --bin codium
```

---

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/update-copilot.sh`.
