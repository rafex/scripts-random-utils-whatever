---
title: configure_kvm_linux.sh
description: Configura QEMU/KVM y libvirt para virtualización privada de usuario en Debian
tags:
  - instalación
  - virtualización
  - qemu
  - kvm
---

# configure_kvm_linux.sh

Prepara QEMU/KVM y libvirt para ejecutar máquinas virtuales desde la sesión
del usuario `rafex`, sin usar `qemu:///system`, bridges físicos ni puertos
adicionales en UFW.

- **Ruta:** `scripts/install/configure_kvm_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** `bash`, `dpkg-query`, `apt-cache`, `sudo`; `virsh`, `qemu-system-x86_64` y `qemu-img` se instalan durante `--apply` si faltan.

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

- Debian con fuentes APT habilitadas.
- CPU con Intel VT-x (`vmx`) o AMD-V (`svm`) habilitado en firmware.
- `sudo` para `--apply`.
- La ejecución debe hacerse como usuario normal, nunca como `root`.

En Debian Forky se utiliza `qemu-system-x86`; no se solicita el paquete
`qemu-kvm`, que no tiene candidato en esta instalación. Consulta el paquete
oficial de [QEMU system x86 en Debian Forky](https://packages.debian.org/forky/qemu-system-x86).

## Uso

Desde la raíz del repositorio:

```bash
just configure-kvm --check
just configure-kvm --plan
just configure-kvm --apply
just configure-kvm --status
```

`--apply` instala, si faltan, QEMU, libvirt, virt-manager, virt-viewer, OVMF
y swtpm. Después prepara:

```text
qemu:///session
~/.local/share/libvirt/images
~/VMs/iso
```

También crea las pools de usuario `rafex-images` y `rafex-iso` cuando no
existen. Una pool con la misma nombre pero una ruta diferente no se modifica.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| `--check` | — | Muestra CPU, `/dev/kvm`, grupos, paquetes, pools y URI sin modificar nada. |
| `--plan` | `--dry-run` | Muestra la instalación y configuración previstas sin ejecutar sudo ni escribir archivos. |
| `--apply` | — | Instala dependencias mediante sudo, prepara la sesión libvirt y crea las pools privadas. |
| `--status` | — | Alias de la auditoría detallada; no modifica el sistema. |
| `--help` | `-h` | Muestra la ayuda. |

## Variables de entorno

No hay variables de configuración propias. Se respetan las variables estándar
`HOME`, `XDG_CONFIG_HOME` y `XDG_DATA_HOME` para calcular las rutas de usuario.
El script no lee archivos `.env` ni guarda credenciales.

## Ejemplos

### Configuración recomendada

```bash
just configure-kvm --check
just configure-kvm --plan
just configure-kvm --apply
```

Si el script añadió el grupo `kvm`, cierra y abre la sesión o ejecuta:

```bash
newgrp kvm
```

### Abrir virt-manager con la sesión de usuario

```bash
virt-manager --connect qemu:///session
virsh -c qemu:///session list --all
```

No ejecutes `virt-manager` con `sudo`: eso abriría otra configuración y puede
llevar a utilizar accidentalmente `qemu:///system`.

### Instalar una VM Debian con red user-mode

```bash
virt-install \
  --connect qemu:///session \
  --name debian-lab \
  --memory 4096 \
  --vcpus 2 \
  --disk pool=rafex-images,size=40,format=qcow2 \
  --cdrom "$HOME/VMs/iso/debian.iso" \
  --network user
```

La red `user` permite salida de la VM sin crear un bridge físico ni publicar
puertos entrantes. Para un laboratorio completamente aislado usa:

```bash
virt-install --connect qemu:///session ... --network none
```

### Diagnóstico

```bash
just configure-kvm --status
virsh -c qemu:///session pool-list --all
virsh -c qemu:///session net-list --all
qemu-img info "$HOME/.local/share/libvirt/images/debian-lab.qcow2"
```

### Compatibilidad con comandos explícitos

Si existe una configuración previa que define otra URI predeterminada, el
script no la sobrescribe. En ese caso utiliza siempre:

```bash
virsh -c qemu:///session list --all
virt-manager --connect qemu:///session
```

## Protecciones de seguridad

- `--check`, `--plan` y `--status` son de solo lectura.
- `--apply` solicita sudo solo para APT y, si es necesario, `usermod -aG kvm`.
- Las VMs se ejecutan como el usuario mediante `qemu:///session`.
- No se añade `rafex` al grupo `libvirt`.
- No se crean bridges, redes NAT del sistema ni reglas nuevas de UFW.
- No se habilita autostart de máquinas virtuales ni se crean servicios de VM.
- Las imágenes e ISOs se guardan en directorios privados con permisos `700`.
- No se modifica NetworkManager, WWAN, Podman, GRUB, `fstab`, LUKS ni firmware.
- El acceso al grupo `kvm` permite usar `/dev/kvm`; por eso solo se añade al
  usuario explícitamente solicitado y no se conceden permisos adicionales.

`qemu:///session` es apropiado para virtualización de escritorio y elimina la
necesidad de administrar permisos del daemon del sistema, pero tiene menos
capacidades de red y autoinicio que `qemu:///system`. Consulta la
[documentación del driver QEMU de libvirt](https://libvirt.org/drvqemu) y la
[FAQ de libvirt sobre session/system](https://wiki.libvirt.org/FAQ.html).

## Fallos conocidos

### `/dev/kvm no existe`

**Causa:** VT-x/AMD-V está deshabilitado en firmware o el kernel no cargó el
módulo KVM.

**Solución:** habilita Intel Virtualization Technology o AMD-V en firmware,
reinicia y vuelve a ejecutar `just configure-kvm --check`. El script no cambia
la BIOS automáticamente.

### `rafex no pertenece al grupo kvm en esta sesión`

**Causa:** `usermod` actualiza la siguiente sesión, pero no los grupos del
proceso actual.

**Solución:** cierra y abre sesión, o ejecuta `newgrp kvm`. No ejecutes el
script como root para evitar este mensaje.

### `pool ... ya existe con otra ruta`

**Causa:** libvirt ya tiene una pool con el nombre reservado por el perfil.

**Solución:** el script no la sobrescribe. Revisa `virsh -c qemu:///session
pool-dumpxml <pool>` y decide manualmente si deseas conservarla o cambiarla.

### `failed to connect to qemu:///session`

**Causa:** falta libvirt, no existe una sesión de usuario con D-Bus o el
daemon de sesión no pudo iniciarse.

**Solución:** ejecuta `just configure-kvm --status`, verifica que `virsh` esté
instalado y prueba `virsh -c qemu:///session uri` desde la sesión gráfica.
No cambies a `qemu:///system` ni uses sudo como solución automática.

### virt-manager muestra otra conexión

**Causa:** virt-manager conserva una conexión previa, normalmente
`qemu:///system`.

**Solución:** agrega o selecciona explícitamente `QEMU/KVM user session` o
ejecuta `virt-manager --connect qemu:///session`.

## Changelog

### [Unreleased]

- **feat:** configurar QEMU/KVM y libvirt para la sesión privada del usuario.
- **docs:** documentar pools de imágenes, ISOs y red user-mode sin bridge.

### v1.0.0 — 2026-08-30

**feat:** primera versión del configurador KVM para la ThinkPad.
