# Rule #1 – PIN codes never travel over any network
- PIN codes (PIN1 and PIN2) never leave the phone when accessed via RAPP.
- RAPP must absolutely deny any attempt to transport PIN codes.
- PIN1 is cached on-device; PIN2 prompts appear only on the phone.

# Rule #2 – Zero PIN and PIN-length logging across all environments
- Never log, trace, display, or format PIN bytes, candidate PIN lengths (e.g. `\(pin.count)`), or development PIN role identifiers in log sinks, audit records, test attachments, or error strings.
- Never commit test PINs or card secrets.

# Rule #3 – Comments describe the code, never its history
- Comments explain what the code does now and the constraints it honors.
  Past bugs, previous implementations, and explanations of what a fix changed
  belong in commit messages, not source comments.

# Rule #4 – Everything the software stores in the keychain lives under `fi.refineid`
- Every keychain service the software creates starts with `fi.refineid`. That prefix is the whole deletable namespace: wiping it forgets every card number, pairing, and credential the app holds, and nothing else.
- That namespace holds software-generated state only. Anything owned by a human stays outside it, so no cleanup can reach it.

- Please No AI attribution spam in commits.
  No `Co-authored-by` / `Signed-off-by` / `Reviewed-by`
  or any AI-naming trailer; subject + body only. 
- Apple uses PascalCase.
- ASCII only in source, UTF-8 only where required.
- No Magic Codes - define everything.
- After a feature commit, install that build on every machine that
  can run it: `Scripts/install-all-devices.sh`. The commit is the
  cheap backup; Mac, the connected iPhone or iPad, and the iPad
  simulator must match it. Do not mix the stamp `Version.xcconfig`
  rewrite into the feature commit.
- Apple deployment goes only through the `Scripts/` entry points:
  device installs via `Scripts/install-ios-development.sh`, store and
  TestFlight work via `Scripts/apple-app-store-connect-release-manager.swift`
  (Swift). Never sign, archive, or export with raw `xcodebuild`, Xcode
  Organizer, or a handwritten sequence, and never pass `DEVELOPMENT_TEAM`
  on the `xcodebuild` command line: the override breaks automatic signing
  and fails with `No Account for Team` even when the certificates are
  on the Mac.
- Reusable agent workflows are plain scripts under `Scripts/`, each with a
  usage header, so any agent of any vendor can discover and run them. Keep
  agent guidance vendor-neutral in this AGENTS.md, not in one vendor's skill
  format.
- Verify from specifications, don't wild guess.
  `Documentation/references.md` indexes which one governs what.
  Cite what a source proves, and say what it does not.
  Where observation contradicts Apple's docs, the recorded
  exchange wins and is cited as observation, not spec.
- The quality gates are mandatory git hooks, not suggestions. Activate
  once per clone: `git config core.hooksPath Scripts/githooks`. Pre-commit
  and pre-push run `Scripts/lint.sh`; `commit-msg` enforces subject and body
  only with zero trailers. Never commit or push with `--no-verify`, never
  disable or work around a gate to land a change, and never leave hooks
  uninstalled. Fix findings instead of dodging them.
- Commit often when compiles and lint is clean. Push when feature is ready.
  Subject and body only: no AI attribution, co-author, sign-off, or review
  trailers.
- One task, one worktree (`~/src/wt/refineid-apple-<topic>`) on one
  `agent/<topic>` branch, one pull request per branch. All agent worktrees
  MUST live strictly under `~/src/wt/`, never loose beside repositories or under `/tmp/`.
  Run `Scripts/agent-housekeeping.sh` when starting and keep the house clean.
  Merge the pull request after mandatory local verification and any distinct
  required remote checks pass, then remove the worktree and branch
  and fast-forward `main`. Full workflow:
  `Documentation/process/agent-worktrees.md`.
- Never poll background commands or set rapid check timers (e.g. 10s-30s).
  When running builds, tests, or async tasks, execute asynchronously and
  wait strictly for system completion notifications.
- Less is more. Terse is better.
- Do not leak personal or private information in commits.
- Never store device UUIDs or UDIDs in version control; discover
  connected hardware and booted simulators dynamically at runtime.
- When stuck, research with fellow AI available.
- If something is not working, it is by default a bug in OUR code (or
  test harness), not a feature of the platform. "Impossible/blocked"
  claims require exchange-level evidence from a clean-slate repro.
- Always test and verify features with automated tests and end-to-end
  verification before handing over to the user. Never claim features work
  without automated verification.

## Commits and integration

- Commits are cheap backups. Make small, focused commits often, without
  asking for permission, once the required commit checks pass.
- Complete the integration without waiting for another instruction: push
  the task branch, open a pull request, and merge it into `main` once the
  required checks pass. Apple build and test checks run locally; the GitHub
  Swift workflow is manual-only and is not a merge requirement. Sync local
  `main` with the merged remote.
  Use squash merges to keep the `main` history linear; do not use merge commits.

## Record deferred findings

- While working, file a GitHub issue in the owning repository for each
  confirmed, actionable defect or quality gap that cannot reasonably be
  fixed within the current task. Filing these issues is authorized; do not
  wait for a separate instruction for each issue.
- Search existing open issues first. Reuse the matching issue and add only
  new, useful evidence instead of creating a duplicate. Group findings only
  when they share a cause and can be resolved by one focused change.
- State the observed behavior, expected behavior, affected repository-relative
  paths, reproduction or inspection evidence, impact, and acceptance checks.
  Distinguish observations from hypotheses and specification requirements.
  Never claim an unexecuted test or hardware operation was verified.
- Keep speculative improvements in working notes until they have a concrete
  problem and useful acceptance criteria. Avoid issue spam and severity claims
  unsupported by evidence.
- Never put credentials, PIN data or candidate lengths, card secrets,
  personal data, private workspace paths, or persistent device identifiers
  in issue text, logs, screenshots, attachments, or reproduction fixtures.
  Report security-sensitive findings through the repository's private
  reporting process; if no safe channel is available, notify the user
  without publishing sensitive details.
- An issue does not excuse a broken gate or incomplete work needed to make
  the current task correct. Fix findings required for the task before handing
  it over; file independently deferred work with a clear scope.
- Link newly filed or reused issues in the task handoff. If issue creation is
  unavailable, preserve a sanitized finding locally and report that it was
  not filed; never silently discard it.
