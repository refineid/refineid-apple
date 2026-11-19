# Testing and Verification Strategy

This document defines the testing philosophy and the tiered verification and release quality gates for RefineID.

## Philosophy: Intent, Integrity, Impact

Trust is the product tests bring. Every test must have **intent**, **integrity**, and **impact**, grounded in empirical software verification and systems safety research:

1. **Integrity — Oracle Strength, Checked Coverage, and Determinism**
   - **Coverage without strong assertions is hollow:** Inozemtseva and Holmes ([inozemtseva2014coverage](references.md#inozemtseva2014coverage)) and Schuler and Zeller ([schuler2011checked](references.md#schuler2011checked)) showed that executing code paths correlates poorly with catching faults unless those paths flow into strict assertions (*checked coverage*). Zhang and Mesbah ([zhang2015assertions](references.md#zhang2015assertions)) confirmed that assertion density and specificity—not raw line execution—drive fault detection.
   - **Flakiness destroys trust:** Luo et al. ([luo2014flaky](references.md#luo2014flaky)) showed that non-deterministic tests train engineers to distrust and ignore failures.
   - **Independent oracles expose implementation assumptions:** Validating outputs with an independent implementation (`Scripts/dss-gate.py` with EU DSS, and shared conformance vectors across Swift and Rust) catches single-implementation habits, while recognizing that shared specification blind spots still require specification review ([knight1986experimental](references.md#knight1986experimental)).
2. **Intent — Specification Traceability & Hazard Constraints**
   - In STPA ([leveson2012engineering](references.md#leveson2012engineering)), testing code against its own structure only proves the code matches itself. A test has intent when it verifies a specification predicate, protocol vector, or STPA controller constraint (`CC-n`)—stating what must hold or never happen independent of how the function is written, with a single clear reason to fail.
3. **Impact — Fault Coupling & Consequence**
   - Just et al. ([just2014mutants](references.md#just2014mutants)) showed that effective tests are coupled to plausible semantic faults at state transitions and boundaries, whereas tautological tests (asserting mocks or trivial wiring) add maintenance cost with near-zero fault sensitivity.
4. **Trust — Calibrated Assurance**
   - In high-assurance engineering, the output of verification is justified confidence (assurance): a passing suite means the guarded invariants hold, and a failing test means a real invariant broke.

## Test frameworks and isolation

Unit and integration tests use Swift Testing (`import Testing`, `@Test`,
`#expect`, and `#require`). XCTest remains the framework for XCUIAutomation
and Apple APIs that require it, such as XCTest performance measurements.
The current XCTest target is `RefineIDUITests`; the framework-policy gate
scans `Tests`, `CardCore/Tests`, and `PKCS11Bridge/Tests` and rejects XCTest
imports in ordinary test sources there. A separate performance-only
target requires an explicit update to that boundary. This follows
[Apple's testing guidance](https://developer.apple.com/documentation/xcode/testing).

Swift Testing schedules tests concurrently. Suites that mutate process-wide
state, swizzle a shared API, or share a credential fixture must coordinate that
resource explicitly; adding `.serialized` to unrelated suites does not
serialize them with one another. Preserve setup, teardown, and asynchronous
completion ownership when migrating a suite.

Assertions must not interpolate secrets or candidate credential lengths,
including on failure. Compute a Boolean before using an introspecting
assertion macro for a secret-bearing comparison, then assert that Boolean
with a generic message. Fixtures, thrown errors, screenshots, and result
attachments must obey the same secrecy rules as production code.

Xcode test plans, test-host isolation, and `.xcresult` artifacts apply to both
frameworks. `RefineIDTests` runs in `RefineIDTestHost`, not the installed app.
UI automation stays in its separate plan and runs inside a headless guest.

## Bounded Apple test processes

`Scripts/RunAppleTests.py` runs only `xcodebuild test`; it is not a build,
signing, archive, or installation entry point. The existing test selectors,
plans, and destinations are passed through unchanged. Derived data remains
inside the current checkout, normally `build/DerivedData`.

Each supervised test process has a 15-minute execution deadline, including its build,
runner initialization, and result finalization. Completion and cancellation
use operating-system notifications rather than process-status polling.
A missed deadline fails with status 124. SIGINT and SIGTERM cancel the run;
ordinary child failures retain their exit status. Cleanup first terminates,
then force-kills after a bounded grace period, only the invocation's private
process group and newly started executables inside its exact derived-data
build-products directory. Preexisting processes and other worktrees are not
cleanup targets. The supervisor never resets global test-manager services,
simulators, or the installed application.

Child stdout and stderr remain visible. Supervisor diagnostics contain no
command arguments, device identifiers, or captured test output. A timeout is
a failed verification, never a retry or a substitute successful result.
`Scripts/TestRunAppleTests.py`, `Scripts/TestCheckTestFrameworks.py`, and
`Scripts/TestTartUITests.py` exercise synthetic processes and isolated source
fixtures during the commit and push tiers.

## Overview of Tiers

| Tier | When | Gate / Tool | Scope & Objectives |
| --- | --- | --- | --- |
| **1. Commit** | Every local commit | `Scripts/test.py commit` (`pre-commit`) | Checks staged whitespace, exercises the quality receipt gate when its files change, runs the testing-tool suites with the framework-policy gate, and runs lint against the exact staged Git tree. |
| **2. Push / PR** | Every local push / PR update | `Scripts/test.py pr` (`pre-push`) | Requires a clean checkout and checks local gate behavior, lint, CardCore and PKCS11Bridge Swift packages, iOS compilation, `RefineIDTests` on macOS and the iOS simulator, and `CardCoreTests` with `RappIntegrationTests` in its own invocation. |
| **3. TestFlight** | Staging candidate builds | `Scripts/apple-app-store-connect-release-manager.swift candidate` | Verifies archive export, provisioning profiles, entitlements, and diagnostic exclusions. Real-device smoke tests on iPhone (NFC card priming) and Mac (USB CCID reader). |
| **4. App Store** | Public release production | `Scripts/test.py pr` + `inspect-archive` | Runs the PR floor. macOS UI and device compliance checks remain separate gates. |

---

## 1. Commit Tier (Local Formatting & Whitespace Control)

- **Script**: `Scripts/test.py commit` (automatically driven by `Scripts/githooks/pre-commit`).
- **Formatting Tool**: Run `Scripts/format.py` (or `Scripts/format.py --staged`) to format modified Swift files in-place using `swift-format` and Python helper scripts using `ruff format`.
- **Whitespace Check**: `git diff --cached --check` prevents committing trailing whitespace, spaces before tabs, or spurious carriage returns.
- **Lint Snapshot**: `Scripts/QualityReceipt.py lint-index` materializes Git blobs from the staged tree and runs `Scripts/lint.py` (`swift-format`, SwiftLint, `ruff format --check`, `ruff check`, `mypy --strict`, `swiftc -typecheck -warnings-as-errors` of every Swift script under `Scripts/`, and the suppression register) in that snapshot. A successful local receipt can skip the same lint run at push when the tree and toolchain still match. Receipts are a local speed optimization, never proof accepted by GitHub.
- **Rule**: Diffs must remain focused and minimal. Zero noise diffs or accidental whitespace reformats across unrelated lines. Xcode builds rewrite the string catalogs: commit only the real extracted keys and discard junk diffs (empty keys, stale marks).

## 2. Push & PR Tier (Functional Verification)

- **Script**: `Scripts/test.py pr` (automatically driven by `Scripts/githooks/pre-push`).
- **Verification Steps**:
  1. **Gate Tests**: `python3 -B Scripts/TestQualityReceipt.py` checks exact snapshots, tool changes, failures, corrupted receipts, and concurrent callers.
  2. **Lint Gate**: `Scripts/QualityReceipt.py lint-head` runs `Scripts/lint.py` against the clean `HEAD` tree. The receipt includes the tree and the selected toolchain. GitHub build and test verification is manual-only; it is not repeated on pushes or pull requests.
  3. **Package Build & Tests**: Runs `swift build --package-path CardCore --scratch-path build/spm/CardCore --build-tests`, `swift test --package-path CardCore --scratch-path build/spm/CardCore`, and `swift test --package-path PKCS11Bridge --scratch-path build/spm/PKCS11Bridge`.
  4. **Multi-Platform Build**: Verifies iOS compilation using the generic iOS destination.
  5. **App Unit Tests**: Executes `RefineIDTests` via `python3 Scripts/RunAppleTests.py -scheme RefineID -destination 'platform=macOS' -only-testing:RefineIDTests`.
  6. **Core Tests**: Executes `CardCoreTests` without `RappIntegrationTests`, then `CardCoreTests/RappIntegrationTests` alone, each in its own supervised `xcodebuild test` invocation on macOS.
  7. **Independent Validation**: `Scripts/dss-gate.py` has the EU DSS validator judge what the Swift signers write (see [Independent validation gate](#independent-validation-gate)).
  8. **Checkout Integrity**: Requires every updated push ref to name `HEAD`, rejects dirty trees, and rechecks the commit after all steps.

### Independent validation gate

Our own tests check what our code means to write; the gate asks the EU
DSS library, the European Commission's reference validator and the one
behind DVV's validation service, what it did write. A release build
saves only a long-term archival signature, so the gate requires:

| Document | DSS signature format | DSS indication | Container |
| --- | --- | --- | --- |
| `swift-pades.pdf` | `PAdES-BASELINE-LTA` | `TOTAL_PASSED` | none |
| `swift-asic-e.asice` | `XAdES-BASELINE-LTA` | `TOTAL_PASSED` | `ASiC-E` |

- **Run**: `Scripts/dss-gate.py`. Step 11 of `Scripts/test.py pr` runs it.
- **Export**: `RefineIDTests/DssGateExportTests` stands in only for the
  card, with a generated RSA-2048 key. From the card's answer on it runs
  the app's own stages: `TimestampClient`, `DocumentSigner.longTerm` and
  `AsicSigner.evidenced`, over `SigningNetwork`. `DssGateUrlProtocol`
  answers every request in memory from `DssGateAuthorities` (a CA, its
  CRL at a numeric public address, and `DebugTimestampAuthority` for the
  configured timestamp authority), installed in each ephemeral session
  configuration for the test's duration. The CA is seeded into
  `TrustRootsCache` as a card's issuer would be. The files land in the
  test host's temporary directory, `RefineIDDssGate`.
- **Judge**: `Scripts/dss-gate/DssGate.java` on DSS 6.5.1, which trusts
  only the exported CA and timestamp authority certificates, loads no
  trusted list and has every online source off. The jars are pinned by
  SHA-256 in `Scripts/dss-gate/dss.lock`, fetched once from Maven Central
  into `~/.cache/refineid/dss-gate` (or `REFINEID_DSS_CACHE`); after that
  the gate runs offline. It needs a JDK 17 or later (`JAVA_HOME`,
  `/usr/libexec/java_home`, or Homebrew's `openjdk`). The validator and
  the pins are refineid-core's (`tools/dss-gate/`), and the two
  repositories move to a new DSS release together.
- **A failure** prints DSS's whole report for the document. Do not lower
  an expectation to make the gate pass; the signer is what is wrong.

## 3. TestFlight Tier (Staging on Physical Hardware)

- **CLI**: `Scripts/apple-app-store-connect-release-manager.swift candidate [ios|macos|all] [--upload]`.
- **Focus**:
  - Validates `TestFlight` Xcode configuration (excluding internal diagnostic symbols).
  - Ensures clean working tree before archiving.
  - Physical smoke testing on real hardware:
    - iPhone NFC antenna positioning and live countdown sheet.
    - Mac USB smart card reader arbitration and `ctkd` token minting.
  - DVV test cards chain to DVV TEST Root CA G3 RSA or ECC, which macOS
    does not trust, and Safari offers a card identity only when its chain
    reaches a trusted root. `Scripts/trust-dvv-test-roots.py install` downloads the
    test roots and the G5R/G5E issuing CAs from DVV, checks each against the
    SHA-256 on DVV's test CA page, and adds them to the System keychain
    (`install`); `uninstall` removes their trust and deletes them again.
    On an iPhone, the roots are installed as a profile from
    `http://proxy.fineid.fi/ca/dvvtest3rc.crt` (and `dvvtest3ec.crt`) and
    given full trust in Certificate Trust Settings.

## 4. App Store Public Release Tier (Exhaustive Assurance)

- **CLI**: `Scripts/test.py pr` and `Scripts/apple-app-store-connect-release-manager.swift inspect-archive`.
- **Focus**:
  - The PR tier: package tests, the iOS build, `RefineIDTests`, and `CardCoreTests` with the RAPP loopback suite in its own invocation.
  - macOS UI checks run through `Scripts/test.py macos-mvp`; device checks run through the documented hardware workflow.
  - Strict hardware protocol testing:
    - PACE establishment with CAN, anti-tamper penalty delay recovery (`FIA_AFL.1/PACE`).
    - PIN1 authentication and PIN2 qualified document signature operations.
    - Premature card tear / departure handling.
    - Review notes, export compliance declarations, and App Store metadata verification.

## 5. Headless & Background UI Testing

- **Fast-Loop Headless Testing (Default)**: `RefineID.xctestplan`, the scheme's default test plan, holds `CardCoreTests` and `RefineIDTests` only. Running tests via `xcodebuild test -scheme RefineID` or pressing ⌘U in Xcode executes in-memory unit and integration tests without opening windows, stealing focus, or interrupting workstation tasks.
- **UI test plan**: `RefineIDUITests.xctestplan` holds `RefineIDUITests`. `Scripts/test.py macos-mvp` selects its Mac MVP suite through the headless Tart workflow on the `macos-ci` VM; a differently named VM needs a direct `Scripts/test-ui-tart.py` call. UI tests open windows and take the keyboard and mouse, so they never run on the workstation's screen. Direct UI selection through the supervisor requires the internal guest marker described below.
- **Gate scope**: the pre-commit hook runs `Scripts/test.py commit` (staged lint and fast gate-tooling checks) and the pre-push hook runs `Scripts/test.py pr` (lint, CardCore and PKCS11Bridge package tests, the iOS build, `RefineIDTests` on macOS and on the iOS simulator, and the DSS gate). Neither runs a UI test. The simulator step fails with a named message when no iPhone simulator is installed instead of a parser error.
- **iPad hardware**: a physical iPad cannot be test-driven under the project's Xcode. Build for it and install and launch with `ios-deploy`; never plan a hardware-iPad UI test. Simulator iPad UI tests are unaffected.
- **Isolated Headless UI Tests with Tart**: When full end-to-end `RefineIDUITests` must be verified locally without screen-stealing, run them inside a headless macOS virtual machine using Tart:
  ```bash
  Scripts/test-ui-tart.py [VM_NAME] [all|macos-mvp]
  ```
  Use an existing, stopped VM with macOS 26 or later, the project's current
  Xcode SDK/toolchain, Python 3, and the Tart guest agent. The script does not
  download an image or alter host automation permissions. Missing setup fails
  before any UI test starts. It refuses a running or suspended VM.

  Tart runs with `--no-graphics`. Its supported `ip --resolver agent --wait`
  operation provides a bounded readiness wait; the address is consumed without
  being displayed. The internal `REFINEID_UI_TEST_GUEST=tart` marker tells the
  entry points the command already runs inside the guest, so `macos-mvp`
  executes there instead of recursively launching another VM. The marker is a
  host-settable escape hatch, so the Tart entry point stays the way to run UI
  tests. Guest commands use the same supervised
  test entry point and worktree-local derived data. Cleanup stops only the Tart
  processes this invocation launched, never an existing VM by name.
  [Tart command sources](https://github.com/cirruslabs/tart/tree/main/Sources/tart/Commands)
  define these options and the guest-agent requirement.

## Optional GitHub diagnostic run

The Swift workflow runs only when explicitly dispatched. The mandatory local
commit and push hooks enforce the normal quality floor. A manual GitHub run
is available for investigating clean-runner differences and is not a merge
requirement.
