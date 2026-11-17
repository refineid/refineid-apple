#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
"""Format Swift code in-place using swift-format according to .swift-format.

Usage:
    Scripts/format.py              # format all Swift source files in project
    Scripts/format.py --staged     # format only git-staged Swift files
    Scripts/format.py <files...>   # format specific files
"""

import subprocess
import sys
from pathlib import Path

DEFAULT_FORMAT_PATHS = [
    "Sources",
    "Tests",
    "Samples",
    "CardCore/Sources/CardCore",
    "CardCore/Sources/RappEngine",
    "CardCore/Tests",
    "CardCore/Package.swift",
    "PKCS11Bridge/Sources",
    "PKCS11Bridge/Tests",
    "PKCS11Bridge/Package.swift",
    "Scripts/PaceCurveBenchmark.swift",
]


def run_cmd(cmd, cwd=None, check=True):
    return subprocess.run(cmd, cwd=cwd, check=check, text=True)


def get_git_root() -> Path:
    res = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=True,
    )
    return Path(res.stdout.strip()).resolve()


def main():
    root = get_git_root()
    args = sys.argv[1:]

    if len(args) == 1 and args[0] in ("-h", "--help"):
        print(__doc__.strip())
        sys.exit(0)

    if len(args) == 1 and args[0] == "--staged":
        res = subprocess.run(
            ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"],
            cwd=root,
            capture_output=True,
            text=True,
            check=True,
        )
        staged = [
            line.strip()
            for line in res.stdout.splitlines()
            if line.strip().endswith(".swift") and (root / line.strip()).is_file()
        ]
        if staged:
            run_cmd(["swift", "format", "format", "--in-place", *staged], cwd=root)
            run_cmd(["git", "add", *staged], cwd=root)
            print(f"Formatted and re-staged {len(staged)} Swift file(s).")
        else:
            print("No staged Swift files to format.")
    elif len(args) > 0:
        run_cmd(["swift", "format", "format", "--in-place", *args], cwd=root)
        print(f"Formatted {len(args)} file(s).")
    else:
        existing = [p for p in DEFAULT_FORMAT_PATHS if (root / p).exists()]
        run_cmd(
            ["swift", "format", "format", "--in-place", "--recursive", *existing],
            cwd=root,
        )
        print("Formatted all project Swift sources.")


if __name__ == "__main__":
    main()
