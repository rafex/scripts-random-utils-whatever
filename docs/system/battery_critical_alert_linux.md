# battery_critical_alert_linux.sh

Muestra una franja de i3 y una notificación crítica si la batería está
descargándose y tiene 10 % o menos. El perfil de Polybar del ThinkPad muestra
«BATERÍA BAJA» desde el 15 %.

- **Ruta:** `scripts/system/battery_critical_alert_linux.sh`
- **SO requerido:** Linux
- **Dependencias:** Bash, `notify-send`, Dunst u otro servidor de notificaciones, `i3-nagbar` y systemd de usuario.

---

## Índice

- [Requisitos](#requisitos)
- [Uso](#uso)
- [Opciones](#opciones)
- [Variables de entorno](#variables-de-entorno)
- [Ejemplos](#ejemplos)
- [Fallos conocidos](#fallos-conocidos)
- [Changelog](#changelog)

## Requisitos

La batería debe aparecer bajo `/sys/class/power_supply/BAT*`. La sesión
gráfica debe tener un servidor de notificaciones en el bus de usuario.

## Uso

El temporizador comprueba la batería cada minuto. Al llegar al 10 % muestra
una franja superior de i3. Cuando conectas el cargador, la franja desaparece
en la siguiente revisión. En Dunst, el aviso crítico
queda visible hasta descartarlo y los avisos sucesivos se agrupan. Mientras
la batería se descargue al 10 % o menos, el aviso volverá a aparecer si se
descarta. Al conectar el cargador cesan los avisos nuevos.

## Opciones

| Opción | Alias | Descripción |
|---|---|---|
| — | — | El script no define opciones. |

## Variables de entorno

| Variable | Descripción |
|---|---|
| `DBUS_SESSION_BUS_ADDRESS` | Dirección del bus de usuario, si la sesión la define. |
| `PATH` | Ruta para localizar `notify-send`. |

## Ejemplos

Desde la raíz del repositorio:

```bash
mkdir -p ~/.local/bin ~/.config/systemd/user
install -m 755 scripts/system/battery_critical_alert_linux.sh ~/.local/bin/battery-critical-alert
units=dotfiles/profiles/thinkpad-x1-yoga-1st/config/systemd/user
install -m 644 "$units"/rafex-battery-alert.{service,timer} "$units"/rafex-battery-nagbar.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now rafex-battery-alert.timer
```

Para una comprobación manual desde la sesión gráfica:

```bash
PATH="/usr/bin:/bin:$PATH" bash scripts/system/battery_critical_alert_linux.sh
```

## Fallos conocidos

### La batería está baja y el aviso no aparece

**Causa:** la batería puede estar cargando, Dunst puede estar pausado o el
temporizador puede estar desactivado.

**Solución:** comprueba el estado de la batería, de Dunst y del temporizador
con `systemctl --user status rafex-battery-alert.timer`.

## Changelog

### [Unreleased]

- **feat:** añade una franja de i3 al 10 % y un aviso en Polybar al 15 %.

### v1.0.0 — 2026-11-18

**feat:** muestra una notificación crítica desde el 10 % de batería.
