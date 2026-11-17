#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
"""Format Swift and Python code in-place using swift-format and ruff.

Usage:
    Scripts/format.py              # format all Swift and Python source files in project
    Scripts/format.py --staged     # format only git-staged Swift and Python files
    Scripts/format.py <files...>   # format specific files
"""

from __future__ import annotations

from pathlib import Path
import subprocess
import sys

DEFAULT_FORMAT_PATHS = [
    "Sources",
    "Tests",
    "Samples",
    "CardCore/Sources/CardCore",
    "CardCore/Sources/RappEngine",
    "CardCore/Sources/RappRequester",
    "CardCore/Tests",
    "CardCore/Package.swift",
    "PKCS11Bridge/Sources",
    "PKCS11Bridge/Tests",
    "PKCS11Bridge/Package.swift",
    "Scripts/PaceCurveBenchmark.swift",
]


def run_cmd(
    cmd: list[str],
    cwd: Path | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, check=check, text=True)


def get_git_root() -> Path:
    res = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=True,
    )
    return Path(res.stdout.strip()).resolve()


def main() -> None:
    root = get_git_root()
    args = sys.argv[1:]

    if len(args) == 1 and args[0] in ("-h", "--help"):
        print((__doc__ or "").strip())
        sys.exit(0)

    if len(args) == 1 and args[0] == "--staged":
        res = subprocess.run(
            ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"],
            cwd=root,
            capture_output=True,
            text=True,
            check=True,
        )
        staged_swift = [
            line.strip()
            for line in res.stdout.splitlines()
            if line.strip().endswith(".swift") and (root / line.strip()).is_file()
        ]
        staged_py = [
            line.strip()
            for line in res.stdout.splitlines()
            if line.strip().endswith(".py") and (root / line.strip()).is_file()
        ]
        if staged_swift:
            run_cmd(["swift", "format", "format", "--in-place", *staged_swift], cwd=root)
            run_cmd(["git", "add", *staged_swift], cwd=root)
        if staged_py:
            run_cmd(["ruff", "format", "--no-cache", *staged_py], cwd=root)
            run_cmd(["git", "add", *staged_py], cwd=root)
        total = len(staged_swift) + len(staged_py)
        if total:
            print(f"Formatted and re-staged {total} file(s).")
        else:
            print("No staged Swift or Python files to format.")
    elif len(args) > 0:
        swift_args = [arg for arg in args if arg.endswith(".swift")]
        py_args = [arg for arg in args if arg.endswith(".py")]
        if swift_args:
            run_cmd(["swift", "format", "format", "--in-place", *swift_args], cwd=root)
        if py_args:
            run_cmd(["ruff", "format", "--no-cache", *py_args], cwd=root)
        print(f"Formatted {len(args)} file(s).")
    else:
        existing = [p for p in DEFAULT_FORMAT_PATHS if (root / p).exists()]
        run_cmd(
            ["swift", "format", "format", "--in-place", "--recursive", *existing],
            cwd=root,
        )
        run_cmd(["ruff", "format", "--no-cache", "Scripts"], cwd=root)
        print("Formatted all project Swift and Python sources.")


if __name__ == "__main__":
    main()
