---
title: Guía de runtimes Java, GraalVM y Node.js
description: Instalación, selección y reparación de runtimes gestionados por los instaladores Rafex
tags:
  - instalación
  - java
  - graalvm
  - nodejs
  - mise
---

# Guía de runtimes Java, GraalVM y Node.js

Esta es la referencia práctica para instalar Java, GraalVM y Node.js en Debian
mediante los instaladores del repositorio. Los runtimes se descargan desde sus
fuentes oficiales, se verifican y se instalan dentro del usuario. `mise` solo
registra, selecciona y expone esas instalaciones mediante shims; no debe
descargar runtimes por su cuenta.

La guía aplica a la ThinkPad y a otras instalaciones Linux compatibles. No
instala Java ni Node.js en `/usr/lib`, no reemplaza el Java del sistema y no
requiere `sudo` para los instaladores de runtimes.

## Índice

- [Elección rápida](#eleccion-rapida)
- [Requisitos](#requisitos)
- [Flujo recomendado](#flujo-recomendado)
- [Instalar Java](#instalar-java)
- [Instalar GraalVM](#instalar-graalvm)
- [Instalar Node.js](#instalar-nodejs)
- [Seleccionar una versión](#seleccionar-una-version)
- [Verificar el resultado](#verificar-el-resultado)
- [Reparar una instalación directa de mise](#reparar-una-instalacion-directa-de-mise)
- [Ubicaciones y archivos](#ubicaciones-y-archivos)
- [Protecciones](#protecciones)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Elección rápida

| Necesidad | Comando |
|---|---|
| Java general y compatibilidad | `just install-java-runtime --provider temurin --version 25 --image jdk --apply` |
| GraalVM Community para Java, Native Image o herramientas Graal | `just install-java-runtime --provider graalvm-community --version latest --image jdk --apply` |
| Node.js estable de largo soporte | `just install-node-runtime --version lts --apply` |
| Maven | `just install-build-runtime --tool maven --version latest --apply` |
| Gradle | `just install-build-runtime --tool gradle --version latest --apply` |

Los comandos anteriores son independientes: instala solo lo que necesites.
GraalVM requiere siempre `--image jdk`; no existe una variante `jre` admitida
por este instalador.

## Requisitos

Ejecuta los comandos como usuario normal desde la raíz del repositorio. La
estación debe tener `mise` instalado y disponible en `~/.local/bin/mise` o en
`PATH`; el instalador puede registrar automáticamente cada runtime en mise.

Para preparar la estación completa, sin instalar todavía runtimes grandes:

```bash
just install-terminal-workstation --check
just install-terminal-workstation --plan --stage runtimes
```

Si faltan dependencias básicas en Debian, prepáralas una sola vez:

```bash
sudo apt-get install python3 curl ca-certificates tar xz-utils unzip coreutils
```

Los instaladores no usan `sudo` para descargar ni escribir los runtimes. El
`sudo` anterior solo prepara paquetes del sistema cuando realmente faltan.

## Flujo recomendado

### 1. Consultar antes de descargar

```bash
just install-java-runtime --provider graalvm-community --version latest --plan
just install-node-runtime --version lts --plan
```

`--plan` consulta metadata y muestra versión, archivo, checksum y destino; no
descarga ni modifica el sistema.

### 2. Instalar el runtime elegido

```bash
just install-java-runtime --provider graalvm-community --version latest --image jdk --apply
just install-node-runtime --version lts --apply
```

### 3. Preparar el selector opcional

```bash
just install-runtime-switcher --check
just install-runtime-switcher --apply
reload-bash
```

El selector instala la función `runtime-use` y conserva `JAVA_HOME` en la
ruta estable `~/.local/share/java-runtimes/current-java`.

### 4. Verificar en una shell nueva

```bash
mise current
runtime-use --list java
runtime-use --list node
java --version
node --version
echo "$JAVA_HOME"
readlink -f "$JAVA_HOME"
```

Abre una nueva shell de login si la shell actual conserva variables antiguas.

## Instalar Java

El instalador es `scripts/install/install_java_runtime_linux.sh` y se invoca
mediante la tarea `install-java-runtime`.

### Temurin: opción general recomendada

```bash
just install-java-runtime --provider temurin --version 25 --image jdk --apply
```

Para una versión concreta distinta:

```bash
just install-java-runtime --provider temurin --version 21 --image jdk --apply
```

### Otros proveedores

```bash
# IBM Semeru
just install-java-runtime --provider semeru --version latest --image jdk --apply

# Oracle GraalVM
just install-java-runtime --provider graalvm-oracle --version latest --image jdk --apply
```

Los proveedores admitidos son `temurin`, `graalvm-community`,
`graalvm-oracle` y `semeru`. Puedes consultar el catálogo sin instalar:

```bash
just scrape-java-runtimes --provider all --pretty
```

## Instalar GraalVM

GraalVM Community se instala como un proveedor Java separado, pero el
instalador propio lo registra también para que el selector `runtime-use` pueda
mostrarlo.

### Última versión disponible

```bash
just install-java-runtime \
  --provider graalvm-community \
  --version latest \
  --image jdk \
  --apply
```

### Versión fija reproducible

```bash
just install-java-runtime \
  --provider graalvm-community \
  --version 25.3.4.1 \
  --image jdk \
  --apply
```

Antes de una versión fija, confirma que existe para la arquitectura de la
ThinkPad:

```bash
just scrape-java-runtimes \
  --provider graalvm-community \
  --version 25.3.4.1 \
  --pretty
```

Verifica que realmente se está usando GraalVM y no Temurin:

```bash
mise current
mise which java
java -version
```

Si el selector está instalado, usa el identificador exacto que aparezca en la
lista. Por ejemplo:

```bash
runtime-use --list java
runtime-use java graalvm-25.3.4.1
reload-bash
java -version
```

Un número como `25` normalmente selecciona Temurin; para GraalVM utiliza el
identificador `graalvm-VERSION` mostrado por `runtime-use --list java`.

## Instalar Node.js

El instalador es `scripts/install/install_node_runtime_linux.sh` y se invoca
mediante `install-node-runtime`.

### LTS actual

```bash
just install-node-runtime --version lts --apply
```

### Versión fija

```bash
just install-node-runtime --version 24.20.0 --apply
```

Comprueba el resultado:

```bash
mise current
mise which node
node --version
npm --version
```

Para cambiar posteriormente:

```bash
runtime-use --list node
runtime-use node 24.20.0
reload-bash
node --version
```

## Seleccionar una versión

El selector `runtime-use` es opcional. Si no está instalado, puedes trabajar
con los shims y la selección global de `mise`; para una experiencia persistente
con `JAVA_HOME`, se recomienda instalarlo:

```bash
just install-runtime-switcher --apply
reload-bash
```

Comandos habituales:

```bash
# Listar las opciones disponibles
runtime-use --list java
runtime-use --list node

# Selección global
runtime-use java temurin-25
runtime-use java graalvm-25.3.4.1
runtime-use node 24.20.0

# Selección solo para el proyecto actual
runtime-use --local java 21
runtime-use --local node 20

# Estado y rutas efectivas
runtime-use current
mise current
mise which java
mise which node
```

Usa los nombres exactos listados por `runtime-use --list`; no inventes un
alias de versión.

## Verificar el resultado

La comprobación mínima para Java y Node.js es:

```bash
command -v java
command -v node
java --version
node --version
printf 'JAVA_HOME=%s\n' "$JAVA_HOME"
readlink -f "$JAVA_HOME"
```

Para confirmar que los binarios vienen de las instalaciones gestionadas:

```bash
mise which java
mise which node
```

La ruta de Java debe resolver a `~/.local/share/java-runtimes/` o a un enlace
de `mise` que finalmente resuelva allí. Node.js debe resolver a
`~/.local/share/node-runtimes/` o a su enlace gestionado.

Maven y Gradle tienen un instalador separado:

```bash
just install-build-runtime --tool maven --version latest --apply
just install-build-runtime --tool gradle --version latest --apply
mvn --version
gradle --version
```

## Reparar una instalación directa de mise

Si antes ejecutaste `mise install` y ahora quieres usar los runtimes
descargados por los instaladores Rafex, ejecuta:

```bash
just reconcile-runtimes --check
just reconcile-runtimes --plan
just reconcile-runtimes --apply
```

Esta reparación:

- vuelve a registrar las rutas de Java/GraalVM, Node.js, Maven y Gradle que
  aparecen en el registro propio;
- corrige la selección global y regenera los shims;
- no descarga runtimes;
- no elimina ninguna instalación.

Comprueba especialmente GraalVM después:

```bash
mise current
mise which java
readlink -f "$(mise which java)"
java -version
```

Solo si quieres eliminar enlaces legacy conocidos y has revisado el plan,
existe esta operación más amplia:

```bash
just reconcile-runtimes --apply --purge-legacy
```

`--purge-legacy` puede eliminar rutas legacy conocidas de Node.js, Maven,
Gradle y Java/GraalVM en la misma ejecución. No lo uses si solo quieres
reparar GraalVM. Las rutas propias no registradas quedan fuera de la purga.

## Ubicaciones y archivos

| Elemento | Ubicación |
|---|---|
| Java instalado por Rafex | `~/.local/share/java-runtimes/` |
| Enlace Java activo | `~/.local/share/java-runtimes/current-java` |
| Node.js instalado por Rafex | `~/.local/share/node-runtimes/` |
| Maven y Gradle instalados por Rafex | `~/.local/share/build-runtimes/` |
| Registro de runtimes | `~/.local/share/rafex-runtimes/registry.tsv` |
| Configuración global de mise | `~/.config/mise/config.toml` |
| Shims de mise | `~/.local/share/mise/shims/` |

No muevas manualmente los directorios ni reemplaces los enlaces de `current-*`.
Usa los instaladores y `runtime-use` para conservar el registro y la selección.

## Protecciones

- `--check` y `--plan` son de solo lectura.
- Los instaladores descargan desde URLs oficiales y verifican checksums antes
  de extraer.
- No se ejecuta `mise install`.
- No se usa `sudo` para instalar runtimes en el usuario.
- Java, Node.js, Maven y Gradle no reemplazan los paquetes del sistema.
- Se conservan respaldos fechados cuando se reemplaza un destino existente.
- La purga de legacy es opcional y requiere `--purge-legacy` explícito.

## Fallos conocidos

### `mise which java` apunta a `~/.local/share/mise/installs/graalvm`

**Causa:** `mise` puede mostrar su backend o un enlace legacy aunque el destino
real ya sea un runtime instalado por Rafex.

**Solución:** ejecuta `just reconcile-runtimes --apply` y comprueba el destino
final con `readlink -f "$(mise which java)"`. Si termina en
`~/.local/share/java-runtimes/graalvm-community/`, GraalVM ya es el runtime
gestionado.

### `runtime-use java 25` activa Temurin y no GraalVM

**Causa:** los números de versión se reservan normalmente para Temurin.

**Solución:** lista los identificadores y selecciona el prefijo de GraalVM:

```bash
runtime-use --list java
runtime-use java graalvm-25.3.4.1
```

### `java --version` no cambia en la shell actual

**Causa:** la shell conserva el `PATH`, `JAVA_HOME` o el hook de `mise` anterior.

**Solución:** ejecuta `reload-bash` o abre una nueva shell de login y repite
`mise current`, `mise which java` y `java --version`.

### `runtime-use: command not found`

**Causa:** todavía no está instalado el selector.

**Solución:** ejecuta `just install-runtime-switcher --apply` y luego
`reload-bash`.

## Changelog

### [Unreleased]

- **docs:** centralizar instalación, selección, verificación y reparación de
  Java, GraalVM, Node.js, Maven y Gradle.
