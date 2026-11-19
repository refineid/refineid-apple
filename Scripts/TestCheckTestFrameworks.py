#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
"""Usage: python3 -B Scripts/TestCheckTestFrameworks.py. Uses isolated source fixtures."""

from pathlib import Path
import tempfile
import unittest

import CheckTestFrameworks as policy


class FrameworkPolicyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory(prefix="test-frameworks-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def source(self, path: str, contents: str) -> None:
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(contents, encoding="ascii")

    def test_accepts_swift_testing_and_ui_automation(self) -> None:
        self.source("Tests/RefineIDTests/Unit.swift", "import Testing\n")
        self.source("Tests/RefineIDUITests/UI.swift", "import XCTest\n")
        self.source("CardCore/Tests/Unit.swift", "import Testing\n")
        self.source("PKCS11Bridge/Tests/Unit.swift", "import Testing\n")
        self.assertFalse(policy.violations(self.root))

    def test_rejects_xctest_in_every_ordinary_test_root(self) -> None:
        paths = (
            "Tests/RefineIDTests/Unit.swift",
            "Tests/CardCoreTests/Unit.swift",
            "CardCore/Tests/Unit.swift",
            "PKCS11Bridge/Tests/Unit.swift",
        )
        for path in paths:
            self.source(path, "@preconcurrency import XCTest\n")
        self.assertEqual(set(policy.violations(self.root)), {Path(path) for path in paths})

    def test_rejects_scoped_import(self) -> None:
        path = "Tests/RefineIDTests/Unit.swift"
        self.source(path, "import class XCTest.XCTestCase\n")
        self.assertEqual(policy.violations(self.root), (Path(path),))

    def test_ignores_comments_and_string_examples(self) -> None:
        examples = (
            "// import XCTest\n",
            "/* outer /* nested */ import XCTest */\n",
            '"import XCTest"\n',
            '"""\nimport XCTest\n"""\n',
            '#"import XCTest"#\n',
        )
        for example in examples:
            with self.subTest(example=example):
                self.source("Tests/RefineIDTests/Unit.swift", example + "import Testing\n")
                self.assertFalse(policy.violations(self.root))

    def test_rejects_access_modified_and_same_line_imports(self) -> None:
        for statement in ("public import XCTest", "import Foundation; import XCTest"):
            with self.subTest(statement=statement):
                self.source("Tests/RefineIDTests/Unit.swift", statement)
                self.assertTrue(policy.violations(self.root))

    def test_ui_automation_import_is_restricted_to_ui_target(self) -> None:
        self.source("Tests/RefineIDUITests/UI.swift", "import XCUIAutomation\n")
        self.assertFalse(policy.violations(self.root))
        self.source("Tests/RefineIDTests/Unit.swift", "import XCUIAutomation\n")
        self.assertTrue(policy.violations(self.root))

    def test_does_not_scan_non_test_sources_or_similar_directory_names(self) -> None:
        self.source("Sources/Example.swift", "import XCTest\n")
        path = "Tests/RefineIDUITestsOther/Unit.swift"
        self.source(path, "import XCTest\n")
        self.assertEqual(policy.violations(self.root), (Path(path),))


if __name__ == "__main__":
    unittest.main()
