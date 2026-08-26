# wifi_polkit_rules — Permisos sin sudo para NetworkManager

Regla PolicyKit que permite a usuarios del grupo `netdev` gestionar WiFi sin contraseña de sudo: conectar, escanear, modificar conexiones, activar/desactivar interfaces.

- **Ruta del archivo de reglas:** `scripts/network/50-wifi-user.rules`
- **Ubicación en el sistema:** `/etc/polkit-1/rules.d/50-wifi-user.rules`
- **SO requerido:** Linux con PolicyKit (pkaction >= 106)

---

## Instalación

```sh
sudo cp scripts/network/50-wifi-user.rules /etc/polkit-1/rules.d/50-wifi-user.rules
sudo chmod 644 /etc/polkit-1/rules.d/50-wifi-user.rules
```

No requiere reinicio — PolicyKit recarga las reglas automáticamente.

---

## Verificar que el usuario está en el grupo `netdev`

```sh
groups | grep netdev
```

Si no aparece, agregarlo:

```sh
sudo usermod -aG netdev $USER
```

Cerrar sesión y volver a entrar para que el grupo tome efecto.

---

## Acciones autorizadas

La regla cubre únicamente las acciones habituales de NetworkManager para una
sesión local activa:

| Acción | Descripción |
|---|---|
| `wifi.scan` | Escanear redes WiFi |
| `settings.modify.system` | Crear/editar/eliminar conexiones del sistema |
| `settings.modify.own` | Gestionar conexiones propias |
| `network-control` | Control general de red |
| `enable-disable-wifi` | Activar/desactivar WiFi |
| `enable-disable-network` | Activar/desactivar red |

---

## Contenido de la regla

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

## Troubleshooting

### Los scripts piden contraseña después de instalar la regla

Verificar que:

1. El usuario está en el grupo `netdev` (puede requerir re-login)
2. La regla tiene permisos 644
3. PolicyKit está corriendo: `systemctl status polkit`

### `pkaction: command not found`

Instalar:

```sh
sudo apt install polkitd
```

---

## Changelog

### [Unreleased]

**fix:** limita las acciones a operaciones necesarias y sesiones locales activas.

### v1.0.0 — 2026-07-22

**feat:** versión inicial. Permite a usuarios del grupo `netdev` todas las acciones de NetworkManager sin autenticación.
