#!/usr/bin/env python3
"""Validate script coverage and MkDocs document conventions."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs"
SCRIPTS = ROOT / "scripts"
MKDOCS = ROOT / ".config" / "mkdocs" / "mkdocs.yml"
CATALOG = DOCS / "catalogo-scripts.md"
REQUIRED_SECTIONS = (
    "## Índice",
    "## Requisitos",
    "## Uso",
    "## Opciones",
    "## Variables de entorno",
    "## Ejemplos",
    "## Fallos conocidos",
    "## Changelog",
)
SCRIPT_EXTENSIONS = {".sh", ".py"}


def error(message: str) -> None:
    print(f"ERROR: {message}")


def warning(message: str) -> None:
    print(f"WARN: {message}")


def expected_doc(script: Path) -> Path:
    return DOCS / script.relative_to(SCRIPTS).with_suffix(".md")


def validate_frontmatter(path: Path, text: str) -> list[str]:
    problems: list[str] = []
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return [f"{path.relative_to(ROOT)}: falta frontmatter YAML"]
    try:
        end = lines.index("---", 1)
    except ValueError:
        return [f"{path.relative_to(ROOT)}: frontmatter sin cierre ---"]
    frontmatter = "\n".join(lines[1:end])
    for key in ("title:", "description:", "tags:"):
        if not re.search(rf"^{re.escape(key)}\s*.+$", frontmatter, re.MULTILINE):
            problems.append(f"{path.relative_to(ROOT)}: falta {key} en frontmatter")
    if not re.search(r"^\s+-\s+\S+", frontmatter, re.MULTILINE):
        problems.append(f"{path.relative_to(ROOT)}: tags debe contener al menos un valor")
    return problems


def validate_local_links(path: Path, text: str) -> list[str]:
    problems: list[str] = []
    for raw_target in re.findall(r"\]\(([^)]+)\)", text):
        target = raw_target.strip().split()[0].strip("<>")
        if not target or target.startswith(("#", "/", "http://", "https://", "mailto:")):
            continue
        target_path = unquote(target.split("#", 1)[0])
        if not target_path:
            continue
        candidate = (path.parent / target_path).resolve()
        try:
            candidate.relative_to(ROOT)
        except ValueError:
            problems.append(f"{path.relative_to(ROOT)}: enlace fuera del repositorio: {target}")
            continue
        if not candidate.exists():
            problems.append(f"{path.relative_to(ROOT)}: enlace roto: {target}")
    return problems


def nav_targets() -> list[str]:
    if not MKDOCS.exists():
        return []
    return re.findall(r"(?:^|:\s+)([A-Za-z0-9_./-]+\.md)\s*$", MKDOCS.read_text())


def main() -> int:
    problems: list[str] = []
    warnings: list[str] = []
    if not MKDOCS.exists():
        problems.append("mkdocs.yml no existe")
    if not CATALOG.exists():
        problems.append("docs/catalogo-scripts.md no existe")

    scripts = sorted(
        path for path in SCRIPTS.rglob("*") if path.is_file() and path.suffix in SCRIPT_EXTENSIONS
    )
    catalog = CATALOG.read_text(encoding="utf-8") if CATALOG.exists() else ""
    just_text = "\n".join(path.read_text(encoding="utf-8", errors="replace") for path in (ROOT / "just").glob("*.just"))
    for script in scripts:
        relative_script = script.relative_to(ROOT).as_posix()
        document = expected_doc(script)
        if not document.exists():
            problems.append(f"{relative_script}: falta {document.relative_to(ROOT)}")
            continue
        text = document.read_text(encoding="utf-8")
        problems.extend(validate_frontmatter(document, text))
        for section in REQUIRED_SECTIONS:
            if section not in text:
                problems.append(f"{document.relative_to(ROOT)}: falta sección {section}")
        script_text = script.read_text(encoding="utf-8", errors="replace")
        uses_env = script.name != "validate_script_docs.py" and (
            "ENV_FILE" in script_text
            or re.search(r"(?<![A-Za-z])\.env(?:$|[\s/'\"])", script_text)
        )
        if uses_env and "## Archivo .env" not in text:
            problems.append(f"{document.relative_to(ROOT)}: el script usa .env y falta ## Archivo .env")
        route = f"- **Ruta:** `{relative_script}`"
        if route not in text:
            problems.append(f"{document.relative_to(ROOT)}: ruta documentada incorrecta o ausente")
        if f"`{relative_script}`" not in catalog:
            problems.append(f"{relative_script}: falta en docs/catalogo-scripts.md")
        if script.name not in just_text and script.name not in {"commons_deploy_verify_unix.sh", "validate_script_docs.py"}:
            warnings.append(f"{relative_script}: no se encontró referencia a una tarea Just")

    for document in sorted(DOCS.rglob("*.md")):
        text = document.read_text(encoding="utf-8")
        problems.extend(validate_frontmatter(document, text))
        problems.extend(validate_local_links(document, text))

    for target in nav_targets():
        if not (DOCS / target).exists():
            problems.append(f"mkdocs.yml: destino de navegación inexistente: {target}")

    for message in warnings:
        warning(message)
    for message in problems:
        error(message)
    if problems:
        print(f"Documentación inválida: {len(problems)} error(es), {len(warnings)} advertencia(s).")
        return 1
    print(f"Documentación válida: {len(scripts)} script(s), {len(list(DOCS.rglob('*.md')))} documento(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
