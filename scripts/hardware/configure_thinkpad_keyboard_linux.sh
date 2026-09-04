#!/usr/bin/env bash
# v1.0.0 — Teclado latinoamericano persistente para Debian, i3 y Openbox.
set -euo pipefail
umask 077
ACTION=check
seen=0
for arg in "$@"; do
    case "$arg" in
        --check|--plan|--status|--apply)
            [[ $seen == 0 ]] || { echo 'Selecciona una sola acción' >&2; exit 2; }
            ACTION=${arg#--}; seen=1 ;;
        --help|-h)
            echo 'Uso: configure_thinkpad_keyboard_linux.sh --check|--plan|--status|--apply'
            echo 'Configura pc105/latam sin variante ni opciones XKB. Ejecutar como usuario normal.'
            exit 0 ;;
        *) echo "Opción desconocida: $arg" >&2; exit 2 ;;
    esac
done
[[ $(uname -s) == Linux && -f /etc/debian_version ]] || { echo 'Requiere Debian y X11' >&2; exit 1; }
[[ $EUID != 0 ]] || { echo 'Ejecuta como usuario normal; sudo se solicita solo para /etc/default/keyboard' >&2; exit 1; }
command -v python3 >/dev/null
if [[ $ACTION == apply && -n ${DISPLAY:-} ]]; then
    command -v setxkbmap >/dev/null || { echo 'Falta setxkbmap (paquete x11-xkb-utils)' >&2; exit 1; }
    setxkbmap -query >/dev/null
fi

python3 - "$ACTION" <<'PY'
import datetime
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

action = sys.argv[1]
home = Path.home()
config = Path(os.environ.get('XDG_CONFIG_HOME', str(home / '.config')))
targets = [(Path('/etc/default/keyboard'), 'system'),
           (config / 'i3/config', 'i3'),
           (config / 'openbox/autostart', 'openbox')]
changes = []
stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')

def render(path, kind, old):
    if kind == 'system':
        values = {'XKBMODEL': 'pc105', 'XKBLAYOUT': 'latam',
                  'XKBVARIANT': '', 'XKBOPTIONS': ''}
        lines = old.splitlines()
        for key, value in values.items():
            pattern = re.compile(r'^\s*' + key + r'\s*=')
            lines = [line for line in lines if not pattern.match(line)]
        return '\n'.join(lines + [f'{key}="{value}"' for key, value in values.items()]) + '\n'
    desired = 'setxkbmap -model pc105 -layout latam -variant "" -option ""'
    found = False
    lines = []
    for line in old.splitlines():
        if line.lstrip().startswith('#') or 'setxkbmap' not in line:
            lines.append(line)
            continue
        if re.fullmatch(r'\s*if command -v setxkbmap >/dev/null 2>&1; then\s*', line):
            lines.append(line)
            continue
        prefix = r'(\s*exec(?:_always)?\s+--no-startup-id\s+)' if kind == 'i3' else r'(\s*)'
        match = re.fullmatch(prefix + r'setxkbmap\s+(?:es|latam|-layout\s+(?:es|latam))\s*', line)
        if match:
            lines.append(match[1] + desired)
            found = True
        elif line.strip() == desired or (kind == 'i3' and line.strip() == 'exec_always --no-startup-id ' + desired):
            lines.append(line)
            found = True
        else:
            raise RuntimeError(f'{path}: comando setxkbmap personalizado; revisarlo manualmente')
    if not found:
        lines += ['', '# Teclado administrado por configure-thinkpad-keyboard',
                  ('exec_always --no-startup-id ' if kind == 'i3' else '') + desired]
    return '\n'.join(lines) + '\n'

try:
    for path, kind in targets:
        if path.is_symlink():
            raise RuntimeError(f'{path}: enlace simbólico; no se reemplazará')
        if not path.exists() and kind != 'system':
            print(f'{kind}: configuración ausente; omitida')
            continue
        old = path.read_text() if path.exists() else ''
        new = render(path, kind, old)
        print(f'{kind}: ' + ('correcto (pc105/latam)' if old == new else 'requiere ajuste a pc105/latam'))
        if old != new:
            changes.append((path, kind, old, new))
    if action == 'check' and changes:
        sys.exit(1)
    if action != 'apply':
        if action == 'plan':
            print('Aplicación: respaldos fechados, configuración persistente y sesión X11 si DISPLAY está disponible.')
        sys.exit(0)

    # Preparar y validar todos los archivos antes de cambiar los destinos.
    with tempfile.TemporaryDirectory(prefix='rafex-keyboard-') as tmp:
        staged = []
        for index, (path, kind, old, new) in enumerate(changes):
            candidate = Path(tmp) / str(index)
            candidate.write_text(new)
            if kind == 'i3':
                subprocess.run(['i3', '-C', '-c', str(candidate)], check=True)
            elif kind == 'openbox':
                subprocess.run(['sh', '-n', str(candidate)], check=True)
            staged.append((path, kind, candidate))
        for path, kind, candidate in staged:
            # Detectar cambios concurrentes antes de sobrescribir.
            original = next(old for p, _, old, _ in changes if p == path)
            if path.is_symlink() or (path.read_text() if path.exists() else '') != original:
                raise RuntimeError(f'{path}: cambió durante la preparación')
            backup = str(path) + '.bak-latam-' + stamp
            if kind == 'system':
                if path.exists():
                    subprocess.run(['sudo', 'cp', '-p', '--', str(path), backup], check=True)
                subprocess.run(['sudo', 'install', '-o', 'root', '-g', 'root', '-m', '0644', str(candidate), str(path)], check=True)
            else:
                shutil.copy2(path, backup)
                fd, temporary = tempfile.mkstemp(prefix='.keyboard-', dir=path.parent)
                try:
                    os.close(fd)
                    shutil.copyfile(candidate, temporary)
                    os.chmod(temporary, path.stat().st_mode & 0o777)
                    os.replace(temporary, path)
                finally:
                    if os.path.exists(temporary):
                        os.unlink(temporary)
            print(f'Configurado: {path}; respaldo: {backup}')
except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
    print(f'ERROR: {exc}. Revisa los respaldos indicados si hubo cambios parciales.', file=sys.stderr)
    sys.exit(1)
PY

if [[ $ACTION == apply ]]; then
    if [[ -n ${DISPLAY:-} ]]; then
        setxkbmap -model pc105 -layout latam -variant '' -option ''
        setxkbmap -query
    else
        echo 'Configuración persistente lista; se activará al iniciar la sesión X11.'
    fi
    echo 'La consola de texto tomará la configuración en el próximo arranque; no se reinicia automáticamente.'
elif [[ -n ${DISPLAY:-} ]] && command -v setxkbmap >/dev/null; then
    setxkbmap -query
fi
