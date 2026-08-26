# install_wifi_polkit_linux.sh

Instala una regla PolicyKit limitada que permite a usuarios locales activos del
grupo `netdev` gestionar las operaciones habituales de NetworkManager sin
contraseña de sudo.

Debe ejecutarse con `sudo`.

- **Ruta:** `scripts/network/install_wifi_polkit_linux.sh`
- **SO requerido:** Linux (PolicyKit)
- **Dependencias:** `polkit`, `sudo`

---

## Uso

```sh
sudo ./scripts/network/install_wifi_polkit_linux.sh
```

---

## Qué hace

1. Crea `/etc/polkit-1/rules.d/10-nm-wifi.rules`
2. Crea el grupo `netdev` si no existe
3. Agrega al usuario actual al grupo `netdev`

Requiere cerrar sesión y volver a entrar para que el grupo tome efecto.

---

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

---

## Changelog

### [Unreleased]

**fix:** limita las acciones a operaciones NetworkManager necesarias para una sesión local activa.

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/install-wifi-polkit.sh`.
