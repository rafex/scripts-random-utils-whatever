#!/usr/bin/env python3
"""Obtiene descargas oficiales verificables de Maven o Gradle."""

from __future__ import annotations

import argparse
import json
import re
import sys
from urllib.request import Request, urlopen


def fetch(url: str) -> bytes:
    request = Request(url, headers={"User-Agent": "rafex-build-runtime-scraper/1.0"})
    with urlopen(request, timeout=30) as response:  # noqa: S310 - fixed HTTPS URLs.
        if not response.geturl().startswith("https://"):
            raise RuntimeError("redirección insegura")
        return response.read()


def version_key(value: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", value))


def maven(version: str) -> dict[str, str]:
    listing_url = "https://archive.apache.org/dist/maven/maven-3/"
    listing = fetch(listing_url).decode("utf-8")
    versions = sorted(set(re.findall(r'href="(3\.[0-9]+\.[0-9]+)/"', listing)), key=version_key)
    if version == "latest":
        selected = versions[-1]
    elif version in versions:
        selected = version
    else:
        raise RuntimeError(f"Maven no tiene la versión {version} en el archivo oficial")
    base = f"https://archive.apache.org/dist/maven/maven-3/{selected}/binaries"
    filename = f"apache-maven-{selected}-bin.tar.gz"
    checksum_text = fetch(f"{base}/{filename}.sha512").decode("utf-8")
    checksum = re.search(r"[0-9a-fA-F]{128}", checksum_text)
    if not checksum:
        raise RuntimeError(f"no se encontró SHA-512 de {filename}")
    return {
        "tool": "maven", "version": selected, "filename": filename,
        "download_url": f"{base}/{filename}", "checksum_url": f"{base}/{filename}.sha512",
        "checksum_algorithm": "sha512", "checksum": checksum.group(0).lower(),
        "source_url": "https://maven.apache.org/download.cgi",
    }


def gradle(version: str) -> dict[str, str]:
    if version == "latest":
        data = json.loads(fetch("https://services.gradle.org/versions/current"))
        selected = str(data["version"])
        url = str(data["downloadUrl"])
        checksum = str(data.get("checksum", ""))
    else:
        selected = version.removeprefix("v")
        if not re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", selected):
            raise ValueError("Gradle requiere latest o una versión como 9.7.1")
        url = f"https://services.gradle.org/distributions/gradle-{selected}-bin.zip"
        checksum = ""
    if not checksum:
        checksum = fetch(f"{url}.sha256").decode("utf-8").split()[0]
    if not re.fullmatch(r"[0-9a-fA-F]{64}", checksum):
        raise RuntimeError("checksum SHA-256 inválido para Gradle")
    return {
        "tool": "gradle", "version": selected, "filename": f"gradle-{selected}-bin.zip",
        "download_url": url, "checksum_url": f"{url}.sha256",
        "checksum_algorithm": "sha256", "checksum": checksum.lower(),
        "source_url": "https://gradle.org/releases/",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tool", choices=("maven", "gradle"), required=True)
    parser.add_argument("--version", default="latest")
    args = parser.parse_args()
    result = maven(args.version) if args.tool == "maven" else gradle(args.version)
    json.dump(result, sys.stdout, indent=2)
    print()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
