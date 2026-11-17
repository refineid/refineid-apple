#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
# Usage: python3 Scripts/test-ci-change-scope.py
# Verifies that documentation filtering cannot classify source or CI as prose.

from __future__ import annotations

import contextlib
import importlib.util
import io
from pathlib import Path
from typing import Protocol, cast
import unittest
from unittest.mock import patch


class ScopeModule(Protocol):
    subprocess: object

    def is_documentation(self, path: bytes) -> bool: ...
    def is_application(self, path: bytes) -> bool: ...
    def has_application_changes_in_updates(
        self,
        updates_text: str,
        remote: str = "origin",
    ) -> bool: ...
    def main(self) -> None: ...


spec = importlib.util.spec_from_file_location(
    "scope",
    Path(__file__).with_name("ci-change-scope.py"),
)
if spec is None or spec.loader is None:
    raise RuntimeError("Could not load ci-change-scope.py")
raw_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(raw_module)
scope = cast(ScopeModule, raw_module)


class ChangeScopeTests(unittest.TestCase):
    def test_documentation_paths(self) -> None:
        for path in (
            b"TASKS.md",
            b"README.md",
            b"AGENTS.md",
            b"Documentation/release-plan.md",
            b"Documentation/references.bib",
        ):
            with self.subTest(path=path):
                self.assertTrue(scope.is_documentation(path))

    def test_executable_and_unknown_paths_require_full_checks(self) -> None:
        for path in (
            b"Sources/App.swift",
            b"Scripts/release.py",
            b".github/workflows/swift.yml",
            b"Documentation/tool.swift",
            b"Metadata/appstore.json",
            b"CardCore/README.md",
            b"Documentation/source.swift\nREADME.md",
        ):
            with self.subTest(path=path):
                self.assertFalse(scope.is_documentation(path))

    def test_complete_diff_classification(self) -> None:
        cases = (
            (b"TASKS.md\0Documentation/release-plan.md\0", "documentation"),
            (b"TASKS.md\0Sources/App.swift\0", "code"),
            (b"Sources/deleted.swift\0Documentation/new.md\0", "code"),
            (b"", "code"),
        )
        for paths, expected in cases:
            with self.subTest(expected=expected, paths=paths):
                output = io.StringIO()
                with (
                    patch("sys.argv", ["scope", "base", "head"]),
                    patch.object(scope.subprocess, "check_output", return_value=paths),
                    contextlib.redirect_stdout(output),
                ):
                    scope.main()
                self.assertEqual(output.getvalue().strip(), expected)

    def test_application_paths(self) -> None:
        for path in (
            b"Sources/App.swift",
            b"CardCore/Sources/CardCore/File.swift",
            b"PKCS11Bridge/Sources/Bridge.swift",
            b"Config/Features.xcconfig",
            b"RefineID.xcodeproj/project.pbxproj",
            b"Version.xcconfig",
            b"RefineID.xctestplan",
            b"Tests/RefineIDTests/Tests.swift",
        ):
            with self.subTest(path=path):
                self.assertTrue(scope.is_application(path))

    def test_non_application_paths(self) -> None:
        for path in (
            b"README.md",
            b"AGENTS.md",
            b"Metadata/appstore.json",
            b".gitignore",
            b".gitattributes",
            b"Scripts/check.py",
            b".github/workflows/swift.yml",
        ):
            with self.subTest(path=path):
                self.assertFalse(scope.is_application(path))

    def test_push_updates_has_application_changes(self) -> None:
        updates = "refs/heads/topic " + "1" * 40 + " refs/heads/topic " + "2" * 40 + "\n"
        with patch.object(
            scope.subprocess,
            "check_output",
            return_value=b"Sources/App.swift\0",
        ):
            self.assertTrue(scope.has_application_changes_in_updates(updates))

        with patch.object(
            scope.subprocess,
            "check_output",
            return_value=b"Metadata/appstore.json\0.gitignore\0",
        ):
            self.assertFalse(scope.has_application_changes_in_updates(updates))

    def test_cli_has_application_changes_flag(self) -> None:
        updates = "refs/heads/topic " + "1" * 40 + " refs/heads/topic " + "2" * 40 + "\n"
        with (
            patch("sys.argv", ["scope", "--has-application-changes", "origin"]),
            patch("sys.stdin", io.StringIO(updates)),
            patch.object(
                scope.subprocess,
                "check_output",
                return_value=b"Sources/App.swift\0",
            ),
        ):
            with self.assertRaises(SystemExit) as cm:
                scope.main()
            self.assertEqual(cm.exception.code, 0)

        with (
            patch("sys.argv", ["scope", "--has-application-changes", "origin"]),
            patch("sys.stdin", io.StringIO(updates)),
            patch.object(
                scope.subprocess,
                "check_output",
                return_value=b"Metadata/appstore.json\0",
            ),
        ):
            with self.assertRaises(SystemExit) as cm:
                scope.main()
            self.assertEqual(cm.exception.code, 1)


if __name__ == "__main__":
    unittest.main()
