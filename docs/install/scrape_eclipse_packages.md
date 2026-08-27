# scrape_eclipse_packages.py

Extrae desde Eclipse.org la versión vigente, los enlaces Linux por arquitectura
y el checksum SHA-512 de los paquetes Java y Enterprise Java/Web.

- **Ruta:** `scripts/install/scrape_eclipse_packages.py`
- **SO requerido:** macOS, Linux
- **Dependencias:** `python3` estándar, acceso HTTPS a `www.eclipse.org`

---

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

- Python 3.10 o posterior recomendado.
- Conectividad HTTPS a la página de paquetes y al endpoint de checksums de
  Eclipse.
- No requiere instalar el framework Scrapy ni paquetes Python externos.

## Uso

Extraer ambos paquetes para la arquitectura local:

```sh
just scrape-eclipse-packages --package all --pretty
```

Extraer únicamente Enterprise Java/Web para `x86_64`:

```sh
python3 scripts/install/scrape_eclipse_packages.py \
  --package jee --architecture x86_64 --pretty
```

El resultado es JSON y contiene `release`, `filename`, `direct_url`,
`checksum` y `checksum_url`. El instalador de Eclipse consume este mismo
formato internamente.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--package <tipo>` | — | `java`, `jee` o `all`; default: `all` |
| `--architecture <arquitectura>` | — | `x86_64`, `aarch64` o `riscv64` |
| `--timeout <segundos>` | — | Tiempo máximo por solicitud; default: `30` |
| `--pretty` | — | Formatea el JSON con indentación |
| `--help` | `-h` | Muestra la ayuda |

## Variables de entorno

El scraper no utiliza variables de entorno. La URL de Eclipse se mantiene
definida en el código para evitar seleccionar espejos o sitios no previstos.

## Ejemplos

### Ambos paquetes y JSON legible

```sh
just scrape-eclipse-packages --package all --pretty
```

### Paquete Java estándar

```sh
python3 scripts/install/scrape_eclipse_packages.py \
  --package java --architecture x86_64 --pretty
```

### Integración con el instalador

```sh
just install-eclipse-ide --package jee --plan
just install-eclipse-ide --package jee --apply
```

## Protecciones de seguridad

- Consulta únicamente `https://www.eclipse.org/downloads/packages/` y el
  endpoint HTTPS de checksums de Eclipse.
- Rechaza enlaces de paquetes que no apunten a `www.eclipse.org`.
- El instalador verifica el SHA-512 publicado antes de extraer el archivo.
- No ejecuta contenido descargado ni requiere credenciales.
- Usa la URL de descarga directa de Eclipse, que puede redirigir a un espejo
  oficial para obtener el archivo.

## Fallos conocidos

### `no se encontró descarga Linux <arquitectura>`

**Causa:** Eclipse no publica ese paquete para la arquitectura solicitada o
la estructura HTML de la página cambió.

**Solución:** revisa manualmente la página oficial de paquetes y ejecuta el
scraper con otra arquitectura disponible.

### `Eclipse no publicó un SHA-512`

**Causa:** el endpoint de checksums no está disponible temporalmente o el
archivo ya no tiene una suma publicada.

**Solución:** no instales el archivo sin verificar. Repite más tarde o revisa
la página oficial.

## Changelog

### [Unreleased]

- **feat:** extraer paquetes Eclipse Java y Enterprise Java/Web con checksum
  SHA-512 para el instalador Debian/Linux.
