#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
"""The lint gate, and the only SwiftLint invocation the pre-commit and pre-push hooks run.

Usage:
    Scripts/lint.py [check|regenerate-register]

Gate:
    - swift-format owns Swift layout
    - SwiftLint owns Swift defects (strict, baseline)
    - ruff format owns Python layout
    - ruff check and mypy --strict own Python defects and static typing
    - swiftc typechecks standalone scripts under Scripts/ with -warnings-as-errors
    - suppression comments must match Scripts/lint-suppression-register.json exactly
"""

from __future__ import annotations

from collections import Counter
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from typing import NoReturn

FORMAT_PATHS = [
    "Sources",
    "Tests",
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

TYPECHECK_TARGETS: list[tuple[str, list[str]]] = [
    ("release manager", ["Scripts/apple-app-store-connect-release-manager.swift"]),
    ("release manager tests", ["Scripts/TestAppleAppStoreConnectReleaseManager.swift"]),
    ("macOS notarized DMG builder", ["Scripts/macos-notarized-dmg-builder.swift"]),
    ("macOS notarized DMG builder tests", ["Scripts/TestMacosNotarizedDmgBuilder.swift"]),
    ("store screenshots", ["Scripts/generate-store-screenshots.swift"]),
    ("card logins", ["Scripts/test-card-logins.swift"]),
    ("icon", ["Scripts/generate-icon.swift"]),
    ("slack icon", ["Scripts/generate-slack-icon.swift"]),
    (
        "stamp samples",
        [
            "CardCore/Sources/CardCore/PdfStampRenderer.swift",
            "CardCore/Sources/CardCore/StampMark.swift",
            "CardCore/Sources/CardCore/Values/PdfValues.swift",
            "Scripts/RenderStampSamples.swift",
        ],
    ),
    (
        "PACE curve benchmark",
        [
            "CardCore/Sources/CardCore/Crypto/U384.swift",
            "CardCore/Sources/CardCore/Crypto/MontgomeryDomain.swift",
            "CardCore/Sources/CardCore/Crypto/CurveFieldElement.swift",
            "CardCore/Sources/CardCore/Crypto/CurvePoint.swift",
            "CardCore/Sources/CardCore/Crypto/CurveDomainParameters.swift",
            "CardCore/Sources/CardCore/Crypto/PaceCurve.swift",
            "CardCore/Sources/CardCore/Crypto/JacobianPoint.swift",
            "CardCore/Sources/CardCore/Crypto/BrainpoolP384r1.swift",
            "CardCore/Sources/CardCore/Crypto/NistP384.swift",
            "CardCore/Sources/CardCore/Crypto/NistP256.swift",
            "CardCore/Sources/CardCore/Values/BrainpoolP384r1Values.swift",
            "CardCore/Sources/CardCore/Values/NistP256Values.swift",
            "CardCore/Sources/CardCore/Values/NistP384Values.swift",
            "CardCore/Sources/CardCore/Values/Sec1Values.swift",
            "Scripts/PaceCurveBenchmark.swift",
        ],
    ),
]


def fail(name: str, log: str = "") -> NoReturn:
    print(f"lint FAIL: {name}", file=sys.stderr)
    if log:
        print(log.strip(), file=sys.stderr)
    sys.exit(1)


def get_repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def check_swift_format(root: Path) -> None:
    paths = [p for p in FORMAT_PATHS if (root / p).exists()]
    res = subprocess.run(
        ["swift", "format", "lint", "--strict", "--recursive", *paths],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    if res.returncode != 0:
        fail("swift-format", res.stdout + res.stderr)


def check_swiftlint(root: Path) -> None:
    baseline = root / ".swiftlint-baseline.json"
    cmd = ["swiftlint", "lint", "--quiet"]
    if baseline.is_file():
        cmd.extend(["--baseline", ".swiftlint-baseline.json"])
    res = subprocess.run(cmd, cwd=root, capture_output=True, text=True, check=False)
    if res.returncode != 0:
        fail("swiftlint", res.stdout + res.stderr)


def check_python_scripts(root: Path) -> None:
    for name, cmd in (
        ("ruff format", ["ruff", "format", "--no-cache", "--check", "Scripts"]),
        ("ruff check", ["ruff", "check", "--no-cache", "Scripts"]),
        (
            "mypy",
            [
                "mypy",
                "--strict",
                "--no-incremental",
                "--explicit-package-bases",
                "Scripts",
            ],
        ),
    ):
        res = subprocess.run(cmd, cwd=root, capture_output=True, text=True, check=False)
        if res.returncode != 0:
            fail(name, res.stdout + res.stderr)


def check_script_typechecks(root: Path) -> None:
    sdk_res = subprocess.run(
        ["xcrun", "--show-sdk-path", "--sdk", "macosx"],
        capture_output=True,
        text=True,
        check=True,
    )
    macos_sdk = sdk_res.stdout.strip()
    typechecked_scripts: set[str] = set()

    for name, files in TYPECHECK_TARGETS:
        for f in files:
            if f.startswith("Scripts/"):
                typechecked_scripts.add(f)
        cmd = ["swiftc", "-typecheck", "-warnings-as-errors", "-sdk", macos_sdk, *files]
        res = subprocess.run(cmd, cwd=root, capture_output=True, text=True, check=False)
        if res.returncode != 0:
            fail(f"typecheck {name}", res.stdout + res.stderr)

    all_scripts = {p.relative_to(root).as_posix() for p in (root / "Scripts").glob("*.swift")}
    untypechecked = sorted(all_scripts - typechecked_scripts)
    if untypechecked:
        fail(
            "typecheck",
            "not typechecked (add a typecheck call to Scripts/lint.py):\n"
            + "\n".join(untypechecked),
        )


def check_suppression_locks(root: Path, mode: str) -> None:
    register_path = root / "Scripts/lint-suppression-register.json"
    if mode == "check" and not register_path.is_file():
        fail(
            "lint locks",
            f"missing {register_path}; print a reviewed replacement with: "
            "Scripts/lint.py regenerate-register",
        )

    register: dict[str, list[dict[str, object]]] = {
        "swiftlint": [],
        "swift_format_ignore": [],
    }
    if mode == "check":
        loaded = json.loads(register_path.read_text(encoding="utf-8"))
        if isinstance(loaded, dict):
            register = loaded

    files: set[Path] = set()
    for raw in FORMAT_PATHS:
        target = root / raw
        if target.is_file() and target.suffix == ".swift":
            files.add(target)
        elif target.is_dir():
            files.update(target.rglob("*.swift"))
    sorted_files = sorted(files)

    disable_re = re.compile(
        r"swiftlint:(disable(?::(?:next|this|previous))?|enable)\s+([^\n]+?)\s*$",
        re.MULTILINE,
    )
    fmt_re = re.compile(
        r"^[ \t]*//[ \t]*swift-format-ignore(?:-file)?(?::\s*([^\n]+))?\s*$",
        re.MULTILINE,
    )

    actual_lint: Counter[tuple[str, str, tuple[str, ...]]] = Counter()
    actual_fmt: Counter[tuple[str, str]] = Counter()
    for path in sorted_files:
        rel = path.relative_to(root).as_posix()
        text = path.read_text(encoding="utf-8")
        for match in disable_re.finditer(text):
            command = match.group(1)
            rules = tuple(sorted(match.group(2).split()))
            actual_lint[(rel, command, rules)] += 1
        for match in fmt_re.finditer(text):
            rule = (match.group(1) or "").strip()
            actual_fmt[(rel, rule)] += 1

    expected_lint: Counter[tuple[str, str, tuple[str, ...]]] = Counter()
    for entry in register.get("swiftlint", []):
        raw_rules = entry.get("rules")
        rules_tuple = tuple(str(r) for r in raw_rules) if isinstance(raw_rules, list) else ()
        raw_count = entry.get("count", 0)
        count = int(raw_count) if isinstance(raw_count, int) else 0
        expected_lint[(str(entry["file"]), str(entry["command"]), rules_tuple)] += count

    expected_fmt: Counter[tuple[str, str]] = Counter()
    for entry in register.get("swift_format_ignore", []):
        raw_count = entry.get("count", 0)
        count = int(raw_count) if isinstance(raw_count, int) else 0
        expected_fmt[(str(entry["file"]), str(entry["rule"]))] += count

    if mode == "regenerate-register":
        output = {
            "swiftlint": [
                {
                    "file": key[0],
                    "command": key[1],
                    "rules": list(key[2]),
                    "count": count,
                }
                for key, count in sorted(actual_lint.items())
            ],
            "swift_format_ignore": [
                {"file": key[0], "rule": key[1], "count": count}
                for key, count in sorted(actual_fmt.items())
            ],
        }
        print(json.dumps(output, indent=2, sort_keys=False))
        return

    def report_mismatch[T](
        label: str,
        actual: Counter[T],
        expected: Counter[T],
    ) -> bool:
        extra = actual - expected
        missing = expected - actual
        if not extra and not missing:
            return False
        sys.stderr.write(
            f"lint lock FAIL: {label} does not match Scripts/lint-suppression-register.json\n"
        )
        for key, count in sorted(extra.items(), key=lambda item: str(item[0])):
            sys.stderr.write(f"  extra x{count}: {key}\n")
        for key, count in sorted(missing.items(), key=lambda item: str(item[0])):
            sys.stderr.write(f"  missing x{count}: {key}\n")
        return True

    failed_lock = False
    if report_mismatch("swiftlint suppression", actual_lint, expected_lint):
        failed_lock = True
    if report_mismatch("swift-format-ignore", actual_fmt, expected_fmt):
        failed_lock = True

    if failed_lock:
        fail(
            "lint locks",
            "Fix the finding, or change the register in the same commit. "
            "Do not add a suppression without removing one from the register.",
        )


def main() -> None:
    mode = "check"
    if len(sys.argv) > 1:
        if sys.argv[1] in ("check", "regenerate-register"):
            mode = sys.argv[1]
        else:
            print(
                "usage: Scripts/lint.py [check|regenerate-register]",
                file=sys.stderr,
            )
            sys.exit(2)

    root = get_repo_root()
    os.chdir(root)
    if mode == "regenerate-register":
        check_suppression_locks(root, mode)
        return

    check_swift_format(root)
    check_swiftlint(root)
    check_python_scripts(root)
    check_script_typechecks(root)
    check_suppression_locks(root, mode)


if __name__ == "__main__":
    main()
