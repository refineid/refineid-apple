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

# Rule #5 – Development builds make every error visible
- Every failure path (refusal, transport close, card or reader error, failed operation) reports to `DevErrorLog` inside `#if DEBUG`, from the app and from both token extensions.
- A development build shows the errors live (the Errors window on the Mac, the error pill and the Diagnostics screen on iPhone and iPad) and writes each one to the unified log, subsystem `fi.refineid.ReFineID`, category `errors`.
- A message names the event and its cause only: never a PIN or its length (Rule #2), a card access number, a name, certificate content, a device name or a serial number.
- TestFlight and Release builds compile none of it and log nothing.

- Please No AI attribution spam in commits.
  No `Co-authored-by` / `Signed-off-by` / `Reviewed-by`
  or any AI-naming trailer; subject + body only. 
- Apple uses PascalCase.
- ASCII only in source, UTF-8 only where required.
- No Magic Codes - define everything (see [Types and numbers](#types-and-numbers)).
- After a feature commit, install that build on every machine that
  can run it: `Scripts/apple-app-store-connect-release-manager.swift
  install-devices`. The commit is the cheap backup; the Mac, every
  connected iPhone or iPad, and the iPad simulator must match it. The
  install stamps the version for its build and restores
  `Version.xcconfig` afterwards, so no stamp reaches a commit.
- Apple builds, signing, provisioning and installs go only through
  `Scripts/apple-app-store-connect-release-manager.swift`; no shell
  scripts for them. That covers device and Mac installs (`install-*`),
  version stamps (`stamp`), and store and TestFlight work. Signed builds
  use the App Store Connect API key, so capabilities named in the
  entitlements are provisioned without an Apple ID in Xcode. Never sign,
  archive, or export with raw `xcodebuild`, Xcode
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
- `RefineIDTests` run in `RefineIDTestHost`, the app's sources under their
  own bundle identifier, so a test run never shares privacy permissions,
  keychain or single-instance identity with the installed app.
- Commit often when compiles and lint is clean. Push when feature is ready.
  Subject and body only: no AI attribution, co-author, sign-off, or review
  trailers.
- Reading does not require a worktree; writing does. The main checkout is
  never edited directly. Before writing code or modifying files for any task,
  create a dedicated git worktree strictly under `../wt/`
  (`../wt/refineid-apple-<topic>`) on a `<topic>` branch. Never
  work directly on `main` or modify files in the main checkout.
- All worktrees MUST live strictly under `../wt/`, never loose beside
  repositories or under `/tmp/`.
- Never put a git worktree under `/tmp`. It is cleared on reboot and takes the
  branch's only checkout with it.
- One task, one worktree, one branch (`<topic>`), one pull request per branch.
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

## Rules live here, not in an agent's memory

Every rule, decision and durable finding an agent should remember goes
into this repository: a working rule into this file, a design rule into
`Documentation/design/`, a defect into an issue. An agent's own memory
holds pointers at most. A rule that lives only in one agent's memory
binds nobody else and is lost with that agent: agent-local memory is the
modern vendor lock-in.

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

## Types and numbers

Two rules from refineid-core bind this repository too: refinement types
and no magic numbers. Define everything.

Refinement types:

- Read
  [refinement-types.md](https://github.com/refineid/refineid-core/blob/main/doc/architecture/refinement-types.md)
  and its case study before designing or reviewing a type.
- A type is a predicate: input from the wire, the card, the platform or
  storage crosses one border, with one constructor that checks every
  specification predicate once, and downstream code trusts the result.
- Every byte is meaning, transit or citation. Nothing raw sits beside a
  typed value, and no byte-like parameter stands where a nominal type
  belongs.
- The policy's review questions are the checklist for writing and review.

No magic numbers:

- No anonymous numeric literal in production code or ordinary tests. Every
  protocol code, status word, tag, size, offset, limit, timeout and count
  is a named constant or derives from one. Writing a hexadecimal value in
  decimal does not name its meaning.
- No hand-typed hexadecimal arrays, not even in tests. A wire buffer or an
  expected fixture is assembled from the same named constants the
  serializer uses; a synthetic test payload is an ASCII string.
- A raw wire value lives only in the initializer of a truthful named
  constant, or in one named constant holding an opaque, externally
  specified block, such as a known-answer vector, a registered identifier
  or an object identifier, with a citation to its source.

## STPA in design

Every design includes a short System-Theoretic Process Analysis (STPA),
sized to the change. [stpa-rapp.md](https://github.com/refineid/refineid-core/blob/main/doc/security/stpa-rapp.md) is the worked example and the
record for RAPP and its applications.

- Ground the analysis in the losses (L-n) and hazards (H-n) the record
  already names. Add a loss only when a real stakeholder could suffer it
  and no recorded loss covers it, and a hazard only for a real system
  state that leads to a loss.
- Do not invent imaginary losses, hazards or threats to fill the method.
  A few real ones beat a long list.
- Describe the control structure the change touches: the controllers,
  their control actions, and the feedback each gets. Look first for
  missing, late or misleading feedback; a controller acting on a stale
  process model is the usual cause of an unsafe control action.
- List the unsafe control actions (UCA-n) the affected controllers could
  issue or fail to issue, the hazards each leads to, and the controller
  constraints (CC-n) the design enforces against them.
- A small change records its analysis in the pull request, and a change
  with no control action or feedback to analyse says so in one line. A
  change to the control structure updates the STPA record that covers it.

## No backwards compatibility

- When code, a script, a command, an API, a file format or a setting is
  replaced, remove the old one in the same change. Do not leave
  compatibility wrappers, deprecated aliases, forwarding shims, fallback
  readers or migration paths behind.
- Update every caller, hook, CI job and document to the replacement in that
  same change instead of keeping the old entry point alive for them.

## Independent review

- Before a pull request merges, have its diff reviewed by a model from a
  different family than the one that wrote it. Any CLI that runs a model
  headless will do; take the strongest model it offers that day, and add a
  second one for protocol, cryptography or state-machine changes.
- Run the reviewer in a sandbox and plan mode, from an empty directory,
  with the diff pasted into the prompt and no tool use. Frame the request as
  a code review from the project's author.
- Check every finding against the code. Fix the real ones and list the
  rejected ones, with the reason, in the pull request description.

## Working method

Read [Documentation/process/working-method.md](Documentation/process/working-method.md) before starting: the roles (front agent, implementation agents), what a brief contains, the feedback loops, and which documentation is kept. The same file is in every RefineID repository.
