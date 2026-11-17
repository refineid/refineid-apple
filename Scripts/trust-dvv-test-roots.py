#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Makes this Mac trust DVV's test certificate chain, or stops trusting it,
# so Safari offers a DVV test card's identity for TLS client authentication.
#
# Safari offers a smart-card identity only when its chain evaluates to a
# trusted anchor; without one it answers the server's certificate request
# with no certificate and shows no picker. Production DVV cards chain to
# the DVV Gov. Root CA G3 roots; DVV test cards (personal and organisation)
# chain to DVV TEST Root CA G3 RSA or ECC instead.
#
# install: nothing is taken from this repository. Each certificate is
# downloaded from DVV's CA distribution point and accepted only when its
# SHA-256 equals the one DVV publishes on its test CA page, fetched over
# HTTPS. The roots are added to the System keychain as trusted roots and
# the test issuing CAs as plain certificates.
#
# uninstall: removes the roots' trust settings and deletes the four
# certificates from the System keychain, found by name.
#
# Usage: Scripts/trust-dvv-test-roots.py install|uninstall
#        (asks for the admin password)

from __future__ import annotations

import hashlib
import html
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import urllib.request

CA_BASE = "http://proxy.fineid.fi/ca"
PAGE_URL = "https://dvv.fi/en/test-ca-certificates"
KEYCHAIN = "/Library/Keychains/System.keychain"

ROOTS = [
    ("dvvtest3rc", "DVV TEST Root CA - G3 RSA"),
    ("dvvtest3ec", "DVV TEST Root CA - G3 ECC"),
]

INTERMEDIATES = [
    ("dvvtp5rc", "DVV TEST Certificates - G5R"),
    ("dvvtp5ec", "DVV TEST Certificates - G5E"),
]


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    sys.exit(1)


def sha256_of_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fetch_page_text() -> str:
    req = urllib.request.Request(PAGE_URL, headers={"User-Agent": "curl/8.7.1"})
    try:
        with urllib.request.urlopen(req) as response:
            html_content = response.read().decode("utf-8", errors="replace")
    except Exception as e:
        fail(f"Failed to fetch DVV test CA page: {e}")

    text = html.unescape(re.sub(r"<[^>]+>", " ", html_content))
    return re.sub(r"\s+", " ", text)


def published_sha256(page_text: str, name: str) -> str:
    pattern = re.escape(name) + r" ([0-9a-f]{64})\b"
    match = re.search(pattern, page_text, re.IGNORECASE)
    return match.group(1).lower() if match else ""


def install() -> None:
    page_text = fetch_page_text()

    with tempfile.TemporaryDirectory(prefix="dvv-roots-") as tmpdir:
        tmp_path = Path(tmpdir)
        downloaded: dict[str, Path] = {}

        for file_stem, name in ROOTS + INTERMEDIATES:
            expected = published_sha256(page_text, name)
            if not expected:
                fail(f'DVV\'s test CA page lists no SHA-256 for "{name}"; nothing installed.')

            url = f"{CA_BASE}/{file_stem}.crt"
            try:
                with urllib.request.urlopen(url) as resp:
                    cert_bytes = resp.read()
            except Exception as e:
                fail(f'Failed to download "{name}" from {url}: {e}')

            actual = sha256_of_bytes(cert_bytes)
            if actual != expected:
                fail(
                    f'"{name}" from {url} does not match DVV\'s published SHA-256; nothing installed.'
                )

            dest = tmp_path / f"{file_stem}.der"
            dest.write_bytes(cert_bytes)
            downloaded[file_stem] = dest

        for file_stem, name in ROOTS:
            cert_file = downloaded[file_stem]
            cmd = [
                "sudo",
                "security",
                "add-trusted-cert",
                "-d",
                "-r",
                "trustRoot",
                "-k",
                KEYCHAIN,
                str(cert_file),
            ]
            subprocess.run(cmd, check=True)

        for file_stem, name in INTERMEDIATES:
            cert_file = downloaded[file_stem]
            cmd = ["sudo", "security", "add-certificates", "-k", KEYCHAIN, str(cert_file)]
            res = subprocess.run(cmd, capture_output=True, check=False)
            if res.returncode != 0:
                print(f"{name} is already in the System keychain.")

        print("DVV test roots trusted; DVV TEST Certificates G5R and G5E added.")


def remove_named(name: str, is_root: bool, tmp_path: Path) -> None:
    res = subprocess.run(
        ["security", "find-certificate", "-a", "-c", name, "-Z", KEYCHAIN],
        capture_output=True,
        text=True,
        check=False,
    )
    if res.returncode != 0 or not res.stdout:
        print(f"{name} is not in the System keychain.")
        return

    hashes = [
        line.split()[2]
        for line in res.stdout.splitlines()
        if line.startswith("SHA-1 hash:") and len(line.split()) >= 3
    ]
    if not hashes:
        print(f"{name} is not in the System keychain.")
        return

    if is_root:
        pem_res = subprocess.run(
            ["security", "find-certificate", "-a", "-c", name, "-Z", "-p", KEYCHAIN],
            capture_output=True,
            text=True,
            check=False,
        )
        if pem_res.returncode == 0:
            blocks = pem_res.stdout.split("SHA-1 hash:")
            for block in blocks[1:]:
                lines = block.splitlines()
                block_hash = lines[0].strip()
                pem_lines = [l for l in lines[1:] if not l.startswith("SHA")]
                pem_text = "\n".join(pem_lines).strip() + "\n"
                root_pem = tmp_path / f"root-{block_hash}.pem"
                root_pem.write_text(pem_text, encoding="utf-8")
                subprocess.run(
                    ["sudo", "security", "remove-trusted-cert", "-d", str(root_pem)],
                    capture_output=True,
                    check=False,
                )

    for h in hashes:
        subprocess.run(
            ["sudo", "security", "delete-certificate", "-Z", h, KEYCHAIN],
            check=False,
        )
    print(f"{name} removed.")


def uninstall() -> None:
    with tempfile.TemporaryDirectory(prefix="dvv-uninstall-") as tmpdir:
        tmp_path = Path(tmpdir)
        for _, name in ROOTS:
            remove_named(name, is_root=True, tmp_path=tmp_path)
        for _, name in INTERMEDIATES:
            remove_named(name, is_root=False, tmp_path=tmp_path)


def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] not in ("install", "uninstall"):
        print(f"Usage: {sys.argv[0]} install|uninstall", file=sys.stderr)
        sys.exit(2)

    if sys.argv[1] == "install":
        install()
    elif sys.argv[1] == "uninstall":
        uninstall()


if __name__ == "__main__":
    main()
