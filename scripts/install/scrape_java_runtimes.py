#!/usr/bin/env python3
"""Extract official Java runtime downloads for Linux.

The scraper uses provider APIs or official download pages and emits JSON for
the companion installer. It intentionally has no third-party dependencies.
"""

from __future__ import annotations

import argparse
import json
import platform
import re
import sys
from datetime import datetime, timezone
from html import unescape
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlparse
from urllib.request import Request, urlopen


ADOPTIUM_API = "https://api.adoptium.net/v3"
GRAALVM_API = "https://api.github.com/repos/graalvm/graalvm-ce-builds"
GRAALVM_PAGE = "https://www.graalvm.org/downloads/"
SEMERU_PAGE = "https://developer.ibm.com/languages/java/semeru-runtimes/downloads/"
USER_AGENT = "rafex-java-runtime-scraper/1.0"

PROVIDERS = ("temurin", "graalvm-community", "graalvm-oracle", "semeru")


def fetch_bytes(url: str, timeout: int, accept: str = "*/*") -> bytes:
    if urlparse(url).scheme != "https":
        raise RuntimeError(f"URL insegura, se requiere HTTPS: {url}")
    request = Request(
        url,
        headers={"Accept": accept, "User-Agent": USER_AGENT},
    )
    with urlopen(request, timeout=timeout) as response:  # noqa: S310 - HTTPS is enforced above.
        final_url = response.geturl()
        if urlparse(final_url).scheme != "https":
            raise RuntimeError(f"redirección insegura: {final_url}")
        return response.read()


def fetch_text(url: str, timeout: int, accept: str = "text/plain,*/*") -> str:
    return fetch_bytes(url, timeout, accept).decode("utf-8", errors="strict")


def fetch_json(url: str, timeout: int) -> object:
    return json.loads(fetch_text(url, timeout, "application/json"))


def architecture_name(value: str) -> str:
    aliases = {
        "x86_64": "x64",
        "amd64": "x64",
        "x64": "x64",
        "aarch64": "aarch64",
        "arm64": "aarch64",
    }
    try:
        return aliases[value.lower()]
    except KeyError as exc:
        raise ValueError(f"arquitectura no soportada: {value}") from exc


def version_sort_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", version))


def checksum_from_text(text: str, length: int) -> str:
    match = re.search(rf"\b([0-9a-fA-F]{{{length}}})\b", text)
    if not match:
        raise RuntimeError("no se encontró un checksum válido en la respuesta")
    return match.group(1).lower()


def temurin(version: str, image: str, architecture: str, timeout: int) -> dict[str, object]:
    info = fetch_json(f"{ADOPTIUM_API}/info/available_releases", timeout)
    if not isinstance(info, dict):
        raise RuntimeError("respuesta inválida de Adoptium available_releases")
    available = info.get("available_releases", [])
    if not isinstance(available, list):
        raise RuntimeError("Adoptium no devolvió versiones disponibles")
    if version == "latest":
        major = int(info["most_recent_lts"])
    elif version.isdigit():
        major = int(version)
    else:
        raise ValueError("Temurin acepta `latest` o una versión mayor como 8, 11, 17, 21 o 25")
    if major not in [int(item) for item in available]:
        raise ValueError(f"Temurin no publica la versión mayor {major}")

    query = (
        f"architecture={architecture}&image_type={image}&os=linux&vendor=eclipse"
        "&release_type=ga"
    )
    assets = fetch_json(f"{ADOPTIUM_API}/assets/latest/{major}/hotspot?{query}", timeout)
    if not isinstance(assets, list) or not assets:
        raise RuntimeError(f"Adoptium no devolvió un binario para Temurin {major}")
    asset = assets[0]
    binary = asset.get("binary", {})
    package = binary.get("package", {})
    if not package.get("link") or not package.get("checksum"):
        raise RuntimeError("respuesta de Adoptium sin enlace o checksum")
    return {
        "provider": "temurin",
        "distribution": "Eclipse Temurin",
        "version": asset.get("release_name", str(major)),
        "major": major,
        "image": image,
        "architecture": architecture,
        "filename": package["name"],
        "download_url": package["link"],
        "checksum_algorithm": "sha256",
        "checksum": package["checksum"].lower(),
        "checksum_url": package.get("checksum_link"),
        "signature_url": package.get("signature_link"),
        "release_url": asset.get("release_link"),
        "source_url": "https://adoptium.net/temurin/releases",
        "available_versions": sorted((int(item) for item in available)),
    }


def graalvm_community(
    version: str, architecture: str, timeout: int
) -> dict[str, object]:
    releases = fetch_json(f"{GRAALVM_API}/releases?per_page=100", timeout)
    if not isinstance(releases, list):
        raise RuntimeError("respuesta inválida de releases de GraalVM Community")
    releases = [
        item
        for item in releases
        if not item.get("draft") and not item.get("prerelease")
    ]
    if version != "latest":
        matching = [
            item
            for item in releases
            if item.get("tag_name") == f"graal-{version}"
            or item.get("tag_name") == f"jdk-{version}"
            or str(item.get("tag_name", "")).endswith(f"-{version}")
        ]
        if not matching and version.isdigit():
            matching = [
                item
                for item in releases
                if re.search(rf"(?:graal|jdk)-{re.escape(version)}(?:\.|$)", item.get("tag_name", ""))
            ]
        releases = matching
    if not releases:
        raise RuntimeError(f"no se encontró GraalVM Community {version}")
    release = releases[0]
    arch_marker = f"linux-{architecture}_bin.tar.gz"
    assets = release.get("assets", [])
    archive = next(
        (
            asset
            for asset in assets
            if asset.get("name", "").startswith("graalvm-community-jdk-")
            and arch_marker in asset.get("name", "")
        ),
        None,
    )
    if archive is None:
        raise RuntimeError(f"GraalVM Community no tiene binario Linux {architecture}")
    checksum_asset = next(
        (asset for asset in assets if asset.get("name") == f"{archive['name']}.sha256"),
        None,
    )
    if checksum_asset is None:
        raise RuntimeError(f"GraalVM Community no publicó checksum para {archive['name']}")
    checksum = checksum_from_text(fetch_text(checksum_asset["browser_download_url"], timeout), 64)
    available = [str(item.get("tag_name", "")) for item in releases]
    return {
        "provider": "graalvm-community",
        "distribution": "GraalVM Community",
        "version": release.get("tag_name", "unknown").removeprefix("graal-"),
        "image": "jdk",
        "architecture": architecture,
        "filename": archive["name"],
        "download_url": archive["browser_download_url"],
        "checksum_algorithm": "sha256",
        "checksum": checksum,
        "checksum_url": checksum_asset["browser_download_url"],
        "release_url": release.get("html_url"),
        "source_url": "https://github.com/graalvm/graalvm-ce-builds/releases",
        "available_versions": available,
    }


def graalvm_oracle(version: str, architecture: str, timeout: int) -> dict[str, object]:
    if version != "latest":
        raise ValueError("Oracle GraalVM admite únicamente `latest`; usa Community para versiones archivadas")
    page = fetch_text(GRAALVM_PAGE, timeout)
    page = unescape(page)
    pattern = re.compile(
        r"https://gds\.oracle\.com/download/graal/([^/]+)/latest/"
        r"(graalvm-jdk-([^/]+)_linux-(x64|aarch64)_bin\.tar\.gz)"
    )
    matches = [match for match in pattern.finditer(page) if match.group(4) == architecture]
    if not matches:
        raise RuntimeError(f"Oracle GraalVM no tiene enlace Linux {architecture} en su página oficial")
    product, filename, _, _ = matches[0].groups()
    major_match = re.search(r"(?:^|-)j?([0-9]+)(?:_|$)", filename)
    if not major_match:
        raise RuntimeError(f"no se pudo determinar la versión Oracle GraalVM: {filename}")
    major = major_match.group(1)
    oracle_filename = re.sub(r"-25i3-25_", "-25_", filename)
    oracle_filename = re.sub(r"-\d+i\d+-\d+_", f"-{major}_", oracle_filename)
    download_url = f"https://download.oracle.com/graalvm/{major}/latest/{oracle_filename}"
    checksum_url = f"{download_url}.sha256"
    checksum = checksum_from_text(fetch_text(checksum_url, timeout), 64)
    return {
        "provider": "graalvm-oracle",
        "distribution": "Oracle GraalVM",
        "version": f"{product}-{major}",
        "image": "jdk",
        "architecture": architecture,
        "filename": oracle_filename,
        "download_url": download_url,
        "checksum_algorithm": "sha256",
        "checksum": checksum,
        "checksum_url": checksum_url,
        "release_url": GRAALVM_PAGE,
        "source_url": GRAALVM_PAGE,
    }


def semeru(version: str, image: str, architecture: str, timeout: int) -> dict[str, object]:
    candidates: list[tuple[str, str]] = []
    page = unescape(fetch_text(SEMERU_PAGE, timeout))
    page_pattern = re.compile(
        r"https://github\.com/ibmruntimes/semeru\d+-binaries/releases/download/"
        r"[^\"'<> ]+/ibm-semeru-open-(jdk|jre)_"
        rf"{re.escape(architecture)}_linux_([0-9.]+)\.tar\.gz"
    )
    candidates.extend(
        (match.group(2), match.group(0))
        for match in page_pattern.finditer(page)
        if match.group(1) == image
    )

    if version != "latest":
        major_match = re.match(r"^(\d+)", version)
        if not major_match:
            raise ValueError("Semeru acepta `latest`, una versión mayor o una versión exacta")
        major = major_match.group(1)
        releases = fetch_json(
            f"https://api.github.com/repos/ibmruntimes/semeru{major}-binaries/releases?per_page=100",
            timeout,
        )
        if not isinstance(releases, list):
            raise RuntimeError("respuesta inválida de releases de IBM Semeru")
        api_pattern = re.compile(
            r"^ibm-semeru-open-(jdk|jre)_"
            rf"{re.escape(architecture)}_linux_([0-9.]+)\.tar\.gz$"
        )
        candidates = []
        for release in releases:
            if release.get("draft") or release.get("prerelease"):
                continue
            for asset in release.get("assets", []):
                match = api_pattern.match(asset.get("name", ""))
                if match and match.group(1) == image:
                    candidates.append((match.group(2), asset["browser_download_url"]))

    unique = {item[1]: item for item in candidates}
    candidates = list(unique.values())
    if version != "latest":
        candidates = [
            item for item in candidates
            if item[0] == version or item[0].startswith(f"{version}.")
        ]
    if not candidates:
        raise RuntimeError(f"IBM Semeru no tiene {image} Linux {architecture} para {version}")
    selected_version, download_url = max(candidates, key=lambda item: version_sort_key(item[0]))
    checksum_url = f"{download_url}.sha256.txt"
    checksum = checksum_from_text(fetch_text(checksum_url, timeout), 64)
    filename = download_url.rsplit("/", 1)[-1]
    return {
        "provider": "semeru",
        "distribution": "IBM Semeru",
        "version": selected_version,
        "image": image,
        "architecture": architecture,
        "filename": filename,
        "download_url": download_url,
        "checksum_algorithm": "sha256",
        "checksum": checksum,
        "checksum_url": checksum_url,
        "release_url": download_url.rsplit("/download/", 1)[0],
        "source_url": SEMERU_PAGE,
        "available_versions": sorted({item[0] for item in candidates}, key=version_sort_key, reverse=True),
    }


def scrape(provider: str, version: str, image: str, architecture: str, timeout: int) -> dict[str, object]:
    selected = PROVIDERS if provider == "all" else (provider,)
    result: dict[str, object] = {
        "fetched_at": datetime.now(timezone.utc).isoformat(),
        "architecture": architecture,
        "image": image,
        "requested_version": version,
        "providers": {},
    }
    providers = result["providers"]
    assert isinstance(providers, dict)
    for name in selected:
        if name == "temurin":
            providers[name] = temurin(version, image, architecture, timeout)
        elif name == "graalvm-community":
            if image != "jdk":
                raise ValueError("GraalVM Community solo publica JDK en este scraper")
            providers[name] = graalvm_community(version, architecture, timeout)
        elif name == "graalvm-oracle":
            if image != "jdk":
                raise ValueError("Oracle GraalVM solo publica JDK en este scraper")
            providers[name] = graalvm_oracle(version, architecture, timeout)
        elif name == "semeru":
            providers[name] = semeru(version, image, architecture, timeout)
    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--provider", choices=("all",) + PROVIDERS, default="all")
    parser.add_argument("--version", default="latest", help="latest, major (Temurin) o versión exacta")
    parser.add_argument("--image", choices=("jdk", "jre"), default="jdk")
    parser.add_argument(
        "--architecture",
        default=architecture_name(platform.machine()),
        help="x64 o aarch64",
    )
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        result = scrape(
            args.provider,
            args.version,
            args.image,
            architecture_name(args.architecture),
            args.timeout,
        )
    except (HTTPError, URLError, RuntimeError, ValueError, KeyError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    json.dump(result, sys.stdout, ensure_ascii=False, indent=2 if args.pretty else None)
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
