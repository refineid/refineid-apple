#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
"""Check the unit/UI test-framework boundary.

Usage: python3 Scripts/CheckTestFrameworks.py

Unit and integration tests use Swift Testing. XCTest and XCUIAutomation belong only to
RefineIDUITests, where XCUIAutomation and XCTest-only APIs require them.
"""

from pathlib import Path
import re
import sys

SUCCESS_EXIT_STATUS = 0
FAILURE_EXIT_STATUS = 1
TEST_ROOTS = ("Tests", "CardCore/Tests", "PKCS11Bridge/Tests")
UI_TEST_ROOT = Path("Tests/RefineIDUITests")
RESTRICTED_TEST_IMPORT = re.compile(
    r"\bimport\s+(?:(?:class|struct|enum|protocol|typealias|func|var|let)\s+)?(?:XCTest|XCUIAutomation)\b"
)
SWIFT_TRIVIA = re.compile(r'//[^\n]*|/\*|(?P<hashes>#+)?(?P<quote>"""|")')
BLOCK_COMMENT_BOUNDARY = re.compile(r"/\*|\*/")
NO_NESTING = 0
NESTING_STEP = 1
ESCAPE_PAIR_SIZE = 2
ONE_ESCAPE = 1
START_OF_SOURCE = 0


def executable_source(source: str) -> str:
    """Remove comments and string bodies before examining import declarations."""
    output = []
    cursor = START_OF_SOURCE
    while match := SWIFT_TRIVIA.search(source, cursor):
        output.append(source[cursor : match.start()])
        end = match.end()
        if match.group() == "/*":
            nesting = NESTING_STEP
            for boundary in BLOCK_COMMENT_BOUNDARY.finditer(source, end):
                nesting += NESTING_STEP if boundary.group() == "/*" else -NESTING_STEP
                end = boundary.end()
                if nesting == NO_NESTING:
                    break
            else:
                end = len(source)
        elif match.group("quote") is not None:
            hashes = match.group("hashes") or ""
            closing = match.group("quote") + hashes
            while True:
                closing_start = source.find(closing, end)
                if closing_start < START_OF_SOURCE:
                    end = len(source)
                    break
                prefix = source[:closing_start]
                if hashes:
                    escaped = prefix.endswith("\\" + hashes)
                else:
                    escaped = (
                        len(prefix) - len(prefix.rstrip("\\"))
                    ) % ESCAPE_PAIR_SIZE == ONE_ESCAPE
                end = closing_start + len(closing)
                if not escaped:
                    break
        output.append(" " + "\n" * source[match.start() : end].count("\n"))
        cursor = end
    output.append(source[cursor:])
    return "".join(output)


def violations(root: Path) -> tuple[Path, ...]:
    offenders = []
    for test_root in TEST_ROOTS:
        for file in (root / test_root).rglob("*.swift"):
            relative = file.relative_to(root)
            if relative.is_relative_to(UI_TEST_ROOT):
                continue
            if RESTRICTED_TEST_IMPORT.search(executable_source(file.read_text(encoding="utf-8"))):
                offenders.append(relative)
    return tuple(sorted(offenders))


def main(root: Path) -> int:
    offenders = violations(root)
    for file in offenders:
        print(
            f"{file}: ordinary tests must use Swift Testing. "
            "Use XCTest for UI automation in RefineIDUITests.",
            file=sys.stderr,
        )
    return FAILURE_EXIT_STATUS if offenders else SUCCESS_EXIT_STATUS


if __name__ == "__main__":
    raise SystemExit(main(Path(__file__).resolve().parent.parent))
