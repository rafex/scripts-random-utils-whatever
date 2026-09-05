#!/usr/bin/env bash
# shellcheck shell=bash
# Imprime las ventanas normales del workspace actual para el módulo de Polybar.
set -Eeuo pipefail
umask 077

die() {
  printf 'i3-window-tasks: %s\n' "$*" >&2
  exit 1
}

[[ "$(uname -s)" == Linux ]] || die 'este helper requiere Linux'
(( $# == 0 )) || die 'no acepta argumentos'
[[ -n "${DISPLAY:-}" ]] || die 'DISPLAY no está disponible'
command -v i3-msg >/dev/null 2>&1 || die 'falta i3-msg'
command -v python3 >/dev/null 2>&1 || die 'falta python3'

tree_json="$(i3-msg -t get_tree)" || die 'no se pudo consultar el árbol IPC de i3'

python3 -c '
import json
import re
import sys


GLYPH_GENERIC = ""
CLASS_GLYPHS = {
    "firefox": "",
    "chromium": "",
    "chromium-browser": "",
    "google-chrome": "",
    "brave-browser": "",
    "alacritty": "",
    "urxvt": "",
    "kitty": "",
    "gnome-terminal": "",
    "xterm": "",
    "code": "",
    "codium": "",
    "vscodium": "",
    "nvim": "",
    "emacs": "",
    "thunar": "",
    "nautilus": "",
    "pcmanfm": "",
    "dolphin": "",
}
EDITOR_CLASSES = ("code-", "jetbrains-", "sublime_text")
TERMINAL_CLASSES = ("terminator", "konsole", "xfce4-terminal")
FILE_MANAGER_CLASSES = ("caja", "nemo", "ranger")


def descendants(node):
    yield node
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        yield from descendants(child)


def workspace_contains_focus(workspace):
    return any(bool(node.get("focused")) for node in descendants(workspace))


def focused_workspace(root):
    for node in descendants(root):
        if node.get("type") == "workspace" and workspace_contains_focus(node):
            return node
    return None


def is_window(node):
    return (
        node.get("type") == "con"
        and isinstance(node.get("id"), int)
        and node.get("window") is not None
        and not node.get("scratchpad_state")
    )


def window_nodes(workspace):
    for node in descendants(workspace):
        if is_window(node):
            yield node


def semantic_glyph(node):
    props = node.get("window_properties") or {}
    values = (props.get("class"), props.get("instance"))
    for value in values:
        normalized = str(value or "").casefold()
        if normalized in CLASS_GLYPHS:
            return CLASS_GLYPHS[normalized]
        if normalized.startswith(EDITOR_CLASSES):
            return ""
        if normalized.startswith(TERMINAL_CLASSES):
            return ""
        if normalized.startswith(FILE_MANAGER_CLASSES):
            return ""
    return GLYPH_GENERIC


def safe_text(value):
    text = str(value or "Sin título")
    text = re.sub(r"[\x00-\x1f\x7f]", " ", text)
    text = re.sub(r"\s+", " ", text).strip() or "Sin título"
    text = text.replace("%", "%%").replace("{", "(").replace("}", ")")
    if len(text) > 24:
        text = text[:23] + "…"
    return text


try:
    tree = json.load(sys.stdin)
except (json.JSONDecodeError, TypeError) as error:
    raise SystemExit(f"árbol i3 inválido: {error}")

workspace = focused_workspace(tree)
if workspace is None or str(workspace.get("name", "")).startswith("__i3_scratch"):
    print(f"{GLYPH_GENERIC} Escritorio")
    raise SystemExit(0)

tasks = []
for node in window_nodes(workspace):
    con_id = node["id"]
    title = safe_text(node.get("name"))
    glyph = semantic_glyph(node)
    tasks.append(f"%{{A1:i3-msg \"[con_id={con_id}] focus\":}}{glyph} {title}%{{A}}")

print("  ".join(tasks) if tasks else f"{GLYPH_GENERIC} Escritorio")
' <<<"$tree_json"
