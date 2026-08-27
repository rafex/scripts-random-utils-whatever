---
title: myip_linux.sh
description: Consulta de la dirección IP pública
tags:
  - red
---

# myip_linux.sh

Obtiene la IP pública consultando 7 servicios distintos y verifica la consistencia de las respuestas.

- **Ruta:** `scripts/network/myip_linux.sh`
- **SO requerido:** Linux, macOS
- **Dependencias:** `curl`

______________________________________________________________________

## Uso

```sh
./scripts/network/myip_linux.sh
```

______________________________________________________________________

## Salida de ejemplo

```
IP pública desde varios servicios:

  https://ifconfig.me/ip            203.0.113.42
  https://icanhazip.com             203.0.113.42
  ...

Resumen:
  IP: 203.0.113.42 (consistente en todos los servicios)
```

______________________________________________________________________

## Índice

- Requisitos
- Uso
- Opciones
- Variables de entorno
- Ejemplos
- Fallos conocidos
- Changelog

## Requisitos

Revisa las dependencias declaradas al inicio del documento antes de ejecutar el script.

## Opciones

Las opciones disponibles se describen en la ayuda del script y en los ejemplos de esta página. Si no se muestran opciones específicas, se ejecuta sin argumentos.

## Variables de entorno

No se requieren variables adicionales fuera de las indicadas en esta documentación.

## Ejemplos

Consulta los ejemplos de uso incluidos en las secciones anteriores y ejecuta primero un modo de diagnóstico cuando exista.

## Fallos conocidos

No se han registrado fallos adicionales; conserva la salida del comando para diagnosticar cualquier incidencia.

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/myip.sh`.
