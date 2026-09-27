#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
# Usage: python3 Scripts/test-ci-change-scope.py
# Verifies that documentation filtering cannot classify source or CI as prose.

import contextlib
import importlib.util
import io
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    'scope', Path(__file__).with_name('ci-change-scope.py')
)
scope = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scope)


class ChangeScopeTests(unittest.TestCase):
    def test_documentation_paths(self):
        for path in (b'TASKS.md', b'README.md', b'AGENTS.md',
                     b'Documentation/release-plan.md', b'Documentation/references.bib'):
            with self.subTest(path=path):
                self.assertTrue(scope.is_documentation(path))

    def test_executable_and_unknown_paths_require_full_checks(self):
        for path in (b'Sources/App.swift', b'Scripts/release.sh',
                     b'.github/workflows/swift.yml', b'Documentation/tool.swift',
                     b'Metadata/appstore.json', b'CardCore/README.md',
                     b'Documentation/source.swift\nREADME.md'):
            with self.subTest(path=path):
                self.assertFalse(scope.is_documentation(path))

    def test_complete_diff_classification(self):
        cases = (
            (b'TASKS.md\0Documentation/release-plan.md\0', 'documentation'),
            (b'TASKS.md\0Sources/App.swift\0', 'code'),
            (b'Sources/deleted.swift\0Documentation/new.md\0', 'code'),
            (b'', 'code'),
        )
        for paths, expected in cases:
            with self.subTest(expected=expected, paths=paths):
                output = io.StringIO()
                with patch('sys.argv', ['scope', 'base', 'head']), \
                     patch.object(scope.subprocess, 'check_output', return_value=paths), \
                     contextlib.redirect_stdout(output):
                    scope.main()
                self.assertEqual(output.getvalue().strip(), expected)


if __name__ == '__main__':
    unittest.main()
