#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Report agent worktree health, and with --clean remove only what is
# provably done.
#
# Usage:
#   Scripts/agent-housekeeping.py [--clean]
#
# Without flags the script only reports. With --clean it removes worktrees
# whose branch is merged into main, whose tree is clean, and that hold no
# unpushed commits, then deletes the merged branch. A branch counts as
# merged when main contains it by ancestry, or when every one of its
# changes is already in main by patch: each commit on its own, or the
# branch's whole diff as one squash. A live claim is tested first, so a
# fresh or dirty worktree is never removed even when its branch is merged.
# Anything else — uncommitted changes, unpushed commits, or an unmerged
# branch — is reported with its latest commit message and never destroyed.

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys
import time


def get_cmd_output(cmd: list[str], cwd: Path | None = None) -> str:
    res = subprocess.run(
        cmd,
        cwd=cwd,
        capture_output=True,
        text=True,
        check=False,
    )
    if res.returncode == 0:
        return res.stdout.strip()
    return ""


def merged_by(branch: str, repo_root: Path) -> str:
    # 1. Ancestry
    res = subprocess.run(
        ["git", "merge-base", "--is-ancestor", branch, "main"],
        cwd=repo_root,
        capture_output=True,
        check=False,
    )
    if res.returncode == 0:
        return "ancestry"

    # 2. Patch (cherry)
    res = subprocess.run(
        ["git", "cherry", "main", branch],
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
    )
    if res.returncode == 0 and res.stdout.strip():
        lines = res.stdout.strip().splitlines()
        if not any(line.startswith("+") for line in lines):
            return "patch"

    # 3. Squash diff against main
    base = get_cmd_output(["git", "merge-base", "main", branch], cwd=repo_root)
    if not base:
        return ""

    diff_res = subprocess.run(
        ["git", "diff", "--no-color", "--no-ext-diff", base, branch],
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
    )
    if diff_res.returncode != 0:
        return ""

    patch_id_res = subprocess.run(
        ["git", "patch-id", "--stable"],
        cwd=repo_root,
        input=diff_res.stdout,
        capture_output=True,
        text=True,
        check=False,
    )
    if patch_id_res.returncode != 0 or not patch_id_res.stdout.strip():
        return ""

    squash_id = patch_id_res.stdout.strip().split()[0]
    if not squash_id:
        return ""

    log_res = subprocess.run(
        ["git", "log", "-p", "--no-merges", "--no-color", "--no-ext-diff", f"{base}..main"],
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
    )
    if log_res.returncode != 0:
        return ""

    main_patch_res = subprocess.run(
        ["git", "patch-id", "--stable"],
        cwd=repo_root,
        input=log_res.stdout,
        capture_output=True,
        text=True,
        check=False,
    )
    if main_patch_res.returncode != 0:
        return ""

    main_ids = {line.split()[0] for line in main_patch_res.stdout.strip().splitlines() if line}
    if squash_id in main_ids:
        return "squash"

    return ""


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Report agent worktree health, and with --clean remove only what is provably done."
    )
    parser.add_argument("--clean", action="store_true", help="Remove merged, clean, and pushed worktrees")
    args = parser.parse_args()

    toplevel = get_cmd_output(["git", "rev-parse", "--show-toplevel"])
    if not toplevel:
        print("Not a git repository.", file=sys.stderr)
        sys.exit(1)

    repo_root = Path(toplevel).resolve()
    os.chdir(repo_root)

    subprocess.run(["git", "worktree", "prune"], check=False)

    worktree_res = subprocess.run(
        ["git", "worktree", "list", "--porcelain"],
        capture_output=True,
        text=True,
        check=False,
    )
    if worktree_res.returncode != 0:
        print("Failed to list worktrees.", file=sys.stderr)
        sys.exit(1)

    stale_after_seconds = 86400
    now = time.time()

    sections: list[list[str]] = []
    current_section: list[str] = []
    for line in worktree_res.stdout.splitlines():
        if not line.strip():
            if current_section:
                sections.append(current_section)
                current_section = []
        else:
            current_section.append(line)
    if current_section:
        sections.append(current_section)

    primary_path: Path | None = None
    worktrees: list[dict[str, str]] = []

    for sec in sections:
        item: dict[str, str] = {}
        for l in sec:
            if l.startswith("worktree "):
                item["worktree"] = l[len("worktree ") :]
            elif l.startswith("branch "):
                item["branch"] = l[len("branch ") :]
            elif l == "bare":
                item["bare"] = "1"
        if "worktree" in item:
            wt_p = Path(item["worktree"]).resolve()
            if primary_path is None:
                primary_path = wt_p
            else:
                worktrees.append(item)

    if primary_path is None:
        return

    wt_root = (primary_path.parent / "wt").resolve()

    for item in worktrees:
        wt_path = Path(item["worktree"]).resolve()
        branch_name = get_cmd_output(["git", "-C", str(wt_path), "rev-parse", "--abbrev-ref", "HEAD"])
        if not branch_name:
            print(f"--- {wt_path}")
            print("  verdict: REVIEW (not a readable checkout)")
            print()
            continue

        merged_test = merged_by(branch_name, repo_root)
        merged = f"yes ({merged_test})" if merged_test else "no"

        status_out = get_cmd_output(["git", "-C", str(wt_path), "status", "--porcelain"])
        dirty = "yes" if status_out else "no"

        branch_commits_str = get_cmd_output(
            ["git", "-C", str(wt_path), "rev-list", "--count", f"main..{branch_name}"]
        )
        try:
            branch_commits = int(branch_commits_str) if branch_commits_str else 0
        except ValueError:
            branch_commits = 0

        upstream_ok = (
            subprocess.run(
                ["git", "-C", str(wt_path), "rev-parse", "--abbrev-ref", f"{branch_name}@{{upstream}}"],
                capture_output=True,
                check=False,
            ).returncode
            == 0
        )
        if upstream_ok:
            unpushed = get_cmd_output(
                ["git", "-C", str(wt_path), "rev-list", "--count", f"{branch_name}@{{upstream}}..{branch_name}"]
            ) or "?"
        elif merged_test:
            unpushed = "0"
        else:
            unpushed = str(branch_commits)

        try:
            tree_mtime = int(wt_path.stat().st_mtime)
        except OSError:
            tree_mtime = 0

        last_commit_time = 0
        if branch_commits > 0:
            commit_time_str = get_cmd_output(
                ["git", "-C", str(wt_path), "log", "-1", "--format=%ct"]
            )
            try:
                last_commit_time = int(commit_time_str) if commit_time_str else 0
            except ValueError:
                last_commit_time = 0
            latest_subject = get_cmd_output(
                ["git", "-C", str(wt_path), "log", "-1", "--format=%s"]
            )
        else:
            latest_subject = "(no commits on branch yet)"

        latest_activity = max(last_commit_time, tree_mtime)
        age = int(now - latest_activity)
        if age > stale_after_seconds:
            activity = f"stale ({age}s since activity)"
        else:
            activity = f"fresh ({age}s since activity)"

        du_out = get_cmd_output(["du", "-sh", str(wt_path)])
        size = du_out.split()[0] if du_out else ""

        print(f"--- {wt_path} [{size}]")
        if not str(wt_path).startswith(f"{wt_root}/"):
            print(f"  policy: NON-COMPLIANT (worktree must live under {wt_root}/)")
        print(f"  branch: {branch_name} (merged: {merged}, dirty: {dirty}, unpushed: {unpushed})")
        print(f"  activity: {activity}")
        if latest_subject:
            print(f"  latest: {latest_subject}")

        if activity.startswith("fresh") or dirty == "yes":
            print("  verdict: KEEP (live claim)")
        elif merged_test and dirty == "no" and unpushed == "0":
            if args.clean:
                subprocess.run(["git", "worktree", "remove", str(wt_path)], check=False)
                subprocess.run(["git", "branch", "-D", branch_name], check=False)
                print(f"  verdict: REMOVED (worktree {wt_path}, branch {branch_name})")
            else:
                print("  verdict: REMOVE (rerun with --clean)")
        else:
            print("  verdict: REVIEW (needs an owner decision)")
        print()


if __name__ == "__main__":
    main()
