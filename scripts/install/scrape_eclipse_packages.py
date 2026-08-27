#!/usr/bin/env python3
"""Extract current official Eclipse IDE package downloads.

This scraper deliberately uses only the Eclipse Foundation package page and
its checksum endpoint. It emits JSON so the installer can consume the result
without depending on fragile shell parsing or third-party Python packages.
"""

from __future__ import annotations

import argparse
import html
import json
import platform
import re
import sys
from datetime import datetime, timezone
from html.parser import HTMLParser
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urljoin, urlparse
from urllib.request import Request, urlopen


PACKAGES = {
    "java": "Eclipse IDE for Java Developers",
    "jee": "Eclipse IDE for Enterprise Java and Web Developers",
}
PACKAGES_URL = "https://www.eclipse.org/downloads/packages/"
DOWNLOAD_BASE = "https://www.eclipse.org/downloads/"
CHECKSUM_ENDPOINT = "https://www.eclipse.org/downloads/sums.php"
USER_AGENT = "rafex-eclipse-package-scraper/1.0"


def read_url(url: str, timeout: int) -> str:
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=timeout) as response:  # noqa: S310 - HTTPS URLs are checked below.
        final_url = response.geturl()
        if urlparse(final_url).scheme != "https":
            raise RuntimeError(f"redirección insegura de Eclipse: {final_url}")
        return response.read().decode("utf-8", errors="strict")


class PackagePageParser(HTMLParser):
    """Parse package cards and their Linux architecture links."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.packages: list[dict[str, object]] = []
        self.current: dict[str, object] | None = None
        self.in_title = False
        self.title_parts: list[str] = []
        self.title_href = ""
        self.os_name_depth = 0
        self.current_os = ""
        self.current_link: dict[str, str] | None = None

    @staticmethod
    def _classes(attrs: list[tuple[str, str | None]]) -> set[str]:
        return set((dict(attrs).get("class") or "").split())

    def _finish_current(self) -> None:
        if self.current is not None:
            self.packages.append(self.current)
        self.current = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        classes = self._classes(attrs)

        if tag == "h3" and "package-title" in classes:
            self._finish_current()
            self.current = {"name": "", "package_href": "", "linux_links": []}
            self.current_os = ""
            self.in_title = True
            self.title_parts = []
            self.title_href = ""
        elif tag == "a" and self.in_title:
            self.title_href = attributes.get("href") or ""
        elif tag == "div" and "downloads-item-os-name" in classes:
            self.os_name_depth = 1
            self.current_os = ""
        elif tag == "a" and self.current is not None and self.current_os == "Linux":
            self.current_link = {"href": attributes.get("href") or "", "text": ""}

    def handle_data(self, data: str) -> None:
        text = " ".join(data.split())
        if not text:
            return
        if self.in_title:
            self.title_parts.append(text)
        if self.os_name_depth:
            self.current_os = f"{self.current_os} {text}".strip()
        if self.current_link is not None:
            self.current_link["text"] += f" {text}"

    def handle_endtag(self, tag: str) -> None:
        if tag == "a" and self.current_link is not None:
            if self.current is not None:
                links = self.current["linux_links"]
                assert isinstance(links, list)
                links.append(
                    {
                        "href": self.current_link["href"],
                        "text": self.current_link["text"].strip(),
                    }
                )
            self.current_link = None
        elif tag == "h3" and self.in_title:
            if self.current is not None:
                self.current["name"] = " ".join(self.title_parts).strip()
                self.current["package_href"] = self.title_href
            self.in_title = False
        elif tag == "div" and self.os_name_depth:
            self.os_name_depth = 0

    def close(self) -> None:
        super().close()
        self._finish_current()


def architecture_name(value: str) -> str:
    normalized = value.lower()
    aliases = {
        "x86_64": "x86_64",
        "amd64": "x86_64",
        "aarch64": "aarch64",
        "arm64": "aarch64",
        "riscv64": "riscv64",
    }
    try:
        return aliases[normalized]
    except KeyError as exc:
        raise ValueError(f"arquitectura no soportada: {value}") from exc


def file_path_from_href(href: str) -> str:
    query = parse_qs(urlparse(href).query)
    values = query.get("file", [])
    if not values or not values[0].startswith("/"):
        raise RuntimeError(f"enlace Eclipse sin parámetro file válido: {href}")
    return values[0]


def release_from_path(file_path: str) -> str:
    match = re.search(r"/release/([^/]+)/([^/]+)/", file_path)
    if not match:
        return "unknown"
    return f"{match.group(1)}-{match.group(2).upper()}"


def checksum_for(file_path: str, timeout: int) -> tuple[str, str]:
    query = urlencode({"file": file_path, "type": "sha512"})
    checksum_url = f"{CHECKSUM_ENDPOINT}?{query}"
    response = read_url(checksum_url, timeout)
    match = re.search(r"\b([0-9a-fA-F]{128})\b", response)
    if not match:
        raise RuntimeError(f"Eclipse no publicó un SHA-512 para {file_path}")
    return match.group(1).lower(), checksum_url


def extract_package(
    parsed_packages: list[dict[str, object]],
    package_key: str,
    architecture: str,
    timeout: int,
) -> dict[str, object]:
    wanted_name = PACKAGES[package_key]
    package = next(
        (item for item in parsed_packages if item.get("name") == wanted_name),
        None,
    )
    if package is None:
        raise RuntimeError(f"no se encontró el paquete oficial: {wanted_name}")

    links = package.get("linux_links", [])
    assert isinstance(links, list)
    expected_marker = f"linux-gtk-{architecture}.tar.gz"
    selected = next(
        (link for link in links if expected_marker in str(link.get("href", ""))),
        None,
    )
    if selected is None:
        raise RuntimeError(
            f"no se encontró descarga Linux {architecture} para {wanted_name}"
        )

    href = str(selected["href"])
    page_url = urljoin(PACKAGES_URL, href)
    if urlparse(page_url).hostname != "www.eclipse.org":
        raise RuntimeError(f"enlace de descarga fuera de Eclipse: {page_url}")
    file_path = file_path_from_href(href)
    filename = file_path.rsplit("/", 1)[-1]
    checksum, checksum_url = checksum_for(file_path, timeout)
    separator = "&" if "?" in page_url else "?"
    direct_url = f"{page_url}{separator}r=1"

    return {
        "key": package_key,
        "name": wanted_name,
        "release": release_from_path(file_path),
        "architecture": architecture,
        "filename": filename,
        "file_path": file_path,
        "package_page": urljoin(PACKAGES_URL, str(package["package_href"])),
        "download_page": page_url,
        "direct_url": direct_url,
        "checksum_algorithm": "sha512",
        "checksum": checksum,
        "checksum_url": checksum_url,
    }


def scrape(package_key: str, architecture: str, timeout: int) -> dict[str, object]:
    page = read_url(PACKAGES_URL, timeout)
    parser = PackagePageParser()
    parser.feed(page)
    parser.close()
    selected_keys = list(PACKAGES) if package_key == "all" else [package_key]
    packages = {
        key: extract_package(parser.packages, key, architecture, timeout)
        for key in selected_keys
    }
    return {
        "source_url": PACKAGES_URL,
        "fetched_at": datetime.now(timezone.utc).isoformat(),
        "architecture": architecture,
        "packages": packages,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--package",
        choices=["java", "jee", "all"],
        default="all",
        help="paquete a extraer (default: all)",
    )
    parser.add_argument(
        "--architecture",
        default=architecture_name(platform.machine()),
        help="arquitectura Eclipse: x86_64, aarch64 o riscv64",
    )
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--pretty", action="store_true", help="JSON indentado")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        architecture = architecture_name(args.architecture)
        result = scrape(args.package, architecture, args.timeout)
    except (HTTPError, URLError, RuntimeError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    json.dump(result, sys.stdout, ensure_ascii=False, indent=2 if args.pretty else None)
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
