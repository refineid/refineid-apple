#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
"""Usage: python3 -B Scripts/TestLandPR.py."""

from pathlib import Path
import unittest
from unittest.mock import MagicMock, patch

import LandPR


class LandPRTests(unittest.TestCase):
    def test_refuses_main_branch(self):
        with patch.object(LandPR, "get_git_root", return_value=Path("/repo")), \
             patch.object(LandPR, "get_current_branch", return_value="main"):
            with self.assertRaises(LandPR.LandPRError) as cm:
                LandPR.land_pr()
            self.assertIn("Cannot land directly from 'main'", str(cm.exception))

    def test_refuses_dirty_working_tree(self):
        mock_proc = MagicMock(stdout=" M SomeFile.swift\n")
        with patch.object(LandPR, "get_git_root", return_value=Path("/repo")), \
             patch.object(LandPR, "get_current_branch", return_value="feature-1"), \
             patch.object(LandPR, "run_cmd", return_value=mock_proc):
            with self.assertRaises(LandPR.LandPRError) as cm:
                LandPR.check_working_tree_clean(Path("/repo"))
            self.assertIn("Working tree has uncommitted changes", str(cm.exception))

    def test_refuses_no_commits_ahead(self):
        def fake_run(cmd, cwd=None, **kwargs):
            if "rev-list" in cmd:
                return MagicMock(stdout="")
            return MagicMock(stdout="")

        with patch.object(LandPR, "run_cmd", side_effect=fake_run):
            with self.assertRaises(LandPR.LandPRError) as cm:
                LandPR.check_commits_ahead(Path("/repo"), "feature-1")
            self.assertIn("No commits on branch 'feature-1' ahead of origin/main", str(cm.exception))

    def test_extract_metadata_single_commit(self):
        def fake_run(cmd, cwd=None, **kwargs):
            return MagicMock(stdout="Fix typo in metadata\x00Detailed body message\x01")

        with patch.object(LandPR, "run_cmd", side_effect=fake_run):
            title, body = LandPR.extract_pr_metadata(Path("/repo"))
            self.assertEqual(title, "Fix typo in metadata")
            self.assertEqual(body, "Detailed body message")

    def test_extract_metadata_multiple_commits(self):
        def fake_run(cmd, cwd=None, **kwargs):
            # git log lists newest to oldest
            return MagicMock(
                stdout="Second commit\x00\x01First commit\x00\x01"
            )

        with patch.object(LandPR, "run_cmd", side_effect=fake_run):
            title, body = LandPR.extract_pr_metadata(Path("/repo"))
            self.assertEqual(title, "Second commit")
            self.assertIn("Commits included:\n- First commit\n- Second commit", body)

    def test_dry_run_does_not_push_or_merge(self):
        with patch.object(LandPR, "get_git_root", return_value=Path("/repo")), \
             patch.object(LandPR, "get_current_branch", return_value="feature-1"), \
             patch.object(LandPR, "check_working_tree_clean"), \
             patch.object(LandPR, "check_commits_ahead", return_value=["abc1234"]), \
             patch.object(LandPR, "check_gh_cli"), \
             patch.object(LandPR, "extract_pr_metadata", return_value=("Title", "Body")), \
             patch.object(LandPR, "run_cmd") as mock_run:
            LandPR.land_pr(dry_run=True)
            mock_run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
