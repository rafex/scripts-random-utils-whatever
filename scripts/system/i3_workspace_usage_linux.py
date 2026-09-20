#!/usr/bin/env python3
# Managed by rafex install_i3_workspace_usage_linux.sh
"""Registra uso agregado de ventanas i3 para proponer workspaces ThinkPad."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


DEFAULT_LABELS = {
    1: "term", 2: "code", 3: "web", 4: "docs", 5: "misc",
    6: "media", 7: "comms", 8: "ops", 9: "monitor", 10: "scratch",
}
CATEGORY_CLASSES = {
    "term": {"alacritty", "kitty", "xterm", "urxvt", "rxvt-unicode", "gnome-terminal", "konsole", "terminator", "xfce4-terminal"},
    "code": {"code", "codium", "vscodium", "eclipse", "emacs", "sublime_text", "jetbrains-idea", "jetbrains-pycharm"},
    "web": {"firefox", "chromium", "chromium-browser", "google-chrome", "brave-browser"},
    "docs": {"zathura", "evince", "libreoffice", "xournalpp", "okular"},
    "files": {"thunar", "nautilus", "nemo", "dolphin", "pcmanfm", "caja"},
    "media": {"obs", "guvcview", "krita", "mpv", "vlc", "spotify"},
    "comms": {"discord", "slack", "telegramdesktop", "signal", "zoitechat", "hexchat"},
    "ops": {"virt-manager", "virtualbox", "gnome-boxes", "remmina"},
    "monitor": {"htop", "btop", "conky"},
    "misc": {"pavucontrol", "nm-connection-editor", "blueman-manager", "arandr"},
}
CLASS_CATEGORY = {name: category for category, names in CATEGORY_CLASSES.items() for name in names}


def state_path() -> Path:
    root = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    return root / "rafex" / "i3-workspace-usage.json"


def load_state(path: Path) -> dict:
    if not path.exists():
        return {"version": 1, "entries": []}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"estado inválido: {error}") from error
    if value.get("version") != 1 or not isinstance(value.get("entries"), list):
        raise RuntimeError("estado con versión o estructura no compatible")
    return value


def save_state(path: Path, state: dict) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    fd, temporary = tempfile.mkstemp(prefix=".i3-workspace-usage.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(state, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def normalized(value: object) -> str:
    return str(value or "").strip().casefold()


def workspace_number(value: object):
    name = str(value or "")
    prefix = name.split(":", 1)[0]
    try:
        number = int(prefix)
    except ValueError:
        return None
    return number if 1 <= number <= 10 else None


def descendants(node: dict):
    yield node
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        yield from descendants(child)


def focused_sample(tree: dict):
    workspace = None
    focused = None
    for node in descendants(tree):
        if node.get("type") == "workspace" and node.get("focused"):
            workspace = workspace_number(node.get("name"))
        if node.get("focused") and node.get("window") is not None:
            focused = node
    if workspace is None or focused is None or focused.get("scratchpad_state") not in (None, "", "none"):
        return None
    properties = focused.get("window_properties") or {}
    window_class = normalized(properties.get("class"))
    instance = normalized(properties.get("instance"))
    if not window_class and not instance:
        return None
    return workspace, window_class, instance


def entry_for(state: dict, sample: tuple):
    workspace, window_class, instance = sample
    for entry in state["entries"]:
        if (entry["workspace"], entry["class"], entry["instance"]) == sample:
            return entry
    entry = {"workspace": workspace, "class": window_class, "instance": instance,
             "focus_seconds": 0.0, "focus_events": 0, "last_seen": 0}
    state["entries"].append(entry)
    return entry


def commit(state: dict, sample, elapsed: float, activated: bool) -> None:
    if sample is None:
        return
    entry = entry_for(state, sample)
    entry["focus_seconds"] += max(0.0, elapsed)
    entry["focus_events"] += int(activated)
    entry["last_seen"] = int(time.time())


def i3_tree() -> dict:
    result = subprocess.run(["i3-msg", "-t", "get_tree"], check=True,
                            capture_output=True, text=True)
    return json.loads(result.stdout)


def daemon() -> int:
    if os.uname().sysname != "Linux":
        raise RuntimeError("este registrador requiere Linux")
    if not os.environ.get("DISPLAY"):
        raise RuntimeError("DISPLAY no está disponible")
    path = state_path()
    state = load_state(path)
    active = None
    started = time.monotonic()
    while True:
        try:
            current = focused_sample(i3_tree())
            commit(state, active, time.monotonic() - started, False)
            changed = current != active
            active = current
            started = time.monotonic()
            commit(state, active, 0.0, changed and active is not None)
            save_state(path, state)
            process = subprocess.Popen(
                ["i3-msg", "-t", "subscribe", "-m", '["window", "workspace"]'],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
            )
            assert process.stdout is not None
            for line in process.stdout:
                try:
                    json.loads(line)
                    current = focused_sample(i3_tree())
                except (json.JSONDecodeError, subprocess.CalledProcessError, RuntimeError):
                    continue
                now = time.monotonic()
                changed = current != active
                commit(state, active, now - started, False)
                active = current
                started = now
                commit(state, active, 0.0, changed and active is not None)
                save_state(path, state)
            process.wait()
        except (OSError, subprocess.CalledProcessError, json.JSONDecodeError):
            pass
        commit(state, active, time.monotonic() - started, False)
        save_state(path, state)
        started = time.monotonic()
        time.sleep(2)


def category(entry: dict):
    return CLASS_CATEGORY.get(entry["class"]) or CLASS_CATEGORY.get(entry["instance"])


def score(entry: dict):
    return (float(entry.get("focus_seconds", 0)), int(entry.get("focus_events", 0)))


def report(state: dict) -> str:
    entries = state["entries"]
    category_scores = {}
    for entry in entries:
        kind = category(entry)
        if kind:
            key = (entry["workspace"], kind)
            seconds, events = category_scores.get(key, (0.0, 0))
            category_scores[key] = (seconds + score(entry)[0], events + score(entry)[1])
    labels = dict(DEFAULT_LABELS)
    for workspace in range(1, 11):
        candidates = [(value, kind) for (number, kind), value in category_scores.items() if number == workspace]
        if candidates:
            labels[workspace] = max(candidates, key=lambda item: (item[0][0], item[0][1], item[1]))[1]

    lines = ["# Borrador de workspaces i3 (generado; revisar antes de aplicar)", "",
             "# Estado agregado: clase/instancia, tiempo en foco y activaciones. No contiene títulos.",
             "# Nombres propuestos"]
    lines += [f'set $ws{number} "{number}:{labels[number]}"' for number in range(1, 11)]
    lines += ["", "# Reglas assign propuestas para clases conocidas con evidencia suficiente"]
    by_class = {}
    for entry in entries:
        if not category(entry):
            continue
        key = entry["class"] or entry["instance"]
        if key:
            by_class.setdefault(key, []).append(entry)
    for name in sorted(by_class):
        best = max(by_class[name], key=score)
        seconds, events = score(best)
        if seconds >= 300 or events >= 3:
            lines.append(f'assign [class="(?i)^{name}$"] $ws{best["workspace"]}  # {seconds:.0f}s, {events} activaciones')

    unknown = [entry for entry in entries if not category(entry)]
    if unknown:
        lines += ["", "# Clases desconocidas: revisar; se dejan inactivas por seguridad"]
        for entry in sorted(unknown, key=lambda item: (item["workspace"], item["class"], item["instance"])):
            seconds, events = score(entry)
            name = entry["class"] or entry["instance"]
            lines.append(f'# assign [class="(?i)^{name}$"] $ws{entry["workspace"]}  # {seconds:.0f}s, {events} activaciones')
    return "\n".join(lines) + "\n"


def status(path: Path, state: dict) -> str:
    total = sum(float(entry.get("focus_seconds", 0)) for entry in state["entries"])
    return f"estado={path}\nentradas={len(state['entries'])}\ntiempo_foco_segundos={total:.0f}\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument("--daemon", action="store_true")
    actions.add_argument("--status", action="store_true")
    actions.add_argument("--report", action="store_true")
    actions.add_argument("--reset", action="store_true")
    parser.add_argument("--yes", action="store_true", help="confirma --reset")
    parser.add_argument("--output", type=Path, help="guarda el informe con permisos 0600")
    args = parser.parse_args()
    if args.output and not args.report:
        parser.error("--output requiere --report")
    if args.yes and not args.reset:
        parser.error("--yes requiere --reset")
    path = state_path()
    if args.daemon:
        return daemon()
    if args.reset:
        if not args.yes:
            parser.error("--reset requiere --yes")
        if path.exists():
            path.unlink()
        print(f"estado eliminado: {path}")
        return 0
    state = load_state(path)
    if args.status:
        sys.stdout.write(status(path, state))
        return 0
    content = report(state)
    if args.output:
        args.output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        args.output.write_text(content, encoding="utf-8")
        os.chmod(args.output, 0o600)
    else:
        sys.stdout.write(content)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(f"i3-workspace-usage: {error}", file=sys.stderr)
        raise SystemExit(1)
