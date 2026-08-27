---
title: install_wifi_polkit_linux.sh
description: Instalación de permisos polkit para NetworkManager
tags:
  - red
---

# install_wifi_polkit_linux.sh

Instala una regla PolicyKit limitada que permite a usuarios locales activos del
grupo `netdev` gestionar las operaciones habituales de NetworkManager sin
contraseña de sudo.

Debe ejecutarse con `sudo`.

- **Ruta:** `scripts/network/install_wifi_polkit_linux.sh`
- **SO requerido:** Linux (PolicyKit)
- **Dependencias:** `polkit`, `sudo`

______________________________________________________________________

## Uso

```sh
sudo ./scripts/network/install_wifi_polkit_linux.sh
```

______________________________________________________________________

## Qué hace

1. Crea `/etc/polkit-1/rules.d/10-nm-wifi.rules`
1. Crea el grupo `netdev` si no existe
1. Agrega al usuario actual al grupo `netdev`

Requiere cerrar sesión y volver a entrar para que el grupo tome efecto.

______________________________________________________________________

## Regla instalada

```js
polkit.addRule(function(action, subject) {
  var allowed = [
    "org.freedesktop.NetworkManager.settings.modify.system",
    "org.freedesktop.NetworkManager.settings.modify.own",
    "org.freedesktop.NetworkManager.network-control",
    "org.freedesktop.NetworkManager.enable-disable-wifi",
    "org.freedesktop.NetworkManager.enable-disable-network",
    "org.freedesktop.NetworkManager.wifi.scan"
  ];
  if (subject.local && subject.active && subject.isInGroup("netdev") &&
      allowed.indexOf(action.id) >= 0) {
    return polkit.Result.YES;
  }
});
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

### [Unreleased]

**fix:** limita las acciones a operaciones NetworkManager necesarias para una sesión local activa.

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/install-wifi-polkit.sh`.
