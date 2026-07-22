# myip_linux.sh

Obtiene la IP pública consultando 7 servicios distintos y verifica la consistencia de las respuestas.

- **Ruta:** `scripts/network/myip_linux.sh`
- **SO requerido:** Linux, macOS
- **Dependencias:** `curl`

---

## Uso

```sh
./scripts/network/myip_linux.sh
```

---

## Salida de ejemplo

```
IP pública desde varios servicios:

  https://ifconfig.me/ip            203.0.113.42
  https://icanhazip.com             203.0.113.42
  ...

Resumen:
  IP: 203.0.113.42 (consistente en todos los servicios)
```

---

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/myip.sh`.
