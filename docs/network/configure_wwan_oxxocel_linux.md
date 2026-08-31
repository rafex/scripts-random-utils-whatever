---
title: configure_wwan_oxxocel_linux.sh
description: Configurar datos móviles OXXO Cel y consultar SMS mediante la EM7455 en Linux
tags:
  - red
  - wwan
  - modemmanager
---

# configure_wwan_oxxocel_linux.sh

Configura el módem Sierra Wireless EM7455 de la ThinkPad X1 Yoga para usar
datos móviles OXXO Cel mediante NetworkManager y ModemManager. También permite
listar los SMS que el módem expone al sistema.

- **Ruta:** `scripts/network/configure_wwan_oxxocel_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** `bash`, `NetworkManager`, `ModemManager`, `nmcli`, `mmcli`, `sudo` solo para `--apply`

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Incidente real: EM7455 en `disabled / low`](#incidente-real-em7455-en-disabled-low)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Protecciones de seguridad](#protecciones-de-seguridad)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

- Debian o una distribución Linux con NetworkManager y systemd.
- Módem WWAN compatible con ModemManager. La ThinkPad X1 Yoga auditada usa una
  Sierra Wireless EM7455 en modo `cdc_mbim`.
- SIM OXXO Cel insertada y detectada. El estado actual puede consultarse sin
  privilegios con `mmcli -L` y `mmcli -m <índice>`.
- El APN oficial para la SIM México es `internet.mvne1.com`.
- Ejecutar el script como el usuario normal, no como root. `--apply` solicita
  privilegios solo mediante `sudo -v` para instalar paquetes y habilitar servicios.

La página vigente de configuración de OXXO Cel está en
[oxxocel.com/apn](https://www.oxxocel.com/apn). Sus instrucciones enlazan con
la configuración de la SIM México en
[my.oxxocel.com/apn](https://my.oxxocel.com/apn).

## Uso

Desde la raíz del repositorio:

```bash
just configure-wwan-oxxocel --check
just configure-wwan-oxxocel --plan
just configure-wwan-oxxocel --apply
just configure-wwan-oxxocel --status
```

`--apply` crea el perfil `OXXO Cel`, pero no enciende una conexión de datos.
Después de insertar la SIM, activa la conexión de forma explícita:

```bash
just configure-wwan-oxxocel --connect
just configure-wwan-oxxocel --disconnect
```

`--connect` debe ejecutarse desde una terminal interactiva del usuario normal.
Activa el radio WWAN con NetworkManager, espera a que ModemManager termine la
transición del módem y sube el perfil por su UUID. No ejecuta `sudo`,
`mmcli --enable` ni comandos AT. Si se invoca por SSH, usa una pseudo-terminal:

```bash
ssh -tt thinkpad 'cd /opt/repository/github/rafex/scripts-random-utils-whatever && just configure-wwan-oxxocel --connect'
```

El script clasifica explícitamente la SIM como ausente, detectada, bloqueada
por PIN/PIN2 o desconocida. También distingue un módem deshabilitado, uno
registrado sin datos y una conexión de datos activa.

`--connect` solo intenta establecer una sesión de datos. Si ModemManager
reporta `sim-pin2`, el script lo muestra como advertencia y continúa con el
intento de NetworkManager; no utiliza funciones especiales de la SIM, no envía
PIN2/PUK2 y no ejecuta comandos AT. Si NetworkManager solicita PIN2, cancela la
petición: no se puede omitir ni adivinar ese código. Que el intento funcione
depende del firmware de la EM7455 y de cómo exponga el bloqueo de la SIM.

Para consultar los SMS almacenados por ModemManager:

```bash
just configure-wwan-oxxocel --sms-list
```

## Incidente real: EM7455 en `disabled / low`

Esta sección conserva el diagnóstico de la ThinkPad X1 Yoga y explica por qué
la conexión terminó funcionando aunque ModemManager mostrara referencias a
PIN2 y `fixed-dialing`. No contiene PIN, PUK, IMEI, IMSI ni credenciales.

### Línea de tiempo

| Observación | Interpretación | Acción segura |
|---|---|---|
| La EM7455 aparecía como `state: disabled` y `power state: low`. | El módem no estaba en una transición operativa para crear una sesión de datos. | Revisar radio WWAN, `rfkill`, firmware y el procedimiento FCC antes de cambiar el APN. |
| `mmcli -m 0 --enable` devolvía `Invalid transition`. | El comando se estaba ejecutando mientras el firmware mantenía el módem en un estado incompatible con esa transición. | No repetir comandos de habilitación a ciegas ni enviar comandos AT. |
| `lsusb` identificó el módulo como `1199:9079`. | Ese identificador corresponde a la Sierra Wireless EM7455 instalada en esta ThinkPad. | Buscar el procedimiento FCC disponible para ese ID. |
| Debian tenía un script FCC disponible, pero no habilitado automáticamente. | Desde ModemManager 1.18.4 los procedimientos FCC disponibles pueden requerir activación explícita por el usuario. | Crear el enlace persistente bajo `/etc/ModemManager/fcc-unlock.d/`. |
| Se activó `/etc/ModemManager/fcc-unlock.d/1199:9079`. | ModemManager pudo ejecutar el procedimiento oficial asociado al módulo al volver a inicializarlo. | Reiniciar únicamente `ModemManager`, sin cambiar firmware ni composición USB. |
| La EM7455 pasó a `state: enabled` y `power state: on`. | El bloqueo de estado FCC/firmware quedó resuelto. | Volver a intentar la conexión con NetworkManager. |
| `--connect` funcionó desde `think:0`, sin sudo, PIN2, PUK2 ni comandos AT. | El problema principal no era el APN `internet.mvne1.com`; era el estado FCC/firmware del módem. | Mantener la conexión de datos bajo NetworkManager y no almacenar secretos. |

### Qué hace el enlace FCC

El paquete de ModemManager puede instalar procedimientos oficiales en:

```text
/usr/share/ModemManager/fcc-unlock.available.d/
```

Esos archivos están disponibles, pero no necesariamente activos. Para la
EM7455 se habilita el procedimiento creando un enlace con el identificador USB
del dispositivo:

```text
/etc/ModemManager/fcc-unlock.d/1199:9079
```

El enlace debe apuntar al archivo disponible de Debian; no se debe copiar,
editar ni reemplazar el script oficial. La activación administrada por este
repositorio se realiza con:

```bash
just configure-wwan-oxxocel --apply
```

Cuando la EM7455 `1199:9079` está conectada y Debian ofrece el procedimiento,
`--apply` crea el directorio, conserva un enlace correcto si ya existe y
reinicia ModemManager para aplicarlo. Si el módulo no está visible por USB,
el script no inventa el enlace: informa que debe repetirse `--apply` después de
insertar o habilitar el módem.

Para comprobarlo sin exponer identificadores de la SIM:

```bash
lsusb -d 1199:9079
test -L /etc/ModemManager/fcc-unlock.d/1199:9079
readlink -f /etc/ModemManager/fcc-unlock.d/1199:9079
systemctl is-active ModemManager
mmcli -L
mmcli -m <índice> | grep -E 'state:|power state:|registration:|packet service state:|lock:|unlock retries:|enabled locks:'
```

La última orden filtra solamente estado operativo y capacidades relevantes; no
se debe guardar una salida completa de `mmcli` porque puede incluir IMEI u otros
identificadores del módem.

La referencia oficial explica que los procedimientos FCC dejaron de habilitarse
por defecto y que las distribuciones pueden instalarlos como archivos
disponibles para que el usuario los active explícitamente: [FCC unlock de
ModemManager](https://mobile-broadband.pages.freedesktop.org/docs/modemmanager/fcc-unlock/).

### PIN normal, PIN2, PUK2 y `fixed-dialing`

| Elemento | Para qué sirve | Relación con los datos LTE |
|---|---|---|
| PIN normal | Desbloquea el uso general de la SIM cuando está protegida. | Puede ser necesario antes de registrar el módem y crear datos. NetworkManager puede solicitarlo mediante `nmcli --ask`. |
| PIN2 | Protege funciones especiales de la SIM, habitualmente relacionadas con marcación fija o servicios suplementarios. | No es el APN ni el PIN normal; su presencia no demuestra por sí sola que los datos estén bloqueados. |
| PUK2 | Código de recuperación del PIN2 después de intentos fallidos. | No debe adivinarse ni probarse en el módem. Un error puede bloquear permanentemente una función de la SIM. |
| `fixed-dialing` | Función de marcación fija que el módem puede anunciar dentro de las capacidades de la SIM. | Puede aparecer junto a `sim-pin2` aunque una sesión de datos LTE funcione correctamente. |
| APN | Nombre del punto de acceso de datos del operador. | Para OXXO Cel es `internet.mvne1.com`; no desbloquea FCC, PIN normal, PIN2 ni PUK2. |

En este caso, `sim-pin2` y `fixed-dialing` fueron señales de una función
especial reportada por el firmware, no una solicitud activa de PIN2 para la
conexión de datos. La evidencia decisiva fue que el módem quedó `enabled / on`,
se registró en LTE, NetworkManager activó el perfil y recibió una dirección IP.

NetworkManager documenta el campo `gsm.pin` como el PIN de la SIM que puede
necesitarse para operar el dispositivo; no define un parámetro de APN para PIN2:
[configuración GSM de NetworkManager](https://networkmanager.dev/docs/api/1.30/settings-gsm.html).

### Diagnóstico reproducible

Usa esta secuencia en la sesión gráfica local o en una terminal SSH con TTY:

```bash
just configure-wwan-oxxocel --check
just configure-wwan-oxxocel --status
just configure-wwan-oxxocel --connect
nmcli device status
nmcli connection show 'OXXO Cel'
```

Interpreta el resultado en este orden:

```text
disabled / low
  -> revisar FCC 1199:9079, WWAN, rfkill y ModemManager;
     no cambiar el APN como primer intento.

sim-missing
  -> revisar inserción, orientación, slot y detección física de la SIM.

sim-pin
  -> usar únicamente la solicitud interactiva de nmcli para el PIN normal;
     no ponerlo en argumentos, scripts, logs ni documentación.

sim-pin2 o fixed-dialing, con módem enabled/registered/connected
  -> tratarlo como advertencia no bloqueante para datos;
     no enviar PIN2, PUK2 ni comandos AT.

registered, sin bearer o sin dirección IP
  -> el módem ve la red, pero el perfil GSM todavía no está conectado o
     NetworkManager no obtuvo una sesión de datos.

connected, packet service attached y dirección IP
  -> datos LTE operativos; el warning de PIN2 no impide esta conexión.
```

El caso histórico de Red Hat muestra una EM7455 con `disabled`, `power state:
low`, `unlock retries: sim-pin2` y `enabled locks: fixed-dialing`, una
combinación que puede desorientar el diagnóstico si se interpreta como una
petición de PIN2 de datos: [caso documentado de EM7455 en Red Hat
Bugzilla](https://bugzilla.redhat.com/show_bug.cgi?id=1379406). El protocolo
MBIM que utiliza `cdc_mbim` define las operaciones de estado, sesión de datos y
mensajería del módem: [documentación de libmbim](https://mobile-broadband.pages.freedesktop.org/docs/libmbim/mbim-protocol/).

### Reconstrucción después de reinstalar Debian

El enlace FCC no contiene secretos y debe volver a generarse como parte de la
reconstrucción del equipo. La secuencia recomendada es:

```bash
cd /opt/repository/github/rafex/scripts-random-utils-whatever
just configure-wwan-oxxocel --check
just configure-wwan-oxxocel --apply
just configure-wwan-oxxocel --status
just configure-wwan-oxxocel --connect
```

`--apply` puede solicitar sudo para paquetes, servicios y el enlace FCC.
`--connect` debe ejecutarse como `rafex`, no requiere sudo y puede solicitar
interactivamente el PIN normal si la SIM lo necesita. No se almacena el PIN y
no se ejecutan operaciones de voz, PIN2, PUK2 ni AT.

Si `--apply` informa que la EM7455 no está visible, habilita WWAN, inserta la
SIM y repite el comando. No crees un enlace a mano hacia una ruta que no exista:
primero debe estar instalado el paquete de ModemManager que proporciona el
archivo bajo `fcc-unlock.available.d`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Audita paquetes, driver, servicios, módem, SIM y perfil sin modificar. |
| `--plan` | `--dry-run` | Muestra paquetes y cambios previstos sin modificar el sistema. |
| `--apply` | — | Instala dependencias, habilita servicios y crea o actualiza el perfil OXXO Cel. |
| `--status` | — | Muestra estado de WWAN, perfil y capacidades sin modificar. |
| `--connect` | — | Activa WWAN y conecta el perfil mediante `nmcli --ask`. |
| `--disconnect` | — | Desconecta el perfil OXXO Cel. |
| `--sms-list` | — | Lista los SMS expuestos por ModemManager. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

| Variable | Predeterminado | Descripción |
|---|---|---|
| `WWAN_OXXOCEL_PROFILE` | `OXXO Cel` | Nombre del perfil NetworkManager que administra el script. |

El APN no se toma de variables de entorno: queda fijado a `internet.mvne1.com`
para evitar configurar accidentalmente un perfil OXXO Cel con otro proveedor.
No se aceptan PIN, usuario ni contraseña como argumentos o variables.

## Ejemplos

Auditoría inicial sin SIM:

```bash
just configure-wwan-oxxocel --check
```

Instalación del soporte y creación del perfil:

```bash
just configure-wwan-oxxocel --apply
```

Conectar manualmente después de insertar la SIM. Si NetworkManager solicita el
PIN, se introduce de forma interactiva y no se guarda en el perfil:

```bash
just configure-wwan-oxxocel --connect
```

Usar otro nombre de perfil sin modificar el APN:

```bash
WWAN_OXXOCEL_PROFILE='OXXO Cel ThinkPad' \
  just configure-wwan-oxxocel --apply
```

Consultar los mensajes recibidos:

```bash
just configure-wwan-oxxocel --sms-list
```

## Protecciones de seguridad

- `--check`, `--plan`, `--status` y `--sms-list` no modifican el sistema.
- `--apply` solicita la contraseña únicamente mediante `sudo -v`.
- No se guardan PIN, usuarios, contraseñas, IMEI ni identificadores del módem.
- El perfil no tiene autoconexión y usa una métrica de ruta alta (`700`) para
  conservar Wi-Fi como conexión preferida.
- El roaming queda desactivado inicialmente (`gsm.home-only yes`).
- No se modifican firmware, composición USB, BIOS, GRUB, particiones, `fstab` ni
  configuraciones de NetworkManager ajenas al perfil administrado.
- El script no usa `ofono`, porque ModemManager y oFono no deben administrar el
  mismo módem simultáneamente.
- No se ejecutan comandos AT ni se detiene ModemManager para acceder directamente
  al nodo MBIM.

## Fallos conocidos

### `sim-missing`

**Causa:** la SIM no está insertada, está mal orientada, el slot está deshabilitado
en firmware o la EM7455 todavía está en bajo consumo.

**Solución:** inserta la SIM, comprueba que WWAN esté habilitado en BIOS y ejecuta
`mmcli -L` y `just configure-wwan-oxxocel --status`. El APN no puede corregir una
SIM que el módem no detecta.

### `modem has no voice capabilities`

**Causa:** la EM7455 de esta ThinkPad no expone capacidades de voz a ModemManager.

**Solución:** las llamadas telefónicas nativas no son posibles con este módulo.
Usa el teléfono, una aplicación VoIP o investiga un reemplazo WWAN compatible con
voz/VoLTE, BIOS, antenas y el operador. No se instalará oFono como supuesto
arreglo.

### `nmcli` no puede modificar el perfil

**Causa:** NetworkManager no está gestionado por el usuario actual o falta la
política polkit de NetworkManager.

**Solución:** valida `systemctl is-active NetworkManager`, el grupo `netdev` y la
configuración de permisos antes de usar `--apply`. No ejecutes todo el script con
`sudo`.

### `failed to modify connection.permissions`

**Causa:** algunas versiones de NetworkManager rechazan el campo reservado vacío
que se expresa como `user:rafex:` o no aceptan permisos restringidos al usuario.

**Solución:** el instalador deja `connection.permissions` vacío, que es la forma
compatible para que NetworkManager permita administrar el perfil al usuario
normal mediante Polkit. Vuelve a ejecutar `--apply` para normalizar un perfil
creado parcialmente.

### `Insufficient privileges` al crear `OXXO Cel`

**Causa:** en Debian, NetworkManager puede reservar la creación o modificación
de perfiles persistentes del sistema para root, aunque el usuario pueda activar
una conexión existente mediante D-Bus/Polkit. Por eso un `nmcli connection add`
ejecutado directamente como `rafex` puede fallar antes de la etapa de conexión.

**Solución:** ejecuta `just configure-wwan-oxxocel --apply` como `rafex`. Esa
acción valida sudo y usa `sudo nmcli` únicamente para crear o normalizar el
perfil `OXXO Cel`; no ejecutes el script completo como root. Después, las
operaciones diarias funcionan sin sudo:

```bash
just configure-wwan-oxxocel --status
just configure-wwan-oxxocel --connect
just configure-wwan-oxxocel --disconnect
```

El script comprueba el UUID devuelto por NetworkManager y modifica el perfil
por UUID, evitando duplicados o cambios ambiguos por nombre. No se instala una
regla Polkit amplia para modificar perfiles globales, porque permitiría alterar
DNS, rutas, proxies y otras conexiones del sistema desde una sesión de usuario.

### `--connect requiere una terminal interactiva`

**Causa:** `nmcli --ask` necesita una entrada de usuario para PIN o secretos y
no debe ejecutarse desde una tubería sin TTY.

**Solución:** ejecútalo desde Alacritty/tmux o usa `ssh -tt`. El PIN, si se
solicita, se escribe interactivamente y no se guarda.

### `el módem permanece deshabilitado`

**Causa:** el firmware, BIOS, `rfkill` o ModemManager mantienen WWAN apagado;
también puede estar ocurriendo una transición lenta después de activar el
radio.

**Solución:** revisa `nmcli radio`, `rfkill list`, WWAN en BIOS y
`mmcli -m <índice>`. Reiniciar ModemManager es una acción administrativa
separada y no la ejecuta `--connect`.

### `la SIM está bloqueada por PIN2`

**Causa:** ModemManager reporta explícitamente `sim-pin2`; el PIN2 no es el PIN
normal de datos.

**Solución:** `--connect` intenta primero una conexión de datos sin enviar PIN2.
Si la EM7455 permite datos en ese estado, la conexión puede funcionar. Si
NetworkManager solicita PIN2 o el módem permanece `disabled`, cancela la
petición y será necesario obtener PIN2/PUK2 del operador o corregir el estado
del firmware. No adivines, pases ni guardes el PIN2 en el perfil.

### `módem registrado en la red, pero todavía sin conexión de datos`

**Causa:** la SIM ya está registrada, pero el perfil GSM aún no fue activado o
NetworkManager no obtuvo una dirección IP.

**Solución:** ejecuta `--connect`, revisa `nmcli device status` y consulta el
journal de NetworkManager usando el UUID que muestra `--status`.

### `campo «NAME» no válido` al consultar el perfil

**Causa:** algunas versiones recientes de NetworkManager ya no aceptan los
alias abreviados `NAME`, `TYPE`, `AUTOCONNECT` o `DEVICE` en `nmcli -f` para
perfiles de conexión.

**Solución:** el instalador consulta los nombres completos de propiedades,
como `connection.id`, `connection.type` y `connection.autoconnect`.

### `hay otra conexión con el nombre «OXXO Cel»`

**Causa:** NetworkManager permite perfiles con nombres repetidos y puede
seleccionar uno distinto de forma ambigua si se modifica por nombre.

**Solución:** el instalador localiza el perfil GSM por nombre y tipo, obtiene su
UUID y realiza las modificaciones usando ese UUID. Los duplicados antiguos se
deben revisar y eliminar manualmente por UUID después de confirmar que no están
en uso.

### `ModemManager no detecta ningún módem WWAN`

**Causa:** el módem está deshabilitado, falta el driver, el dispositivo no está
presente o la BIOS no habilita WWAN.

**Solución:** revisa `lsusb`, `lsusb -t`, `lsmod | grep cdc_mbim`,
`nmcli radio` y el estado de ModemManager. No cambies la composición USB sin una
investigación específica del modelo.

### `--sms-list` no muestra mensajes

**Causa:** la SIM no está disponible, el módem no está habilitado o el firmware y
el operador no exponen el almacén SMS por MBIM.

**Solución:** conecta primero el perfil, confirma el registro en red y repite el
comando. La recepción de SMS depende de la SIM, firmware y operador.

## Changelog

### [Unreleased]

**feat:** configurar datos OXXO Cel manualmente y consultar SMS mediante ModemManager.

- Añadir perfil NetworkManager con APN `internet.mvne1.com`.
- Detectar dinámicamente el módem y documentar la ausencia de voz de la EM7455.

**fix:** aceptar la sintaxis de permisos de conexión de NetworkManager en Debian.

**fix:** crear y modificar el perfil persistente con `sudo nmcli` solo durante
`--apply`, validando el UUID antes de continuar; mantener `--connect`,
`--disconnect`, `--status` y `--sms-list` sin sudo.

**fix:** usar propiedades completas de `nmcli` y reportar claramente fallos de `sudo` o `systemctl`.

**fix:** seleccionar y modificar el perfil WWAN por UUID para evitar duplicados.

**fix:** conectar como usuario normal, esperar el estado del módem y clasificar
SIM, registro y conexión de datos sin usar sudo.

**fix:** permitir el intento de datos cuando la SIM reporta `sim-pin2`, sin
enviar códigos PIN/PUK ni comandos AT.

**docs:** documentar el incidente FCC de la EM7455 `1199:9079` y diferenciar
PIN2/fixed-dialing de un bloqueo real de datos.

**fix:** habilitar el procedimiento FCC oficial de Debian durante `--apply`
cuando la EM7455 está presente y hacer compatible la detección del perfil GSM
activo con distintas versiones de `nmcli`.
