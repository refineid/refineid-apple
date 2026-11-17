#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
"""Usage: python3 -B Scripts/TestGatePlans.py."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parent
SUCCESS = 0
FAILURE = 1
USAGE_ERROR = 2
COMMAND_TIMEOUT_SECONDS = 30
EXECUTABLE_MODE = 0o755
LSREGISTER = (
    '/System/Library/Frameworks/CoreServices.framework/Frameworks/'
    'LaunchServices.framework/Support/lsregister'
)
TIERS = ('commit', 'pr', 'nfc-signing', 'macos-mvp')
SPY = '''import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
arguments = sys.argv[1:]
with open(os.environ['GATE_PLAN_TRACE'], 'a') as stream:
    stream.write(json.dumps([name, *arguments]) + '\\n')
if name == os.environ.get('GATE_PLAN_FAIL'):
    raise SystemExit(1)
if name == 'python3' and arguments[:1] == ['-c']:
    os.execv(sys.executable, [sys.executable, *arguments])
elif name == 'git':
    if arguments == ['rev-parse', 'HEAD']:
        print('<HEAD>')
    elif arguments == ['rev-parse', 'HEAD^{tree}']:
        print('<tree>')
    elif arguments[:3] == ['diff', '--cached', '--quiet']:
        raise SystemExit(int(os.environ.get('GATE_PLAN_RECEIPT_CHANGED', '0')))
elif name == 'xcrun':
    print(json.dumps({'devices': {'runtime': [{'name': 'iPhone Fixture'}]}}))
elif name == 'date':
    print('fixture-timestamp')
'''


class GatePlanTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.tools = self.root / 'tools'
        self.tools.mkdir()
        self.trace = self.root / 'tools.jsonl'
        self.env = os.environ.copy()
        self.env['PATH'] = str(self.tools) + os.pathsep + self.env['PATH']
        self.env['GATE_PLAN_TRACE'] = str(self.trace)
        for variable in ('GATE_PLAN_FAIL', 'GATE_PLAN_RECEIPT_CHANGED', 'BASH_ENV', 'ENV'):
            self.env.pop(variable, None)
        for name in ('python3', 'swift', 'swiftc', 'swiftlint', 'xcrun',
                     'xcodebuild', 'git', 'date', 'lsregister'):
            self.tool(self.tools / name)
        (self.root / 'Scripts/githooks').mkdir(parents=True)
        for name in ('test.sh', 'lint.sh'):
            source = (SCRIPTS / name).read_text()
            # Only the external cleanup executable is redirected; the real
            # gate's trap, product discovery, and cleanup control flow run.
            source = source.replace(LSREGISTER, str(self.tools / 'lsregister'))
            (self.root / 'Scripts' / name).write_text(source)
        self.tool(self.root / 'Scripts/QualityReceipt.py')
        self.tool(self.root / 'Scripts/dss-gate.sh')
        (self.root / 'Scripts/githooks/pre-commit').write_text('#!/bin/bash\n')
        (self.root / 'Scripts/apple-app-store-connect-release-manager.swift').touch()
        product = self.root / 'build/DerivedData/Build/Products/Debug/Fixture.app/Contents'
        product.mkdir(parents=True)
        (product / 'Info.plist').write_text('synthetic build product\n')

    def tearDown(self):
        self.directory.cleanup()

    def tool(self, path):
        path.write_text(f'#!{sys.executable}\n' + SPY)
        path.chmod(EXECUTABLE_MODE)

    def run_script(self, script, *arguments):
        return subprocess.run(
            ['/bin/bash', str(self.root / 'Scripts' / script), *arguments],
            cwd=self.root, env=self.env, capture_output=True, text=True,
            timeout=COMMAND_TIMEOUT_SECONDS)

    def calls(self):
        return [json.loads(line) for line in self.trace.read_text().splitlines()]

    def snapshot(self):
        return {
            str(path.relative_to(self.root)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in self.root.rglob('*') if path.is_file()
        }

    def test_plans_are_deterministic_and_have_no_tool_or_cleanup_side_effects(self):
        before = self.snapshot()
        for tier in TIERS:
            with self.subTest(tier=tier):
                first = self.run_script('test.sh', 'plan', tier)
                second = self.run_script('test.sh', 'plan', tier)
                self.assertEqual(first.returncode, SUCCESS, first.stderr)
                self.assertEqual(first.stdout, second.stdout)
                self.assertIn('=== ', first.stdout)
        self.assertFalse(self.trace.exists(), 'inspection invoked a tool or cleanup')
        self.assertEqual(before, self.snapshot())

    def test_lint_list_names_coverage_without_running_checks(self):
        before = self.snapshot()
        result = self.run_script('lint.sh', 'list')
        self.assertEqual(result.returncode, SUCCESS, result.stderr)
        for item in ('format Sources', 'shellcheck Scripts/test.sh',
                     'shellcheck Scripts/githooks/pre-commit',
                     'typecheck Scripts/apple-app-store-connect-release-manager.swift'):
            self.assertIn(item, result.stdout)
        self.assertFalse(self.trace.exists(), 'listing ran a checker')
        self.assertEqual(before, self.snapshot())

    def test_help_and_invalid_tiers_do_not_cleanup(self):
        for arguments, expected in [(('--help',), SUCCESS), (('unknown-tier',), USAGE_ERROR)]:
            with self.subTest(arguments=arguments):
                result = self.run_script('test.sh', *arguments)
                self.assertEqual(result.returncode, expected, result.stderr)
        self.assertFalse(self.trace.exists(), 'non-execution mode ran cleanup')

    def test_pr_tier_preserves_required_checks_and_cleans_real_runs(self):
        result = self.run_script('test.sh', 'pr')
        self.assertEqual(result.returncode, SUCCESS, result.stderr)
        calls = self.calls()
        required = [
            ['python3', '-B', 'Scripts/TestGatePlans.py'],
            ['python3', '-B', 'Scripts/TestDocumentationGate.py'],
            ['QualityReceipt.py', 'verify-clean-head'],
            ['python3', '-B', 'Scripts/TestQualityReceipt.py'],
            ['QualityReceipt.py', 'lint-head'],
            ['swift', 'test', '--package-path', 'CardCore'],
            ['swift', 'test', '--package-path', 'PKCS11Bridge'],
            ['dss-gate.sh'],
            ['swift', 'Scripts/TestMacosNotarizedDmgBuilder.swift'],
            ['swift', 'Scripts/TestAppleAppStoreConnectReleaseManager.swift'],
            ['QualityReceipt.py', 'verify-head', '<HEAD>', '<tree>'],
        ]
        self.assertEqual([call for call in calls if call in required], required)
        builds = [call for call in calls if call[0] == 'xcodebuild']
        common = ['-derivedDataPath', 'build/DerivedData', '-scheme', 'RefineID']
        self.assertEqual(builds, [
            ['xcodebuild', *common, '-destination', 'generic/platform=iOS',
             '-quiet', 'build', 'CODE_SIGNING_ALLOWED=NO'],
            ['xcodebuild', 'test', *common, '-destination', 'platform=macOS',
             '-only-testing:RefineIDTests', '-quiet'],
            ['xcodebuild', 'test', *common, '-destination',
             'platform=iOS Simulator,name=iPhone Fixture', '-only-testing:RefineIDTests', '-quiet'],
            ['xcodebuild', 'test', *common, '-destination', 'platform=macOS',
             '-only-testing:CardCoreTests', '-skip-testing:CardCoreTests/RappIntegrationTests', '-quiet'],
            ['xcodebuild', 'test', *common, '-destination', 'platform=macOS',
             '-only-testing:CardCoreTests/RappIntegrationTests', '-quiet'],
            ['xcodebuild', 'test', *common, '-destination',
             'platform=iOS Simulator,name=iPhone Fixture',
             '-only-testing:CardCoreTests/RappBleAppearanceWatcherTests',
             '-only-testing:CardCoreTests/CardCanOfferTests', '-quiet'],
        ])
        self.assertEqual(calls[-1], ['lsregister', '-u',
            'build/DerivedData/Build/Products/Debug/Fixture.app'])

    def test_failure_stops_later_checks_but_cleans_build_products(self):
        self.env['GATE_PLAN_FAIL'] = 'swift'
        result = self.run_script('test.sh', 'pr')
        self.assertEqual(result.returncode, FAILURE)
        self.assertIn('CardCore package tests failed', result.stderr)
        calls = self.calls()
        self.assertNotIn(['swift', 'test', '--package-path', 'PKCS11Bridge'], calls)
        self.assertFalse(any(call[0] == 'xcodebuild' for call in calls))
        self.assertEqual(calls[-1][0], 'lsregister')

    def test_commit_tier_runs_receipt_regressions_only_for_changed_receipt_files(self):
        for changed in (False, True):
            with self.subTest(changed=changed):
                self.trace.unlink(missing_ok=True)
                self.env['GATE_PLAN_RECEIPT_CHANGED'] = str(int(changed))
                result = self.run_script('test.sh', 'commit')
                self.assertEqual(result.returncode, SUCCESS, result.stderr)
                calls = self.calls()
                self.assertEqual(
                    ['python3', '-B', 'Scripts/TestQualityReceipt.py'] in calls, changed)
                self.assertIn(['git', 'diff', '--cached', '--check'], calls)
                self.assertIn(['QualityReceipt.py', 'lint-index'], calls)


if __name__ == '__main__':
    unittest.main()
