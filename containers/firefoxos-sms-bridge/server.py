#!/usr/bin/env python3
"""Rootless, local-only SMS queue and Firefox OS hosted-app publisher."""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import re
import secrets
import signal
import tempfile
import threading
import time
from contextlib import contextmanager
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Iterator
from urllib.parse import urlsplit


RETENTION_SECONDS = 30 * 24 * 60 * 60
PAIRING_SECONDS = 10 * 60
MESSAGE_EXPIRY_SECONDS = 24 * 60 * 60
MAX_BODY_BYTES = 8192
E164_RE = re.compile(r"^\+[1-9][0-9]{7,14}$")
REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9._:-]{1,96}$")

GSM7_BASIC = set(
    "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞ\fÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?"
    "¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà"
)
GSM7_EXTENDED = set("^{}\\[~]|€")

APP_FILES = {
    "/index.html": ("index.html", "text/html; charset=utf-8"),
    "/style.css": ("style.css", "text/css; charset=utf-8"),
    "/app.js": ("app.js", "application/javascript; charset=utf-8"),
}


def now() -> int:
    return int(time.time())


def sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def segment_units(body: str) -> tuple[str, int]:
    units = 0
    for character in body:
        if character in GSM7_BASIC:
            units += 1
        elif character in GSM7_EXTENDED:
            units += 2
        else:
            return "unicode", len(body)
    return "gsm7", units


def validate_message(recipient: Any, body: Any, request_id: Any) -> tuple[str, str, str]:
    if not isinstance(recipient, str) or not E164_RE.fullmatch(recipient):
        raise ValueError("destinatario E.164 inválido")
    if not isinstance(body, str) or not body or "\x00" in body:
        raise ValueError("texto SMS vacío o inválido")
    if not isinstance(request_id, str) or not REQUEST_ID_RE.fullmatch(request_id):
        raise ValueError("identificador de solicitud inválido")
    encoding, units = segment_units(body)
    if (encoding == "gsm7" and units > 160) or (encoding == "unicode" and units > 70):
        raise ValueError("el texto supera un segmento SMS")
    return recipient, body, request_id


def new_state() -> dict[str, Any]:
    return {"pairing": None, "token_hash": None, "messages": []}


class StateStore:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        os.chmod(self.root, 0o700)
        self.state_path = self.root / "state.json"
        self.lock_path = self.root / ".state.lock"
        self.lock_path.touch(mode=0o600, exist_ok=True)
        os.chmod(self.lock_path, 0o600)

    def _load(self) -> dict[str, Any]:
        if not self.state_path.exists():
            return new_state()
        try:
            data = json.loads(self.state_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            raise RuntimeError("estado del puente ilegible")
        if not isinstance(data, dict) or not isinstance(data.get("messages", []), list):
            raise RuntimeError("estado del puente inválido")
        data.setdefault("pairing", None)
        data.setdefault("token_hash", None)
        return data

    def _save(self, data: dict[str, Any]) -> None:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=self.root, prefix=".state.", delete=False
        ) as temporary:
            json.dump(data, temporary, ensure_ascii=False, separators=(",", ":"))
            temporary.write("\n")
            temporary.flush()
            os.fchmod(temporary.fileno(), 0o600)
            temporary_path = Path(temporary.name)
        os.replace(temporary_path, self.state_path)
        os.chmod(self.state_path, 0o600)

    @staticmethod
    def _prune(data: dict[str, Any], timestamp: int) -> None:
        pairing = data.get("pairing")
        if isinstance(pairing, dict) and int(pairing.get("expires_at", 0)) <= timestamp:
            data["pairing"] = None
        for message in data.get("messages", []):
            if message.get("status") == "queued" and int(message.get("expires_at", 0)) <= timestamp:
                message["status"] = "expired"
                message["expired_at"] = timestamp
        data["messages"] = [
            message
            for message in data.get("messages", [])
            if timestamp - int(message.get("created_at", timestamp)) <= RETENTION_SECONDS
        ]

    @contextmanager
    def transaction(self) -> Iterator[dict[str, Any]]:
        import fcntl

        with self.lock_path.open("r+", encoding="utf-8") as lock:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
            data = self._load()
            self._prune(data, now())
            try:
                yield data
                self._save(data)
            finally:
                fcntl.flock(lock.fileno(), fcntl.LOCK_UN)

    def issue_pairing(self) -> str:
        code = f"{secrets.randbelow(100_000_000):08d}"
        with self.transaction() as data:
            data["pairing"] = {
                "code_hash": sha256(code),
                "expires_at": now() + PAIRING_SECONDS,
                "attempts": 0,
            }
        return code

    def exchange_pairing(self, code: Any) -> str:
        if not isinstance(code, str) or not re.fullmatch(r"[0-9]{8}", code):
            raise PermissionError("código inválido")
        with self.transaction() as data:
            pairing = data.get("pairing")
            if not isinstance(pairing, dict) or int(pairing.get("expires_at", 0)) <= now():
                raise PermissionError("código no disponible")
            if int(pairing.get("attempts", 0)) >= 5:
                raise PermissionError("código no disponible")
            pairing["attempts"] = int(pairing.get("attempts", 0)) + 1
            if not hmac.compare_digest(str(pairing.get("code_hash", "")), sha256(code)):
                raise PermissionError("código inválido")
            token = secrets.token_urlsafe(32)
            data["token_hash"] = sha256(token)
            data["pairing"] = None
            return token

    def token_is_valid(self, token: str | None) -> bool:
        if not token:
            return False
        with self.transaction() as data:
            stored = data.get("token_hash")
            return isinstance(stored, str) and hmac.compare_digest(stored, sha256(token))

    def revoke(self) -> None:
        with self.transaction() as data:
            data["token_hash"] = None

    def enqueue(self, recipient: str, body: str, request_id: str) -> tuple[dict[str, Any], bool]:
        recipient, body, request_id = validate_message(recipient, body, request_id)
        with self.transaction() as data:
            for message in data["messages"]:
                if message.get("request_id") == request_id:
                    return dict(message), True
            if any(message.get("status") == "queued" for message in data["messages"]):
                raise RuntimeError("ya existe un mensaje pendiente")
            timestamp = now()
            message = {
                "id": secrets.token_urlsafe(12),
                "request_id": request_id,
                "recipient": recipient,
                "body": body,
                "status": "queued",
                "created_at": timestamp,
                "expires_at": timestamp + MESSAGE_EXPIRY_SECONDS,
            }
            data["messages"].append(message)
            return dict(message), False

    def pending(self) -> dict[str, Any] | None:
        with self.transaction() as data:
            for message in data["messages"]:
                if message.get("status") == "queued":
                    return dict(message)
        return None

    def mark(self, message_id: str, status: str) -> dict[str, Any] | None:
        with self.transaction() as data:
            for message in data["messages"]:
                if message.get("id") != message_id:
                    continue
                current = message.get("status")
                if current == status or (current == "presented" and status == "presented"):
                    return dict(message)
                if current != "queued":
                    raise RuntimeError("mensaje ya procesado")
                message["status"] = status
                message[f"{status}_at"] = now()
                return dict(message)
        return None

    def history(self) -> list[dict[str, Any]]:
        with self.transaction() as data:
            return [dict(message) for message in reversed(data["messages"])]

    def purge(self) -> int:
        with self.transaction() as data:
            before = len(data["messages"])
            timestamp = now()
            data["messages"] = [
                message
                for message in data["messages"]
                if timestamp - int(message.get("created_at", timestamp)) <= RETENTION_SECONDS
            ]
            return before - len(data["messages"])

    def summary(self) -> dict[str, Any]:
        with self.transaction() as data:
            counts: dict[str, int] = {}
            for message in data["messages"]:
                status = str(message.get("status", "unknown"))
                counts[status] = counts.get(status, 0) + 1
            return {
                "token_configured": bool(data.get("token_hash")),
                "pairing_pending": bool(data.get("pairing")),
                "messages": counts,
            }


def installation_page(origin: str) -> bytes:
    return f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Rafex · Puente SMS</title>
<style>body{{background:#18202b;color:#f5f7fa;font:18px sans-serif;margin:0;padding:2rem}}main{{margin:auto;max-width:28rem}}button{{background:#ff7043;border:0;border-radius:.5rem;color:#171d26;font:inherit;font-weight:700;padding:.8rem 1rem;width:100%}}#status{{color:#9fe3b1;min-height:1.5rem}}</style></head>
<body><main><p>RAFEX · FIREFOX OS</p><h1>Puente SMS</h1>
<p>Instala la aplicación hospedada en este Flame. El envío siempre se confirma dentro de Mensajes.</p>
<button id="install" type="button">Instalar en este Flame</button><p id="status" role="status" aria-live="polite"></p>
<p><a href="/index.html">Abrir la aplicación</a></p></main>
<script>(function(){{var b=document.getElementById('install'),s=document.getElementById('status'),u={json.dumps(origin + '/manifest.webapp')};b.onclick=function(){{if(!navigator.mozApps||!navigator.mozApps.install){{s.textContent='Este navegador no permite instalar aplicaciones Firefox OS.';return}}b.disabled=true;s.textContent='Esperando confirmación…';var r=navigator.mozApps.install(u);r.onsuccess=function(){{s.textContent='Aplicación instalada.'}};r.onerror=function(){{b.disabled=false;s.textContent='No se instaló: '+(r.error||'cancelado')}}}}}})();</script></body></html>""".encode("utf-8")


def admin_page() -> bytes:
    return """<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Rafex · Consola SMS</title><style>body{background:#18202b;color:#f5f7fa;font:16px sans-serif;margin:0;padding:2rem}main{margin:auto;max-width:42rem}label{display:block;margin-top:1rem}input,textarea,button{box-sizing:border-box;font:inherit;padding:.7rem;width:100%}textarea{min-height:7rem}button{background:#ff7043;border:0;border-radius:.4rem;margin-top:1rem;font-weight:700}#status{min-height:1.5rem;color:#9fe3b1}.item{border-top:1px solid #667085;margin-top:1rem;padding-top:1rem}.meta{color:#a9b4c5;font-size:.85rem}</style></head>
<body><main><p>RAFEX · THINKPAD</p><h1>Cola local de SMS</h1>
<p>Solo la ThinkPad local puede crear mensajes. El Flame los presenta en Mensajes para confirmación manual.</p>
<form id="form"><label>Destinatario E.164<input id="to" required placeholder="+5255…"></label><label>Mensaje<textarea id="body" maxlength="160" required></textarea></label><button>Agregar a la cola</button></form><p id="status" role="status"></p><h2>Historial</h2><section id="history"></section>
<script>(function(){var f=document.getElementById('form'),s=document.getElementById('status'),h=document.getElementById('history');function req(method,url,data,done){var x=new XMLHttpRequest();x.open(method,url,true);x.setRequestHeader('Content-Type','application/json');x.onreadystatechange=function(){if(x.readyState!==4)return;var d;try{d=JSON.parse(x.responseText)}catch(e){d={error:'respuesta inválida'}};done(x.status,d)};x.send(data?JSON.stringify(data):null)}function render(){req('GET','/api/v1/admin/history',null,function(code,d){if(code!==200){s.textContent='No se pudo leer el historial.';return}h.textContent='';d.messages.forEach(function(m){var a=document.createElement('article');a.className='item';var t=document.createElement('div');t.textContent=m.recipient+' · '+m.status;a.appendChild(t);var b=document.createElement('div');b.className='meta';b.textContent=m.body;a.appendChild(b);h.appendChild(a)})})}f.onsubmit=function(e){e.preventDefault();var to=document.getElementById('to').value,body=document.getElementById('body').value,id='web-'+Date.now();req('POST','/api/v1/admin/messages',{recipient:to,body:body,request_id:id},function(code,d){s.textContent=code===201?'Mensaje agregado.':(d.error||'No se pudo agregar.');if(code===201){f.reset();render()}})};render();setInterval(render,5000)}());</script></main></body></html>""".encode("utf-8")


class BridgeServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


class BridgeHandler(BaseHTTPRequestHandler):
    server_version = "RafexFirefoxOSSMS/1.0"
    sys_version = ""

    def log_message(self, fmt: str, *args: object) -> None:
        role = getattr(self.server, "role", "unknown")  # type: ignore[attr-defined]
        path = urlsplit(self.path).path
        print(f"sms-bridge: {role} {self.command} {path} {args[-1] if args else ''}", flush=True)

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        path = urlsplit(self.path).path
        role = getattr(self.server, "role", "")  # type: ignore[attr-defined]
        if role == "admin":
            if path in {"/", "/admin.html"}:
                self._send(HTTPStatus.OK, admin_page(), "text/html; charset=utf-8")
                return
            if path == "/api/v1/admin/status":
                self._json(HTTPStatus.OK, self.server.store.summary())  # type: ignore[attr-defined]
                return
            if path == "/api/v1/admin/history":
                self._json(HTTPStatus.OK, {"messages": self.server.store.history()})  # type: ignore[attr-defined]
                return
        if role == "phone":
            if path in {"/", "/install.html"}:
                self._send(HTTPStatus.OK, installation_page(self.server.public_origin), "text/html; charset=utf-8")  # type: ignore[attr-defined]
                return
            if path == "/manifest.webapp":
                self._send(HTTPStatus.OK, self._manifest(), "application/x-web-app-manifest+json")
                return
            if path in APP_FILES:
                filename, content_type = APP_FILES[path]
                try:
                    body = (self.server.app_root / filename).read_bytes()  # type: ignore[attr-defined]
                except OSError:
                    self._error(HTTPStatus.NOT_FOUND, "recurso no disponible")
                    return
                self._send(HTTPStatus.OK, body, content_type)
                return
            if path == "/api/v1/messages/pending":
                if not self._authorized():
                    return
                self._json(HTTPStatus.OK, {"message": self.server.store.pending()})  # type: ignore[attr-defined]
                return
        self._error(HTTPStatus.NOT_FOUND, "recurso no encontrado")

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        path = urlsplit(self.path).path
        role = getattr(self.server, "role", "")  # type: ignore[attr-defined]
        message_match = re.fullmatch(r"/api/v1/messages/([A-Za-z0-9_-]{8,32})/(presented|cancel)", path)
        payload: dict[str, Any] = {}
        if not (role == "phone" and message_match):
            parsed_payload = self._read_json()
            if parsed_payload is None:
                return
            payload = parsed_payload
        store: StateStore = self.server.store  # type: ignore[attr-defined]

        if role == "phone" and path == "/api/v1/pair/exchange":
            try:
                token = store.exchange_pairing(payload.get("code"))
            except PermissionError:
                self._json(HTTPStatus.FORBIDDEN, {"error": "código no válido o expirado"})
                return
            self._json(HTTPStatus.OK, {"token": token})
            return

        if role == "phone" and not self._authorized():
            return
        if role == "phone" and message_match:
            message_id = message_match.group(1)
            status = "presented" if message_match.group(2) == "presented" else "cancelled"
            if not message_id:
                self._json(HTTPStatus.BAD_REQUEST, {"error": "mensaje inválido"})
                return
            try:
                message = store.mark(message_id, status)
            except RuntimeError:
                self._json(HTTPStatus.CONFLICT, {"error": "mensaje ya procesado"})
                return
            if message is None:
                self._json(HTTPStatus.NOT_FOUND, {"error": "mensaje no encontrado"})
                return
            self._json(HTTPStatus.OK, {"message": message})
            return

        if role == "admin" and path == "/api/v1/admin/pair":
            self._json(HTTPStatus.OK, {"code": store.issue_pairing(), "expires_in": PAIRING_SECONDS})
            return
        if role == "admin" and path == "/api/v1/admin/revoke":
            store.revoke()
            self._json(HTTPStatus.OK, {"revoked": True})
            return
        if role == "admin" and path == "/api/v1/admin/purge":
            self._json(HTTPStatus.OK, {"removed": store.purge()})
            return
        if role == "admin" and path == "/api/v1/admin/messages":
            try:
                message, duplicate = store.enqueue(
                    payload.get("recipient"), payload.get("body"), payload.get("request_id")
                )
            except ValueError as exc:
                self._json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
                return
            except RuntimeError:
                self._json(HTTPStatus.CONFLICT, {"error": "ya existe un mensaje pendiente"})
                return
            self._json(HTTPStatus.OK if duplicate else HTTPStatus.CREATED, {"message": message, "duplicate": duplicate})
            return
        self._error(HTTPStatus.NOT_FOUND, "recurso no encontrado")

    def _manifest(self) -> bytes:
        app_root: Path = self.server.app_root  # type: ignore[attr-defined]
        try:
            data = json.loads((app_root / "manifest.webapp").read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return b"{}\n"
        data["installs_allowed_from"] = [self.server.public_origin]  # type: ignore[attr-defined]
        return (json.dumps(data, ensure_ascii=False, indent=2) + "\n").encode("utf-8")

    def _read_json(self) -> dict[str, Any] | None:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_BODY_BYTES:
            self._json(HTTPStatus.BAD_REQUEST, {"error": "petición inválida"})
            return None
        try:
            data = json.loads(self.rfile.read(length).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._json(HTTPStatus.BAD_REQUEST, {"error": "JSON inválido"})
            return None
        if not isinstance(data, dict):
            self._json(HTTPStatus.BAD_REQUEST, {"error": "JSON inválido"})
            return None
        return data

    def _authorized(self) -> bool:
        header = self.headers.get("Authorization", "")
        token = header[7:].strip() if header.startswith("Bearer ") else None
        if self.server.store.token_is_valid(token):  # type: ignore[attr-defined]
            return True
        self._json(HTTPStatus.UNAUTHORIZED, {"error": "autorización requerida"})
        return False

    def _json(self, status: HTTPStatus, data: dict[str, Any]) -> None:
        self._send(status, (json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8"), "application/json; charset=utf-8")

    def _error(self, status: HTTPStatus, message: str) -> None:
        self._json(status, {"error": message})

    def _send(self, status: HTTPStatus, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)


def main() -> int:
    parser = argparse.ArgumentParser(description="Puente SMS local para Firefox OS")
    parser.add_argument("--state-dir", default="/var/lib/rafex")
    parser.add_argument("--app-root", default="/srv/app")
    parser.add_argument("--phone-origin", required=True)
    parser.add_argument("--admin-port", type=int, default=8786)
    parser.add_argument("--phone-port", type=int, default=8787)
    parser.add_argument("--admin-bind", default="0.0.0.0")
    parser.add_argument("--phone-bind", default="0.0.0.0")
    args = parser.parse_args()

    if not args.phone_origin.startswith("http://"):
        parser.error("--phone-origin debe usar http://")
    app_root = Path(args.app_root).resolve()
    for filename in ("manifest.webapp", "index.html", "style.css", "app.js"):
        if not (app_root / filename).is_file():
            parser.error(f"falta recurso de aplicación: {filename}")
    store = StateStore(Path(args.state_dir).resolve())
    servers: list[BridgeServer] = []
    for role, bind, port in (("admin", args.admin_bind, args.admin_port), ("phone", args.phone_bind, args.phone_port)):
        server = BridgeServer((bind, port), BridgeHandler)
        server.role = role
        server.store = store
        server.app_root = app_root
        server.public_origin = args.phone_origin.rstrip("/")
        servers.append(server)

    stop_event = threading.Event()

    def stop(_signum: int, _frame: Any) -> None:
        stop_event.set()
        for server in servers:
            server.shutdown()

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    threads = [threading.Thread(target=server.serve_forever, daemon=True) for server in servers]
    for thread in threads:
        thread.start()
    print("sms-bridge: listeners ready admin=local phone=lan", flush=True)
    stop_event.wait()
    for server in servers:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
