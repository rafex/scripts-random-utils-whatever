# install_wifi_polkit_linux.sh

Instala la regla PolicyKit que permite a usuarios del grupo `netdev` gestionar NetworkManager (escanear, conectar, modificar conexiones) sin contraseña de sudo.

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
  if (action.id.indexOf("org.freedesktop.NetworkManager.") == 0 &&
      subject.isInGroup("netdev")) {
    return polkit.Result.YES;
  }
});
```

---

## Changelog

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Migrado desde `laptop:~/.local/bin/install-wifi-polkit.sh`.
