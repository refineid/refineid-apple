#!/usr/bin/env python3
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
"""Land a feature branch into main via a GitHub Pull Request.

Usage:
    python3 Scripts/LandPR.py [--title TITLE] [--body BODY] [--dry-run] [--no-delete-branch]

Preconditions:
    - Must be executed inside a feature branch or worktree (not main).
    - Working tree must be clean.
    - Branch must have at least one commit ahead of origin/main.
    - GitHub CLI (gh) must be installed and authenticated.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


class LandPRError(Exception):
    pass


def run_cmd(
    cmd: list[str],
    cwd: Path | None = None,
    capture: bool = True,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=capture,
            text=True,
            check=check,
        )
    except subprocess.CalledProcessError as error:
        stderr_msg = error.stderr.strip() if error.stderr else ""
        stdout_msg = error.stdout.strip() if error.stdout else ""
        msg = stderr_msg or stdout_msg or f"Command failed with exit code {error.returncode}"
        raise LandPRError(f"{' '.join(cmd)} failed: {msg}") from error


def get_git_root() -> Path:
    res = run_cmd(["git", "rev-parse", "--show-toplevel"])
    return Path(res.stdout.strip()).resolve()


def get_current_branch(root: Path) -> str:
    res = run_cmd(["git", "branch", "--show-current"], cwd=root)
    branch = res.stdout.strip()
    if not branch:
        raise LandPRError("Not currently on any branch (detached HEAD).")
    return branch


def check_working_tree_clean(root: Path) -> None:
    res = run_cmd(["git", "status", "--porcelain"], cwd=root)
    if res.stdout.strip():
        raise LandPRError(
            "Working tree has uncommitted changes. Commit or stash them before landing."
        )


def check_commits_ahead(root: Path, branch: str, base_remote: str = "origin") -> list[str]:
    # Ensure remote tracking ref exists
    run_cmd(["git", "fetch", base_remote, "main"], cwd=root)
    res = run_cmd(
        ["git", "rev-list", f"{base_remote}/main..HEAD"],
        cwd=root,
    )
    commits = [c.strip() for c in res.stdout.splitlines() if c.strip()]
    if not commits:
        raise LandPRError(
            f"No commits on branch '{branch}' ahead of {base_remote}/main to land."
        )
    return commits


def extract_pr_metadata(root: Path, base_remote: str = "origin") -> tuple[str, str]:
    res = run_cmd(
        ["git", "log", f"{base_remote}/main..HEAD", "--format=%s%x00%b%x01"],
        cwd=root,
    )
    raw_entries = res.stdout.split("\x01")
    entries = []
    for raw in raw_entries:
        if not raw.strip():
            continue
        parts = raw.split("\x00", 1)
        subject = parts[0].strip()
        body = parts[1].strip() if len(parts) > 1 else ""
        entries.append((subject, body))

    if not entries:
        return ("Automated Pull Request", "")

    if len(entries) == 1:
        return entries[0]

    # For multiple commits: use latest commit subject as title, list all in body
    latest_subject, _ = entries[0]
    body_lines = ["Commits included:"]
    for subj, _ in reversed(entries):
        body_lines.append(f"- {subj}")
    return latest_subject, "\n".join(body_lines)


def check_gh_cli() -> None:
    if not shutil.which("gh"):
        raise LandPRError(
            "GitHub CLI (gh) is required but not installed or not found in PATH."
        )
    res = subprocess.run(["gh", "auth", "status"], capture_output=True, text=True)
    if res.returncode != 0:
        raise LandPRError(
            f"GitHub CLI is not authenticated. Run 'gh auth login' first.\n{res.stderr.strip()}"
        )


def find_existing_pr(root: Path, branch: str) -> dict[str, str] | None:
    res = run_cmd(
        ["gh", "pr", "list", "--head", branch, "--base", "main", "--state", "open", "--json", "number,url,title"],
        cwd=root,
    )
    try:
        prs = json.loads(res.stdout)
        if prs and isinstance(prs, list):
            return prs[0]
    except json.JSONDecodeError:
        pass
    return None


def is_worktree(root: Path) -> bool:
    res = run_cmd(["git", "rev-parse", "--git-common-dir"], cwd=root)
    common_dir = Path(res.stdout.strip()).resolve()
    git_dir = (root / ".git").resolve()
    # In a worktree, .git is a file, or git_dir != common_dir
    return not git_dir.is_dir() or git_dir != common_dir


def land_pr(
    title: str | None = None,
    body: str | None = None,
    dry_run: bool = False,
    delete_branch: bool = True,
    remote: str = "origin",
) -> None:
    root = get_git_root()
    branch = get_current_branch(root)

    if branch == "main":
        raise LandPRError(
            "Cannot land directly from 'main'. Work in a feature branch or worktree under ../wt/refineid-apple-<topic>\n"
            "(see AGENTS.md and Documentation/process/agent-worktrees.md)."
        )

    check_working_tree_clean(root)
    commits = check_commits_ahead(root, branch, base_remote=remote)
    check_gh_cli()

    default_title, default_body = extract_pr_metadata(root, base_remote=remote)
    pr_title = title if title else default_title
    pr_body = body if body is not None else default_body

    print(f"Branch:  {branch}")
    print(f"Commits: {len(commits)} commit(s) ahead of {remote}/main")
    print(f"Title:   {pr_title}")
    if pr_body:
        print(f"Body:\n{pr_body.strip()}\n")

    if dry_run:
        print("[dry-run] Preconditions verified. No push or merge performed.")
        return

    # 1. Push branch to remote
    print(f"Pushing '{branch}' to {remote}...")
    run_cmd(["git", "push", "-u", remote, branch], cwd=root, capture=False)

    # 2. Find or create PR
    existing_pr = find_existing_pr(root, branch)
    if existing_pr:
        pr_number = str(existing_pr["number"])
        pr_url = existing_pr.get("url", f"#{pr_number}")
        print(f"Found existing open PR #{pr_number}: {pr_url}")
    else:
        print("Creating Pull Request...")
        cmd = [
            "gh", "pr", "create",
            "--head", branch,
            "--base", "main",
            "--title", pr_title,
            "--body", pr_body,
        ]
        res = run_cmd(cmd, cwd=root)
        pr_url = res.stdout.strip()
        print(f"Created Pull Request: {pr_url}")
        # Extract PR number from URL or query
        pr_number = pr_url.rstrip("/").split("/")[-1]

    # 3. Squash and merge PR
    print(f"Merging PR #{pr_number} into main...")
    merge_cmd = ["gh", "pr", "merge", pr_number, "--squash"]
    if delete_branch:
        merge_cmd.append("--delete-branch")
    run_cmd(merge_cmd, cwd=root, capture=False)

    # 4. Sync
    run_cmd(["git", "fetch", remote, "main"], cwd=root)
    worktree_mode = is_worktree(root)

    print("\n" + "=" * 60)
    print(f"✓ Pull Request #{pr_number} squashed and merged into main.")
    if delete_branch:
        print(f"✓ Remote branch '{branch}' deleted.")

    if worktree_mode:
        print(f"✓ Worktree ({root.name}) task completed.")
        print("  You can now switch to main in your primary repository, or clean up with:")
        print("    Scripts/agent-housekeeping.sh --clean")
    else:
        print("Updating local main...")
        run_cmd(["git", "checkout", "main"], cwd=root)
        run_cmd(["git", "pull", "--ff-only", remote, "main"], cwd=root)
        print("✓ Local main fast-forwarded to latest.")
    print("=" * 60)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Land a feature branch into main via a GitHub Pull Request."
    )
    parser.add_argument("--title", help="Custom Pull Request title")
    parser.add_argument("--body", help="Custom Pull Request body description")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Check preconditions without pushing or merging",
    )
    parser.add_argument(
        "--no-delete-branch",
        action="store_true",
        help="Keep remote branch after squash-merge",
    )
    args = parser.parse_args()

    try:
        land_pr(
            title=args.title,
            body=args.body,
            dry_run=args.dry_run,
            delete_branch=not args.no_delete_branch,
        )
    except LandPRError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
