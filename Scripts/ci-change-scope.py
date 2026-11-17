#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
# Usage:
#   Scripts/ci-change-scope.py BASE HEAD
#     Prints documentation only when every changed path is a documentation file.
#   Scripts/ci-change-scope.py --has-application-changes [REMOTE] < updates
#     Exit 0 if any application file changed; exit 1 if only non-application files changed.

from __future__ import annotations

import subprocess
import sys

APPLICATION_PREFIXES = (
    b"Sources/",
    b"CardCore/",
    b"PKCS11Bridge/",
    b"Config/",
    b"RefineID.xcodeproj/",
    b"Tests/",
    b"Samples/",
)
APPLICATION_FILES = {
    b"RefineID.xctestplan",
    b"RefineIDUITests.xctestplan",
    b"Version.xcconfig",
    b"Package.swift",
}


def is_documentation(path: bytes) -> bool:
    if b"\n" in path or b"\r" in path:
        return False
    return path in {b"README.md", b"AGENTS.md", b"TASKS.md"} or (
        path.startswith(b"Documentation/") and path.endswith((b".md", b".bib"))
    )


def is_application(path: bytes) -> bool:
    if b"\n" in path or b"\r" in path:
        return True
    return (
        any(path.startswith(prefix) for prefix in APPLICATION_PREFIXES) or path in APPLICATION_FILES
    )


def push_ranges(
    updates_text: str,
    remote: str = "origin",
) -> list[tuple[str, str]] | None:
    ranges: list[tuple[str, str]] = []
    for line in updates_text.splitlines():
        fields = line.strip().split()
        if len(fields) != 4:
            continue
        _local_ref, local_sha, _remote_ref, old_sha = fields
        if set(local_sha) == {"0"}:
            continue
        if set(old_sha) == {"0"}:
            try:
                base = (
                    subprocess.check_output(
                        ["git", "merge-base", local_sha, f"refs/remotes/{remote}/main"],
                        stderr=subprocess.PIPE,
                    )
                    .decode()
                    .strip()
                )
            except subprocess.CalledProcessError:
                return None
        else:
            base = old_sha
        ranges.append((base, local_sha))
    return ranges


def has_application_changes_in_updates(
    updates_text: str,
    remote: str = "origin",
) -> bool:
    ranges = push_ranges(updates_text, remote)
    if ranges is None:
        return True
    if not ranges:
        return False
    for base, target in ranges:
        try:
            diff = subprocess.check_output(
                ["git", "diff", "--name-only", "--no-renames", "-z", base, target],
                stderr=subprocess.PIPE,
            ).split(b"\0")
            paths = [p for p in diff if p]
            if any(map(is_application, paths)):
                return True
        except subprocess.CalledProcessError:
            return True
    return False


def main() -> None:
    if len(sys.argv) >= 2 and sys.argv[1] == "--has-application-changes":
        remote = sys.argv[2] if len(sys.argv) > 2 else "origin"
        updates = sys.stdin.read()
        has_app = has_application_changes_in_updates(updates, remote)
        sys.exit(0 if has_app else 1)

    if len(sys.argv) != 3:
        raise SystemExit("Usage: Scripts/ci-change-scope.py BASE HEAD")
    paths = subprocess.check_output(
        ["git", "diff", "--name-only", "--no-renames", "-z", sys.argv[1], sys.argv[2]]
    ).split(b"\0")
    paths = [path for path in paths if path]
    print("documentation" if paths and all(map(is_documentation, paths)) else "code")


if __name__ == "__main__":
    main()
