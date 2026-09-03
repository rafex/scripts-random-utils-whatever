#!/usr/bin/env python3
"""Small, read-only HTTP publisher for the Firefox OS Hello World app."""

from __future__ import annotations

import argparse
import json
import os
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


APP_FILES = {
    "/index.html": ("index.html", "text/html; charset=utf-8"),
    "/style.css": ("style.css", "text/css; charset=utf-8"),
    "/app.js": ("app.js", "application/javascript; charset=utf-8"),
}


def installation_page(origin: str) -> bytes:
    return f"""<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Instalar Rafex Hola Mundo</title>
  <style>
    body {{ background: #18202b; color: #f5f7fa; font: 18px sans-serif; margin: 0; padding: 2rem; }}
    main {{ margin: auto; max-width: 28rem; }}
    button {{ background: #ff7043; border: 0; border-radius: .5rem; color: #171d26; font: inherit; font-weight: 700; padding: .8rem 1rem; width: 100%; }}
    #status {{ color: #9fe3b1; min-height: 1.5rem; }}
  </style>
</head>
<body>
  <main>
    <p>RAFEX · FIREFOX OS</p>
    <h1>Instalar Hola Mundo</h1>
    <p>Esta instalación usa el servidor local de la ThinkPad y no requiere WebIDE.</p>
    <button id="install" type="button">Instalar en este Flame</button>
    <p id="status" role="status" aria-live="polite"></p>
    <p><a href="/index.html">Probar la aplicación en el navegador</a></p>
  </main>
  <script>
    (function () {{
      "use strict";
      var button = document.getElementById("install");
      var status = document.getElementById("status");
      var manifestUrl = {json.dumps(origin + "/manifest.webapp")};

      button.addEventListener("click", function () {{
        var request;
        if (!navigator.mozApps || !navigator.mozApps.install) {{
          status.textContent = "Este navegador no ofrece instalación de aplicaciones Firefox OS.";
          return;
        }}
        button.disabled = true;
        status.textContent = "Solicitando confirmación en el teléfono…";
        request = navigator.mozApps.install(manifestUrl);
        request.onsuccess = function () {{
          status.textContent = "Aplicación instalada correctamente.";
        }};
        request.onerror = function () {{
          button.disabled = false;
          status.textContent = "No se instaló: " + (request.error || "cancelado");
        }};
      }});
    }}());
  </script>
</body>
</html>
""".encode("utf-8")


class PublisherHandler(BaseHTTPRequestHandler):
    server_version = "RafexFirefoxOSPublisher/1.0"
    sys_version = ""

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        self._serve(head_only=False)

    def do_HEAD(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        self._serve(head_only=True)

    def log_message(self, fmt: str, *args: object) -> None:
        # Paths are fixed and contain no user data; omit request headers and query strings.
        print("publisher: " + fmt % args, flush=True)

    def _serve(self, *, head_only: bool) -> None:
        path = urlsplit(self.path).path
        app_root = self.server.app_root  # type: ignore[attr-defined]
        origin = self.server.public_origin  # type: ignore[attr-defined]

        if path in {"/", "/install.html"}:
            body = installation_page(origin)
            content_type = "text/html; charset=utf-8"
        elif path == "/manifest.webapp":
            try:
                data = json.loads((app_root / "manifest.webapp").read_text(encoding="utf-8"))
                data["installs_allowed_from"] = [origin]
                body = (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
            except (OSError, json.JSONDecodeError):
                self._error(HTTPStatus.INTERNAL_SERVER_ERROR, "manifest no disponible")
                return
            # Keep the historical Firefox OS MIME type exact for old clients.
            content_type = "application/x-web-app-manifest+json"
        elif path in APP_FILES:
            filename, content_type = APP_FILES[path]
            try:
                body = (app_root / filename).read_bytes()
            except OSError:
                self._error(HTTPStatus.NOT_FOUND, "recurso no disponible")
                return
        else:
            self._error(HTTPStatus.NOT_FOUND, "recurso no encontrado")
            return

        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        if not head_only:
            self.wfile.write(body)

    def _error(self, status: HTTPStatus, message: str) -> None:
        body = (message + "\n").encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)


class PublisherServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main() -> int:
    parser = argparse.ArgumentParser(description="Servidor local de Firefox OS Hola Mundo")
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--app-root", default="/srv/app")
    parser.add_argument("--public-origin", default=os.environ.get("PUBLIC_ORIGIN", ""))
    args = parser.parse_args()

    app_root = Path(args.app_root).resolve()
    if not args.public_origin.startswith("http://"):
        parser.error("PUBLIC_ORIGIN debe usar http:// para el navegador legado")
    if not (app_root / "manifest.webapp").is_file():
        parser.error("manifest.webapp no está disponible")

    server = PublisherServer((args.bind, args.port), PublisherHandler)
    server.app_root = app_root  # type: ignore[attr-defined]
    server.public_origin = args.public_origin.rstrip("/")  # type: ignore[attr-defined]
    print(f"publisher: escuchando en {server.public_origin}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
