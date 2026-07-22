# update_copilot_chat_linux.sh

Descarga la penúltima versión minor de GitHub Copilot Chat (`.vsix`) desde el Marketplace de VS Code. Opcionalmente instala con `codium` o `code` usando `--force`.

- **Ruta:** `scripts/dev/update_copilot_chat_linux.sh`
- **SO requerido:** Linux, macOS
- **Dependencias:** `curl`, `jq`, `sort`

---

## Uso

```sh
./scripts/dev/update_copilot_chat_linux.sh [opciones]
```

---

## Opciones

| Opción | Descripción |
|---|---|
| `--install` | Instala la extensión tras descargar |
| `--no-force` | Instala sin `--force` |
| `--out DIR` | Directorio de salida para el .vsix (default: `./vsix`) |
| `--bin codium\|code` | Binario del editor para instalar |
| `-h, --help` | Mostrar ayuda |

---

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `OUT_DIR` | `./vsix` | Directorio de descarga |
| `INSTALL` | `0` | Instalar tras descargar (`1` = sí) |
| `FORCE` | `1` | Usar `--force` al instalar |
| `EDITOR_BIN` | auto (codium o code) | Binario del editor |

---

## Ejemplos

```sh
./scripts/dev/update_copilot_chat_linux.sh

./scripts/dev/update_copilot_chat_linux.sh --install --bin codium

OUT_DIR=/tmp/vsix INSTALL=1 EDITOR_BIN=code \
  ./scripts/dev/update_copilot_chat_linux.sh
```

---

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/update_copilot_chat.sh`.
