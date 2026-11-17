#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
# Usage: Scripts/render-stamp-samples.py [output-directory] [rotation-degrees]
# Render production PDF stamp operators with Apple's PDFKit into EN/FI/SV PNGs.

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    os.chdir(repo_root)

    output = Path(sys.argv[1]).expanduser() if len(sys.argv) > 1 else Path.home() / "Desktop"
    output.mkdir(parents=True, exist_ok=True)

    tmp_pdfs = repo_root / "build" / "stamp-samples"
    tmp_pdfs.mkdir(parents=True, exist_ok=True)
    (repo_root / "build" / ".metadata_never_index").touch(exist_ok=True)

    binary = tmp_pdfs / "render-stamps"

    swift_sources = [
        "CardCore/Sources/CardCore/PdfStampRenderer.swift",
        "CardCore/Sources/CardCore/StampMark.swift",
        "CardCore/Sources/CardCore/Values/PdfValues.swift",
        "Scripts/RenderStampSamples.swift",
    ]

    compile_cmd = ["swiftc", *swift_sources, "-o", str(binary)]
    subprocess.run(compile_cmd, check=True)

    extra_args = sys.argv[2:]
    run_cmd = [str(binary), str(tmp_pdfs), *extra_args]
    subprocess.run(run_cmd, check=True)

    for png in tmp_pdfs.glob("signature-stamp-*-tilted.png"):
        shutil.copy2(png, output / png.name)


if __name__ == "__main__":
    main()
