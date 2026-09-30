#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Usage: python3 Scripts/TestQualityReceipt.py
#
# Verify exact-tree lint receipts with an isolated Git repository and fake linter.

import contextlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest import mock

sys.dont_write_bytecode = True


SCRIPT = Path(__file__).with_name("QualityReceipt.py")
SPEC = importlib.util.spec_from_file_location("quality_receipt", SCRIPT)
quality_receipt = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(quality_receipt)


FIXTURE_GIT_ENVIRONMENT = {
    "GIT_AUTHOR_NAME",
    "GIT_AUTHOR_EMAIL",
    "GIT_COMMITTER_NAME",
    "GIT_COMMITTER_EMAIL",
}


def fixture_environment(environment=None):
    source = os.environ if environment is None else environment
    return {
        name: value
        for name, value in source.items()
        if not name.startswith("GIT_") or name in FIXTURE_GIT_ENVIRONMENT
    }


def git(root, *arguments):
    return subprocess.check_output(
        ["git", *arguments],
        cwd=root,
        env=fixture_environment(),
        text=True,
        stderr=subprocess.PIPE,
    ).strip()


class QualityReceiptTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.repo = self.base / "repo"
        self.repo.mkdir()
        self.home = self.base / "home"
        self.home.mkdir()
        self.counter = self.base / "calls"
        self.marker = self.base / "mutation-complete"
        self.environment = {
            **fixture_environment(),
            "GIT_AUTHOR_NAME": "Quality Test",
            "GIT_AUTHOR_EMAIL": "quality-test@example.invalid",
            "GIT_COMMITTER_NAME": "Quality Test",
            "GIT_COMMITTER_EMAIL": "quality-test@example.invalid",
            "QUALITY_TEST_COUNTER": str(self.counter),
        }
        subprocess.run(
            ["git", "init", "--quiet", "--initial-branch=main"],
            cwd=self.repo,
            env=fixture_environment(self.environment),
            check=True,
        )
        self.write_linter()
        (self.repo / "Sources").mkdir()
        (self.repo / "Sources" / "Probe.swift").write_text("PASS\n")
        (self.repo / ".swift-format").write_text("initial config\n")
        git(self.repo, "add", ".")
        git(self.repo, "commit", "--quiet", "-m", "Initial quality fixture")
        self.environment_patch = mock.patch.dict(
            os.environ, self.environment, clear=True
        )
        self.environment_patch.start()
        self.addCleanup(self.environment_patch.stop)
        self.home_patch = mock.patch.object(
            quality_receipt.Path, "home", return_value=self.home
        )
        self.home_patch.start()
        self.addCleanup(self.home_patch.stop)

    def write_linter(self):
        scripts = self.repo / "Scripts"
        scripts.mkdir(exist_ok=True)
        script = scripts / "lint.sh"
        script.write_text(
            "#!/bin/bash\n"
            "set -euo pipefail\n"
            "printf x >> \"$QUALITY_TEST_COUNTER\"\n"
            "if ! grep -q '^PASS$' Sources/Probe.swift; then exit 1; fi\n"
            "if [ \"${QUALITY_TEST_MUTATE:-0}\" = 1 ] "
            "&& [ ! -e \"$QUALITY_TEST_MARKER\" ]; then\n"
            "  printf 'FAIL\\n' > \"$QUALITY_TEST_ROOT/Sources/Probe.swift\"\n"
            "  git -C \"$QUALITY_TEST_ROOT\" add Sources/Probe.swift\n"
            "  if [ \"${QUALITY_TEST_COMMIT:-0}\" = 1 ]; then\n"
            "    git -C \"$QUALITY_TEST_ROOT\" commit --quiet -m 'Fixture tree change'\n"
            "  fi\n"
            "  touch \"$QUALITY_TEST_MARKER\"\n"
            "fi\n"
        )
        script.chmod(0o755)

    def run_lint(self, tree=None, fingerprint="toolchain-a", guard="index"):
        tree = tree or quality_receipt.tree_for(self.repo, "index")
        with contextlib.redirect_stdout(io.StringIO()):
            return quality_receipt.run_lint(
                self.repo, tree, fingerprint, tree_guard=guard
            )

    def calls(self):
        return len(self.counter.read_text()) if self.counter.exists() else 0

    def receipts(self):
        return list(
            (
                self.home
                / "Library"
                / "Caches"
                / "RefineID"
                / "QualityReceipts"
            ).glob("*.json")
        )

    def test_exact_tree_hit_and_staged_snapshot_resist_unstaged_laundering(self):
        source = self.repo / "Sources" / "Probe.swift"
        source.write_text("FAIL\n")
        git(self.repo, "add", "Sources/Probe.swift")
        staged_tree = quality_receipt.tree_for(self.repo, "index")
        source.write_text("PASS\n")

        self.assertNotEqual(self.run_lint(staged_tree), 0)
        self.assertEqual(self.calls(), 1)
        self.assertEqual(self.receipts(), [])

        source.write_text("PASS\n")
        git(self.repo, "add", "Sources/Probe.swift")
        staged_tree = quality_receipt.tree_for(self.repo, "index")
        index_before = staged_tree
        source.write_text("FAIL\n")

        self.assertEqual(self.run_lint(staged_tree), 0)
        self.assertEqual(quality_receipt.tree_for(self.repo, "index"), index_before)
        self.assertEqual(self.run_lint(staged_tree), 0)
        self.assertEqual(self.calls(), 2)

    def test_export_attributes_cannot_hide_staged_lint_inputs(self):
        source = self.repo / "Sources" / "Probe.swift"
        attributes = self.repo / ".gitattributes"
        attributes.write_text("Sources/Probe.swift export-ignore\n")
        git(self.repo, "add", ".gitattributes")
        source.write_text("PASS\n")
        git(self.repo, "add", "Sources/Probe.swift")
        staged_tree = quality_receipt.tree_for(self.repo, "index")
        source.write_text("FAIL\n")

        self.assertEqual(self.run_lint(staged_tree), 0)
        self.assertEqual(quality_receipt.tree_for(self.repo, "index"), staged_tree)
        self.assertEqual(self.calls(), 1)

    def test_inherited_git_index_cannot_redirect_fixture_commands(self):
        sentinel = self.base / "sentinel"
        sentinel.mkdir()
        sentinel_environment = {
            **fixture_environment(),
            "GIT_AUTHOR_NAME": "Sentinel Test",
            "GIT_AUTHOR_EMAIL": "sentinel@example.invalid",
            "GIT_COMMITTER_NAME": "Sentinel Test",
            "GIT_COMMITTER_EMAIL": "sentinel@example.invalid",
        }
        subprocess.run(
            ["git", "init", "--quiet", "--initial-branch=sentinel"],
            cwd=sentinel,
            env=sentinel_environment,
            check=True,
        )
        (sentinel / "sentinel.txt").write_text("preserve\n")
        subprocess.run(
            ["git", "add", "sentinel.txt"],
            cwd=sentinel,
            env=sentinel_environment,
            check=True,
        )
        subprocess.run(
            ["git", "commit", "--quiet", "-m", "Sentinel index"],
            cwd=sentinel,
            env=sentinel_environment,
            check=True,
        )
        sentinel_head = git(sentinel, "rev-parse", "HEAD")
        sentinel_tree = git(sentinel, "write-tree")
        sentinel_index = sentinel / ".git" / "index"
        original_index = sentinel_index.read_bytes()
        staged_tree = quality_receipt.tree_for(self.repo, "index")

        with mock.patch.dict(os.environ, {"GIT_INDEX_FILE": str(sentinel_index)}):
            (self.repo / "Sources" / "Probe.swift").write_text("PASS\n")
            git(self.repo, "add", "Sources/Probe.swift")
            git(self.repo, "status", "--porcelain")
            self.assertEqual(self.run_lint(staged_tree, guard=None), 0)

        self.assertEqual(git(sentinel, "rev-parse", "HEAD"), sentinel_head)
        self.assertEqual(git(sentinel, "write-tree"), sentinel_tree)
        self.assertEqual(sentinel_index.read_bytes(), original_index)

    def test_source_configuration_and_toolchain_changes_miss(self):
        tree = quality_receipt.tree_for(self.repo, "index")
        self.assertEqual(self.run_lint(tree), 0)

        config = self.repo / ".swift-format"
        config.write_text("changed config\n")
        git(self.repo, "add", ".swift-format")
        config_tree = quality_receipt.tree_for(self.repo, "index")
        self.assertNotEqual(config_tree, tree)
        self.assertEqual(self.run_lint(config_tree), 0)

        source = self.repo / "Sources" / "Probe.swift"
        source.write_text("PASS\n\n")
        git(self.repo, "add", "Sources/Probe.swift")
        source_tree = quality_receipt.tree_for(self.repo, "index")
        self.assertNotEqual(source_tree, config_tree)
        self.assertEqual(self.run_lint(source_tree), 0)
        self.assertEqual(self.run_lint(source_tree, "toolchain-b"), 0)
        self.assertEqual(self.calls(), 4)

    def test_tool_fingerprint_tracks_binary_and_selected_environment(self):
        fake_tool = self.base / "tool"
        fake_tool.write_text("first tool binary")
        with mock.patch.object(quality_receipt.shutil, "which", return_value=str(fake_tool)):
            with mock.patch.object(
                quality_receipt,
                "command_output",
                side_effect=lambda arguments: (
                    str(fake_tool)
                    if "--find" in arguments
                    else "stable version"
                ),
            ):
                first = quality_receipt.toolchain_fingerprint()
                fake_tool.write_text("second tool binary")
                second = quality_receipt.toolchain_fingerprint()
                with mock.patch.dict(os.environ, {"SDKROOT": "alternate-sdk"}):
                    third = quality_receipt.toolchain_fingerprint()

        self.assertNotEqual(first, second)
        self.assertNotEqual(second, third)

    def test_toolchain_change_during_lint_is_not_cached_or_reused(self):
        tree = quality_receipt.tree_for(self.repo, "index")
        initial = "toolchain-a"
        with mock.patch.object(
            quality_receipt,
            "toolchain_fingerprint",
            side_effect=[initial, "toolchain-b"],
        ):
            self.assertNotEqual(
                quality_receipt.run_lint(
                    self.repo,
                    tree,
                    initial,
                    tree_guard="index",
                    fingerprint_supplier=quality_receipt.toolchain_fingerprint,
                ),
                0,
            )
        self.assertEqual(self.calls(), 1)
        self.assertEqual(self.receipts(), [])

        self.assertEqual(self.run_lint(tree, initial), 0)
        with mock.patch.object(
            quality_receipt, "toolchain_fingerprint", return_value="toolchain-b"
        ):
            self.assertNotEqual(
                quality_receipt.run_lint(
                    self.repo,
                    tree,
                    initial,
                    tree_guard="index",
                    fingerprint_supplier=quality_receipt.toolchain_fingerprint,
                ),
                0,
            )
        self.assertEqual(self.calls(), 2)

    def test_failed_lint_never_writes_a_receipt(self):
        source = self.repo / "Sources" / "Probe.swift"
        source.write_text("FAIL\n")
        git(self.repo, "add", "Sources/Probe.swift")
        tree = quality_receipt.tree_for(self.repo, "index")

        self.assertNotEqual(self.run_lint(tree), 0)
        self.assertNotEqual(self.run_lint(tree), 0)
        self.assertEqual(self.calls(), 2)
        self.assertEqual(self.receipts(), [])

    def test_corrupt_and_symlink_receipts_are_cache_misses(self):
        tree = quality_receipt.tree_for(self.repo, "index")
        self.assertEqual(self.run_lint(tree), 0)
        receipt = self.receipts()[0]
        receipt.write_text("invalid receipt\n")
        self.assertEqual(self.run_lint(tree), 0)
        self.assertEqual(self.calls(), 2)

        receipt = self.receipts()[0]
        outside = self.base / "outside"
        outside.write_text("preserve\n")
        receipt.unlink()
        receipt.symlink_to(outside)
        self.assertEqual(self.run_lint(tree), 0)
        self.assertEqual(self.calls(), 3)
        self.assertEqual(outside.read_text(), "preserve\n")
        self.assertTrue(receipt.is_file())
        self.assertFalse(receipt.is_symlink())

    def test_index_change_during_lint_fails_without_receipt(self):
        tree = quality_receipt.tree_for(self.repo, "index")
        with mock.patch.dict(
            os.environ,
            {
                "QUALITY_TEST_MUTATE": "1",
                "QUALITY_TEST_ROOT": str(self.repo),
                "QUALITY_TEST_MARKER": str(self.marker),
            },
        ):
            self.assertNotEqual(self.run_lint(tree), 0)
        self.assertNotEqual(quality_receipt.tree_for(self.repo, "index"), tree)
        self.assertEqual(self.receipts(), [])

    def test_index_change_during_receipt_hit_is_rejected(self):
        tree = quality_receipt.tree_for(self.repo, "index")
        self.assertEqual(self.run_lint(tree), 0)
        source = self.repo / "Sources" / "Probe.swift"

        def change_index(*_arguments):
            source.write_text("FAIL\n")
            git(self.repo, "add", "Sources/Probe.swift")
            return True

        with mock.patch.object(
            quality_receipt, "receipt_is_valid", side_effect=change_index
        ):
            self.assertNotEqual(self.run_lint(tree), 0)
        self.assertEqual(self.calls(), 1)

    def test_head_change_during_lint_fails_without_receipt(self):
        tree = quality_receipt.tree_for(self.repo, "head")
        with mock.patch.dict(
            os.environ,
            {
                "QUALITY_TEST_MUTATE": "1",
                "QUALITY_TEST_ROOT": str(self.repo),
                "QUALITY_TEST_MARKER": str(self.marker),
                "QUALITY_TEST_COMMIT": "1",
            },
        ):
            self.assertNotEqual(
                self.run_lint(tree, guard="head"), 0
            )
        self.assertEqual(self.receipts(), [])

    def test_push_rejects_hidden_worktree_changes(self):
        source = self.repo / "Sources" / "Probe.swift"
        for flag, reset_flag in (
            ("--assume-unchanged", "--no-assume-unchanged"),
            ("--skip-worktree", "--no-skip-worktree"),
        ):
            with self.subTest(flag=flag):
                source.write_text("FAIL\n")
                git(self.repo, "update-index", flag, "Sources/Probe.swift")
                self.assertEqual(
                    git(self.repo, "status", "--porcelain", "--untracked-files=all"),
                    "",
                )
                with self.assertRaises(quality_receipt.GateError):
                    quality_receipt.require_clean_head(self.repo)
                source.write_text("PASS\n")
                git(self.repo, "update-index", reset_flag, "Sources/Probe.swift")

    def test_concurrent_callers_write_one_atomic_receipt(self):
        tree = quality_receipt.tree_for(self.repo, "index")
        barrier = threading.Barrier(3)
        results = []

        def invoke():
            barrier.wait()
            results.append(self.run_lint(tree))

        threads = [threading.Thread(target=invoke) for _ in range(2)]
        for thread in threads:
            thread.start()
        barrier.wait()
        for thread in threads:
            thread.join()

        self.assertEqual(results, [0, 0])
        self.assertEqual(self.calls(), 1)
        self.assertEqual(len(self.receipts()), 1)
        self.assertEqual(self.run_lint(tree), 0)
        self.assertEqual(self.calls(), 1)

    def test_push_ref_updates_check_local_commit_and_clean_tree(self):
        (self.repo / ".swift-format").write_text("next config\n")
        git(self.repo, "add", ".swift-format")
        git(self.repo, "commit", "--quiet", "-m", "Second quality fixture")
        head = git(self.repo, "rev-parse", "HEAD")
        previous = git(self.repo, "rev-parse", "HEAD^")
        git(self.repo, "tag", "--annotate", "release", "--message", "Fixture tag", head)
        annotated_tag = git(self.repo, "rev-parse", "refs/tags/release")
        updates = [
            f"refs/heads/main {head} refs/heads/main {head}\n",
            f"refs/heads/new {head} refs/heads/new {'0' * len(head)}\n",
            f"refs/tags/release {annotated_tag} refs/tags/release {head}\n",
            f"refs/heads/old {'0' * len(head)} refs/heads/old {head}\n",
        ]
        for update in updates:
            with mock.patch.object(sys, "stdin", io.StringIO(update)):
                quality_receipt.verify_push(self.repo)

        with mock.patch.object(
            sys,
            "stdin",
            io.StringIO(
                f"refs/heads/old {previous} refs/heads/old {previous}\n"
            ),
        ):
            with self.assertRaises(quality_receipt.GateError):
                quality_receipt.verify_push(self.repo)

        with mock.patch.object(
            sys, "stdin", io.StringIO(f"refs/heads/main {head} refs/heads/main {head}\n")
        ):
            (self.repo / "unstaged.swift").write_text("dirty\n")
            with self.assertRaises(quality_receipt.GateError):
                quality_receipt.verify_push(self.repo)


if __name__ == "__main__":
    unittest.main()
