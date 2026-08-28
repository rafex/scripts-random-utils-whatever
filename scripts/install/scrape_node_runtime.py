#!/usr/bin/env python3
"""Obtiene un binario oficial de Node.js y su checksum SHA-256."""

from __future__ import annotations

import argparse
import json
import platform
import re
import sys
from urllib.request import Request, urlopen


INDEX_URL = "https://nodejs.org/dist/index.json"


def fetch_json(url: str) -> list[dict[str, object]]:
    request = Request(url, headers={"User-Agent": "rafex-node-runtime-scraper/1.0"})
    with urlopen(request, timeout=30) as response:  # noqa: S310 - URL is fixed HTTPS.
        if not response.geturl().startswith("https://"):
            raise RuntimeError("redirección insegura")
        value = json.load(response)
    if not isinstance(value, list):
        raise RuntimeError("respuesta inválida de Node.js")
    return value


def arch(value: str) -> str:
    aliases = {"x86_64": "x64", "amd64": "x64", "x64": "x64", "aarch64": "arm64", "arm64": "arm64"}
    try:
        return aliases[value.lower()]
    except KeyError as exc:
        raise ValueError(f"arquitectura no soportada: {value}") from exc


def version_key(value: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", value))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", default="lts", help="lts, mayor o versión exacta")
    parser.add_argument("--architecture", default=arch(platform.machine()))
    args = parser.parse_args()
    architecture = arch(args.architecture)
    releases = fetch_json(INDEX_URL)
    candidates = [
        item for item in releases
        if isinstance(item.get("version"), str)
        and f"linux-{architecture}" in item.get("files", [])
        and item.get("version", "").startswith("v")
    ]
    if args.version == "lts":
        candidates = [item for item in candidates if item.get("lts")]
    elif args.version.isdigit():
        candidates = [
            item for item in candidates
            if str(item.get("version", "")).startswith(f"v{args.version}.")
        ]
    else:
        requested = args.version if args.version.startswith("v") else f"v{args.version}"
        candidates = [item for item in candidates if item.get("version") == requested]
    if not candidates:
        raise RuntimeError(f"Node.js no tiene una versión {args.version} para {architecture}")
    release = max(candidates, key=lambda item: version_key(str(item["version"])))
    version = str(release["version"])[1:]
    filename = f"node-v{version}-linux-{architecture}.tar.xz"
    base = f"https://nodejs.org/dist/v{version}"
    checksum_text = fetch_text(f"{base}/SHASUMS256.txt")
    checksum = next(
        (line.split()[0] for line in checksum_text.splitlines() if line.endswith(filename)),
        None,
    )
    if not checksum or not re.fullmatch(r"[0-9a-fA-F]{64}", checksum):
        raise RuntimeError(f"no se encontró checksum de {filename}")
    json.dump({
        "provider": "nodejs",
        "version": version,
        "architecture": architecture,
        "filename": filename,
        "download_url": f"{base}/{filename}",
        "checksum_url": f"{base}/SHASUMS256.txt",
        "checksum_algorithm": "sha256",
        "checksum": checksum.lower(),
        "source_url": "https://nodejs.org/dist/",
    }, sys.stdout, indent=2)
    print()
    return 0


def fetch_text(url: str) -> str:
    request = Request(url, headers={"User-Agent": "rafex-node-runtime-scraper/1.0"})
    with urlopen(request, timeout=30) as response:  # noqa: S310 - URL is fixed HTTPS.
        if not response.geturl().startswith("https://"):
            raise RuntimeError("redirección insegura")
        return response.read().decode("utf-8")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
