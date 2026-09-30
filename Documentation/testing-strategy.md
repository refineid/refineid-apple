# Testing and Verification Strategy

This document defines the tiered testing, formatting, and release quality gates for RefineID.

## Overview of Tiers

| Tier | When | Gate / Tool | Scope & Objectives |
| --- | --- | --- | --- |
| **1. Commit** | Every local commit | `Scripts/test.sh commit` (`pre-commit`) | Checks staged whitespace, exercises the quality receipt gate when its files change, and runs lint against the exact staged Git tree. |
| **2. Push / PR** | Every local push / PR update | `Scripts/test.sh pr` (`pre-push`) | Requires a clean checkout and checks local gate behavior, lint, CardCore and PKCS11Bridge Swift packages, iOS compilation, and `RefineIDTests`. |
| **3. TestFlight** | Staging candidate builds | `Scripts/apple-app-store-connect-release-manager.swift candidate` | Verifies archive export, provisioning profiles, entitlements, and diagnostic exclusions. Real-device smoke tests on iPhone (NFC card priming) and Mac (USB CCID reader). |
| **4. App Store** | Public release production | `Scripts/test.sh full` + `inspect-archive` | Runs the PR floor, CardCore tests, and isolated RAPP integration tests. macOS UI and device compliance checks remain separate gates. |

---

## 1. Commit Tier (Local Formatting & Whitespace Control)

- **Script**: `Scripts/test.sh commit` (automatically driven by `Scripts/githooks/pre-commit`).
- **Formatting Tool**: Run `Scripts/format.sh` (or `Scripts/format.sh --staged`) to format modified Swift files in-place using `swift-format`.
- **Whitespace Check**: `git diff --cached --check` prevents committing trailing whitespace, spaces before tabs, or spurious carriage returns.
- **Lint Snapshot**: `Scripts/QualityReceipt.py lint-index` materializes Git blobs from the staged tree and runs `Scripts/lint.sh` in that snapshot. A successful local receipt can skip the same lint run at push when the tree and toolchain still match. Receipts are a local speed optimization, never proof accepted by GitHub.
- **Rule**: Diffs must remain focused and minimal. Zero noise diffs or accidental whitespace reformats across unrelated lines.

## 2. Push & PR Tier (Functional Verification)

- **Script**: `Scripts/test.sh pr` (automatically driven by `Scripts/githooks/pre-push`).
- **Verification Steps**:
  1. **Gate Tests**: `python3 -B Scripts/TestQualityReceipt.py` checks exact snapshots, tool changes, failures, corrupted receipts, and concurrent callers.
  2. **Lint Gate**: `Scripts/QualityReceipt.py lint-head` runs `Scripts/lint.sh` against the clean `HEAD` tree. The receipt includes the tree and the selected toolchain. GitHub build and test verification is manual-only; it is not repeated on pushes or pull requests.
  3. **Package Tests**: Runs `swift test --package-path CardCore` and `swift test --package-path PKCS11Bridge`.
  4. **Multi-Platform Build**: Verifies iOS compilation using the generic iOS destination.
  5. **Targeted Unit Tests**: Executes `RefineIDTests` via `xcodebuild test -scheme RefineID -destination 'platform=macOS' -only-testing:RefineIDTests`.
  6. **Checkout Integrity**: Requires every updated push ref to name `HEAD`, rejects dirty trees, and rechecks the commit after all steps.

## 3. TestFlight Tier (Staging on Physical Hardware)

- **CLI**: `Scripts/apple-app-store-connect-release-manager.swift candidate [ios|macos|all] [--upload]`.
- **Focus**:
  - Validates `TestFlight` Xcode configuration (excluding internal diagnostic symbols).
  - Ensures clean working tree before archiving.
  - Physical smoke testing on real hardware:
    - iPhone NFC antenna positioning and live countdown sheet.
    - Mac USB smart card reader arbitration and `ctkd` token minting.

## 4. App Store Public Release Tier (Exhaustive Assurance)

- **CLI**: `Scripts/test.sh full` and `Scripts/apple-app-store-connect-release-manager.swift inspect-archive`.
- **Focus**:
  - Package tests, the core Xcode test target, and the targeted app unit tests. The RAPP loopback suite runs in an isolated invocation.
  - macOS UI checks run through `Scripts/test.sh macos-mvp`; device checks run through the documented hardware workflow.
  - Strict hardware protocol testing:
    - PACE establishment with CAN, anti-tamper penalty delay recovery (`FIA_AFL.1/PACE`).
    - PIN1 authentication and PIN2 qualified document signature operations.
    - Premature card tear / departure handling.
  - Review notes, export compliance declarations, and App Store metadata verification.

## Optional GitHub diagnostic run

The Swift workflow runs only when explicitly dispatched. The mandatory local
commit and push hooks enforce the normal quality floor. A manual GitHub run
is available for investigating clean-runner differences and is not a merge
requirement.
