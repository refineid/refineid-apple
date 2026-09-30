# Agent Worktrees

Status: Active

Date: 2026-09-12

## Context

Several agents (and the owner) work on this repository at the same time.
One task, one worktree, one branch, one pull request keeps that work from
colliding and keeps the main checkout pristine for integration.

## Topology and naming

- The main checkout is never edited directly. It integrates and releases.
- Each task gets a worktree under ~/src/wt, never loose beside repositories or under /tmp:
  `~/src/wt/refineid-apple-<topic>` on branch `agent/<topic>`.
- One branch carries one pull request. Never stack unrelated work onto a
  branch that already has an open pull request.

## Starting a task

1. Update local main: `git checkout main && git pull --ff-only`.
2. Create the worktree: `git worktree add ~/src/wt/refineid-apple-<topic> -b agent/<topic>`.
3. Activate the quality gate hooks in the worktree: `git config core.hooksPath Scripts/githooks`.
4. Never copy distribution or release signing credentials: worktrees build debug only;
   store and TestFlight distribution stays in the main checkout via
   `Scripts/apple-app-store-connect-release-manager.swift`.
5. Run `Scripts/agent-housekeeping.sh` and act on what it reports.

Swift Package Manager's package download cache and Xcode DerivedData live
outside the checkout (`~/Library/Caches/org.swift.swiftpm` and DerivedData).
Package downloads can be reused between worktrees. Keep Xcode's writable
DerivedData separate between concurrent worktrees.

Successful local lint receipts live outside worktrees in
`~/Library/Caches/RefineID/QualityReceipts`. They match the full Git tree and
the selected lint toolchain, allowing a staged-tree lint pass to satisfy the
later pre-push lint for the same commit. These receipts are local cache data,
not remote attestations. The mandatory local push gate verifies changes before
a pull request is opened. GitHub does not repeat Apple build and test gates
on pushes or pull requests.

## Housekeeping

`Scripts/agent-housekeeping.sh` reports every worktree with its branch,
merge state, dirty files, unpushed commits, activity freshness, and disk use.
With `--clean` it removes only what is provably done:

- The branch is merged into main, the tree is clean, and nothing is
  unpushed. The work is fully preserved in main, so deleting the worktree
  loses nothing. The branch goes with it.

Everything else is reported, never destroyed, with the latest commit headline
quoted so the evaluator — owner or agent — can decide in seconds whether to
resume work or clean up. In particular:

- Fresh activity (or dirty working tree) is hands off, unconditionally.
- Uncommitted changes or unpushed commits are never auto-deleted.

## Finishing a task

1. Run `Scripts/test.sh pr` in the clean worktree. This includes lint, Swift
   package tests for CardCore and PKCS11Bridge, the iOS build, and RefineIDTests.
2. Commit on the task branch (subject and body only; strictly no AI attribution trailers)
   and push.
3. Open one pull request for the branch.
4. Squash-merge after the mandatory local push gate passes and any distinct
   required remote checks pass. The Apple build and tests are local gates;
   GitHub does not repeat them for pull requests. The pull request preserves
   the branch history.
5. Remove the worktree (`git worktree remove`), delete the branch, and
   fast-forward local main.

## Out of scope

Hardware and physical test devices are owner-coordinated.
Agents do not arbitrate, reserve, or toggle transports or physical smart cards.

## GitHub verification

`.github/workflows/swift.yml` is manual-only (`workflow_dispatch`). It provides
an optional clean-runner diagnostic build and test run. Pushes and pull
requests do not repeat the mandatory local verification.

Do not require the manual workflow's status for merging. Local hooks remain
mandatory for every commit and push. Local receipts accelerate matching lint
checks; they do not provide independent or tamper-resistant attestation.
