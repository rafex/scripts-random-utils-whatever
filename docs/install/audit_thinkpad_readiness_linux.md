---
title: audit_thinkpad_readiness_linux.sh
description: Audita si una ThinkPad Debian está lista para desarrollo, cursos y laboratorios móviles
tags:
  - instalación
  - seguridad
  - thinkpad
---

# audit_thinkpad_readiness_linux.sh

Revisa los controles de seguridad, red, runtimes, virtualización, energía,
sesión gráfica y respaldo de la ThinkPad sin modificar el sistema.

- **Ruta:** `scripts/install/audit_thinkpad_readiness_linux.sh`
- **SO requerido:** Linux (Debian)
- **Dependencias:** bash, systemctl y dpkg-query; sudo solo se usa sin interacción si ya existe una autorización válida

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

- Debian con systemd.
- Ejecutar como rafex o el usuario propietario de la sesión; no se debe
  ejecutar como root.
- Para verificar UFW, Fail2ban, AppArmor, auditd, USBGuard, Polkit, TLP y
  sshd -T, ejecutar antes sudo -v en la consola local. El auditor nunca
  solicita la contraseña.

## Uso

```bash
just audit-thinkpad --check
just audit-thinkpad --status
```

La salida separa bloqueos confirmados de asuntos pendientes. Un proyector no
conectado, un respaldo desmontado o una comprobación privilegiada no disponible
no se presentan como fallos del hardware.

También informa, sin convertir en bloqueos, la disponibilidad opcional de GIMP,
Krita, LibreOffice, FFmpeg, mpv, VLC, ClamAV y Noto CJK. Para instalar estas
capas usa los instaladores separados `install-graphics`, `install-office`,
`install-multimedia`, `install-antivirus` e `install-fonts`; la instalación
ligera del perfil no las activa automáticamente.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| --check | — | Ejecuta la auditoría de solo lectura. |
| --status | — | Alias de --check, útil para scripts de estado. |
| --help | -h | Muestra la ayuda. |

## Variables de entorno

El script no utiliza variables de entorno de configuración. Detecta el usuario
actual, la raíz del repositorio y la sesión gráfica disponible.

## Ejemplos

### Auditoría normal

```bash
just audit-thinkpad --check
```

### Verificación privilegiada completa

En la consola local, para que el auditor pueda leer los controles protegidos:

```bash
sudo -v
just audit-thinkpad --status
```

### Proyector y respaldo

Conecta físicamente el proyector y monta manualmente el SSD etiquetado
ssd_rafex_1; después ejecuta de nuevo el auditor. La prueba específica de
salidas sigue siendo:

```bash
just screen-projector --check
```

## Protecciones de seguridad

- No ejecuta apt, systemctl start/restart, escaneos, capturas ni comandos
  de laboratorio.
- Nunca imprime contraseñas, PIN, IMEI, IMSI, claves o secretos Wi-Fi.
- Usa sudo -n únicamente para consultar el estado y nunca abre un prompt.
- Marca como bloqueo la caída de USBGuard, perfiles GSM OXXO Cel duplicados,
  dumpcap con SUID/capacidades persistentes o políticas de hardening
  incorrectas cuando pudo verificarlas.
- La ausencia de sudo autorizado se informa como pendiente, no se soluciona
  ampliando permisos.
- No certifica la proyección física: esa parte requiere conectar y probar el
  adaptador o proyector real.

## Fallos conocidos

### Verificación privilegiada pendiente

**Causa:** la auditoría se ejecutó por SSH o en una shell sin una autorización
sudo vigente.
**Solución:** en la consola local ejecuta sudo -v y repite
just audit-thinkpad --status.

### USBGuard no está activo

**Causa:** usbguard.service o usbguard-dbus.service está detenido o falló.
**Solución:** revisa el journal con sudo y aplica
just harden-thinkpad --apply --stage local.

### Existen perfiles GSM OXXO Cel

**Causa:** una ejecución anterior creó más de un perfil con el mismo nombre.
**Solución:** ejecuta just configure-wwan-oxxocel --apply; reutiliza el perfil
activo y elimina solo los duplicados inactivos del mismo tipo.

### dumpcap conserva privilegios persistentes

**Causa:** una instalación anterior otorgó SUID o capacidades a dumpcap.
**Solución:** ejecuta just install-security-lab --apply --stage base; el
instalador instala libcap2-bin, elimina esos privilegios y conserva la captura
explícita con sudo dumpcap.

## Changelog

### [Unreleased]

- **feat:** añadir auditoría integral de preparación de la ThinkPad.
- **docs:** distinguir bloqueos confirmados de verificaciones pendientes sin
  solicitar credenciales.

### v1.0.0 — 2026-08-30

**feat:** primera versión del auditor de preparación.
