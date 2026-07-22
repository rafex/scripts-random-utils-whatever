# jdtls_linux.sh

Lanza Eclipse JDT Language Server para editores como Neovim. Requiere JDTLS instalado en `/opt/github/eclipse.jdt.ls`.

- **Ruta:** `scripts/dev/jdtls_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `java`, JDTLS instalado

---

## Uso

```sh
./scripts/dev/jdtls_linux.sh [workspace_dir]
```

| Argumento | Default | Descripción |
|---|---|---|
| `workspace_dir` | `~/.local/share/nvim/jdtls-workspace/default` | Directorio de workspace |

---

## Variables de entorno

| Variable | Default | Descripción |
|---|---|---|
| `JDTLS_HOME` | `/opt/github/eclipse.jdt.ls` | Ruta de instalación de JDTLS |
| `JAVA_BIN` | `java` | Binario de Java a usar |

---

## Ejemplos

```sh
./scripts/dev/jdtls_linux.sh

./scripts/dev/jdtls_linux.sh /tmp/my-project

JDTLS_HOME=/opt/jdtls JAVA_BIN=/usr/lib/jvm/java-21/bin/java \
  ./scripts/dev/jdtls_linux.sh
```

---

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/jdtls`.
