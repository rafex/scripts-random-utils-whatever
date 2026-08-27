#!/usr/bin/env python3
"""Launch Ether-rules around compatibility issues in the v0.5.0 wheel.

The upstream wheel currently imports ``MCPServer`` although supported MCP SDK
releases expose ``FastMCP``.  This adapter keeps the wheel untouched, adds its
legacy ``lib`` import path, and provides the missing compatibility alias.
"""

from __future__ import annotations

import os
import site
import sys
from pathlib import Path


TOOL_DIR = Path.home() / ".local" / "share" / "uv" / "tools" / "ether-mcp-my-best-practices"
TOOL_PYTHON = TOOL_DIR / "bin" / "python"


def tool_site_packages() -> Path:
    candidates = sorted(TOOL_DIR.glob("lib/python*/site-packages"))
    if not candidates:
        raise SystemExit(f"No se encontró el entorno uv de Ether-rules en {TOOL_DIR}")
    return candidates[-1]


def reexec_with_tool_python() -> None:
    if not TOOL_PYTHON.is_file():
        raise SystemExit(f"No se encontró el intérprete de Ether-rules: {TOOL_PYTHON}")
    if Path(sys.executable).resolve() != TOOL_PYTHON.resolve():
        os.execve(str(TOOL_PYTHON), [str(TOOL_PYTHON), __file__, *sys.argv[1:]], os.environ)


def main() -> int:
    reexec_with_tool_python()
    packages = tool_site_packages()
    package_root = packages / "ether_mcp_my_best_practices"
    sys.path.insert(0, str(package_root))
    site.addsitedir(str(packages))

    data_root = package_root / "data"
    for env_name in ("RULES_DIR", "TEMPLATES_DIR", "HELPERS_DIR", "DOCS_DIR"):
        directory = data_root / env_name.removesuffix("_DIR").lower()
        if directory.is_dir():
            os.environ.setdefault(env_name, str(directory))

    import mcp.server
    from mcp.server.fastmcp import FastMCP

    if not hasattr(mcp.server, "MCPServer"):
        class MCPServer(FastMCP):
            def __init__(self, name: str, version: str | None = None, **kwargs: object) -> None:
                del version
                super().__init__(name=name, **kwargs)

        mcp.server.MCPServer = MCPServer

    # El wheel registra su auditoría en stdout; durante la importación se
    # redirige a stderr para no contaminar el canal JSON-RPC de MCP.
    protocol_stdout = sys.stdout
    sys.stdout = sys.stderr
    try:
        import ether_mcp_my_best_practices.config as config

        config.GITIGNORE_DIR = str(data_root / "templates" / "gitignore")
        config.REPO_STRUCTURE_DIR = str(data_root / "templates" / "repository-structure")

        from ether_mcp_my_best_practices.server import main as server_main
    finally:
        sys.stdout = protocol_stdout

    return int(server_main() or 0)


if __name__ == "__main__":
    raise SystemExit(main())
