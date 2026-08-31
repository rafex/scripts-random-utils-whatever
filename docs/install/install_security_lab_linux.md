---
title: install_security_lab_linux.sh
description: Instala herramientas de auditoría y laboratorio de seguridad por etapas en Debian
tags:
  - instalación
  - seguridad
  - laboratorio
  - thinkpad
---

# install_security_lab_linux.sh

Instala herramientas de auditoría defensiva y laboratorio en Debian por etapas. El script no ejecuta escaneos, capturas, ataques, cracking ni servicios de laboratorio.

- **Ruta:** `scripts/install/install_security_lab_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `apt-get`, `apt-cache`, `dpkg-query`, `sudo`; `systemctl`, `iw`, `ethtool` y `getcap` son opcionales para el diagnóstico.

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

- Debian con fuentes APT habilitadas y candidatos disponibles para la etapa elegida.
- Ejecutar el script como usuario normal con `sudo` disponible. No se debe invocar como `root`.
- Para `--apply`, la cuenta debe poder usar `sudo` para `apt-get` y, en la etapa `virtualization`, para añadir al usuario al grupo `kvm`.
- Las etapas `wireless`, `web`, `forensics`, `credentials` y `all` requieren una autorización consciente durante la ejecución o la opción explícita `--yes`.
- Las capturas en vivo de Wireshark requieren privilegios en el momento de capturar; el instalador no concede capacidades persistentes a `dumpcap`.

## Uso

La instalación base es deliberadamente independiente del perfil gráfico, NetworkManager, UFW, Podman y la configuración de energía de la ThinkPad.

```bash
just install-security-lab --check
just install-security-lab --plan --stage base
just install-security-lab --apply --stage base
just install-security-lab --status
```

Las demás etapas se instalan explícitamente:

```bash
just install-security-lab --apply --stage wireless
just install-security-lab --apply --stage web
just install-security-lab --apply --stage forensics
just install-security-lab --apply --stage credentials
just install-security-lab --apply --stage virtualization
```

`--stage all` instala todas las etapas y no es el valor predeterminado.

### Etapas

| Etapa | Paquetes principales | Propósito |
|---|---|---|
| `base` | `nmap`, `ncat`, `ndiff`, `tcpdump`, `tshark`, `wireshark`, `mtr-tiny`, `bind9-dnsutils`, `whois`, `arp-scan`, `ethtool`, `iw`, `socat`, `lsof`, `strace`, `usbutils` | Diagnóstico de red, sistema y tráfico propio |
| `wireless` | `aircrack-ng`, `hcxdumptool`, `hcxtools`, `macchanger`, `wireless-tools` | Laboratorios inalámbricos autorizados |
| `web` | `ffuf`, `gobuster`, `nikto`, `whatweb`, `mitmproxy`, `dirb` | Pruebas web en aplicaciones propias o autorizadas |
| `forensics` | `sleuthkit`, `testdisk`, `yara`, `hashdeep`, `ssdeep`, `rkhunter` | Análisis de copias e imágenes forenses |
| `credentials` | `john`, `hydra`, `hashcat` | Laboratorios de credenciales propios |
| `virtualization` | `qemu-system-x86`, `qemu-utils`, libvirt, `virt-manager`, `virt-viewer`, OVMF y `swtpm` | Máquinas virtuales aisladas |

La disponibilidad de `nmap`, `aircrack-ng`, `tshark`, libvirt y `virt-manager` en Debian Forky puede consultarse en sus páginas oficiales de paquetes: [Nmap](https://packages.debian.org/forky/nmap), [Aircrack-ng](https://packages.debian.org/forky/aircrack-ng), [TShark](https://packages.debian.org/forky/tshark), [libvirt](https://packages.debian.org/forky/libvirt-daemon-system) y [virt-manager](https://packages.debian.org/forky/virt-manager).

`kismet` se mantiene como herramienta opcional documentada, pero fue retirado
de Debian Testing/Forky y no bloquea la etapa `wireless`; el instalador no
añade repositorios externos. Para virtualización se usa `qemu-system-x86`, que
es el paquete disponible en Forky; no se solicita el nombre ausente
`qemu-kvm`.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Comprueba Debian y muestra el estado de los paquetes de la etapa; no actualiza APT. |
| `--plan` | `--dry-run` | Muestra los paquetes y acciones previstas sin ejecutar `sudo`, escribir archivos ni instalar nada. |
| `--apply` | — | Actualiza índices e instala la etapa seleccionada mediante `sudo`. |
| `--status` | — | Muestra todas las etapas, versiones disponibles, estado de `dumpcap`, Wi-Fi, KVM y servicios. No modifica el sistema. |
| `--stage <etapa>` | — | Selecciona `base`, `wireless`, `web`, `forensics`, `credentials`, `virtualization` o `all`. |
| `--yes` | — | Omite la confirmación de las etapas sensibles; úsalo únicamente tras verificar la autorización del laboratorio. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

El script no utiliza variables de entorno de configuración. La etapa se selecciona exclusivamente mediante `--stage`; el usuario se obtiene de la sesión que ejecuta el script.

## Ejemplos

### Instalación recomendada por fases

```bash
just install-security-lab --check
just install-security-lab --plan --stage base
just install-security-lab --apply --stage base
just install-security-lab --status
```

### Laboratorio inalámbrico con adaptador externo

```bash
just install-security-lab --apply --stage wireless
iw list
iw dev
```

El Wi-Fi interno continúa administrado por NetworkManager. Para modo monitor o inyección se recomienda evaluar un adaptador USB externo compatible; la guía de Aircrack-ng explica que el hardware debe soportar esas capacidades: [Aircrack-ng Newbie Guide](https://www.aircrack-ng.org/doku.php?id=newbie_guide).

### Captura de tráfico propio

La política del perfil no añade `rafex` al grupo `wireshark`, no configura SUID ni capacidades persistentes en `dumpcap` y no ejecuta la interfaz gráfica como root.

```bash
sudo dumpcap -D
sudo dumpcap -i wlp4s0 -w captura.pcapng
wireshark captura.pcapng
```

La captura requiere autorización sobre la red y el equipo observados. Wireshark documenta la separación entre la captura privilegiada y el análisis de archivos: [Capture privileges](https://wiki.wireshark.org/CaptureSetup/CapturePrivileges).

### Máquinas virtuales sin bridge físico

```bash
just install-security-lab --apply --stage virtualization
newgrp kvm
virsh -c qemu:///session list --all
virt-manager --connect qemu:///session
```

El instalador añade solo el grupo `kvm`. No añade `libvirt`, no crea bridges físicos, no habilita exposición de servicios ni abre puertos en UFW.

### Etapa sensible con confirmación explícita

```bash
just install-security-lab --apply --stage credentials
```

Solo responde `y` si el laboratorio, las cuentas y los datos son tuyos o tienes autorización escrita. El instalador no ejecuta `john`, `hydra` ni `hashcat`.

## Protecciones de seguridad

- `--check`, `--plan` y `--status` son de solo lectura y no solicitan `sudo`.
- `--apply` usa `sudo` para APT y no guarda contraseñas.
- No se ejecutan escaneos, capturas, desautenticación, inyección, MITM, cracking ni comandos inalámbricos activos.
- No se ejecuta `airmon-ng check kill`; NetworkManager mantiene la administración del Wi-Fi interno.
- Kismet y mitmproxy se instalan sin habilitar ni iniciar servicios automáticamente.
- No se instalan wordlists grandes de forma automática.
- El instalador no modifica UFW, NetworkManager, WWAN, i3, Podman, energía, discos ni firmware.
- Las herramientas de forense deben usarse sobre copias o imágenes, no sobre discos montados sin autorización.
- En redes públicas solo debe observarse el propio equipo. Nmap debe utilizarse únicamente sobre sistemas propios o con permiso explícito; consulta sus [consideraciones legales](https://nmap.org/book/legal-issues.html).
- La HD Graphics 520 no es adecuada para cracking GPU intensivo; para laboratorios pequeños `john` es la opción práctica.

## Fallos conocidos

### `uno o más paquetes no tienen candidato APT`

**Causa:** la etapa solicita un paquete que no está disponible en las fuentes habilitadas o los índices APT están desactualizados.

**Solución:** revisa las fuentes de Debian, ejecuta `just install-security-lab --plan --stage <etapa>` y vuelve a intentar `--apply`. El script no sustituye paquetes ni añade repositorios externos.

Si el mensaje aparece para todos los paquetes después de un `apt-get update`
correcto, comprueba el idioma de la sesión. `apt-cache policy` puede mostrar
`Candidato:` en lugar de `Candidate:` cuando `LANG` está en español. El
instalador fuerza `LC_ALL=C` únicamente al leer esa salida, por lo que no es
necesario cambiar el idioma global del sistema.

Cuando el mensaje identifica un paquete concreto, revisa si se trata de una
opción no disponible en Forky. `kismet` aparece como opcional no bloqueante y
`qemu-kvm` ya no forma parte de la lista: `qemu-system-x86` cubre la base de
QEMU/KVM.

### `la confirmación requiere una terminal`

**Causa:** se pidió una etapa sensible desde una ejecución no interactiva.

**Solución:** ejecuta el comando desde una terminal local o una sesión SSH con TTY. Usa `--yes` solo si ya verificaste la autorización y el alcance del laboratorio.

### `dumpcap tiene privilegios persistentes`

**Causa:** la distribución o una configuración anterior dejó SUID o capacidades Linux en `dumpcap`.

**Solución:** revisa `install-security-lab --status`. El script solo informa y no cambia esa política automáticamente; elimina privilegios persistentes únicamente después de revisar la política local y conserva la captura explícita con `sudo dumpcap`.

### El adaptador no ofrece modo monitor o inyección

**Causa:** esas capacidades dependen del chipset, firmware y driver del adaptador; no son una propiedad garantizada del paquete.

**Solución:** usa un adaptador USB compatible y conserva el Wi-Fi interno para NetworkManager. No ejecutes `airmon-ng check kill` en la interfaz principal.

### `no se detectó vmx/svm` o `/dev/kvm ausente`

**Causa:** la virtualización puede estar desactivada en firmware o el kernel no expone KVM.

**Solución:** revisa la opción Intel VT-x/AMD-V en firmware y vuelve a comprobar `test -e /dev/kvm`. No se modifica BIOS automáticamente.

### `kismet sin candidato Debian`

**Causa:** Kismet fue retirado de Debian Testing/Forky.

**Solución:** la etapa `wireless` continúa con `aircrack-ng`, `hcxdumptool`,
`hcxtools`, `macchanger` y `wireless-tools`. Si se necesita Kismet, debe
evaluarse aparte con una fuente oficial compatible, sin incorporarla
automáticamente al instalador ni a la configuración de NetworkManager.

## Changelog

### [Unreleased]

- `feat:` instalador por etapas para base, wireless, web, forense, credenciales y virtualización.
- `fix:` paquetes no disponibles en Forky (`kismet` y `qemu-kvm`) dejan de bloquear las etapas correspondientes.
- `docs:` política de autorización, captura privilegiada y KVM sin bridge físico.

### v1.0.0 — 2026-08-30

**feat:** primera versión del laboratorio opcional de seguridad para Debian ThinkPad.
