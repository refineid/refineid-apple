# Testing and Verification Strategy

This document defines the tiered testing, formatting, and release quality gates for RefineID.

## Overview of Tiers

| Tier | When | Gate / Tool | Scope & Objectives |
| --- | --- | --- | --- |
| **1. Commit** | Every local commit | `Scripts/test.sh commit` (`pre-commit`) | Forbids trailing whitespace & whitespace noise via `git diff --cached --check`. Enforces formatting layout via `swift-format` and defect checks via `Scripts/lint.sh`. |
| **2. Push / PR** | Every push / PR update | `Scripts/test.sh pr` (`pre-push`) | Runs lint gate, verifies iOS and macOS compilation cleanly (`xcodebuild`), and executes the fast unit test suite (`RefineIDTests`). Guarantees no non-functional code reaches a PR. |
| **3. TestFlight** | Staging candidate builds | `Scripts/apple-app-store-connect-release-manager.swift candidate` | Verifies archive export, provisioning profiles, entitlements, and diagnostic exclusions. Real-device smoke tests on iPhone (NFC card priming) and Mac (USB CCID reader). |
| **4. App Store** | Public release production | `Scripts/test.sh full` + `inspect-archive` | Runs full unit & crypto suites across isolated targets (preventing Xcode runner stalls on async loopbacks). Completes physical card compliance checklist and archive inspections. |

---

## 1. Commit Tier (Local Formatting & Whitespace Control)

- **Script**: `Scripts/test.sh commit` (automatically driven by `Scripts/githooks/pre-commit`).
- **Formatting Tool**: Run `Scripts/format.sh` (or `Scripts/format.sh --staged`) to format modified Swift files in-place using `swift-format`.
- **Whitespace Check**: `git diff --cached --check` prevents committing trailing whitespace, spaces before tabs, or spurious carriage returns.
- **Rule**: Diffs must remain focused and minimal. Zero noise diffs or accidental whitespace reformats across unrelated lines.

## 2. Push & PR Tier (Functional Verification)

- **Script**: `Scripts/test.sh pr` (automatically driven by `Scripts/githooks/pre-push`).
- **Verification Steps**:
  1. **Lint Gate**: `Scripts/lint.sh` (`swift-format lint --strict`, `swiftlint lint --baseline .swiftlint-baseline.json`, and suppression lock validation).
  2. **Multi-Platform Build**: Verifies that both macOS and iOS targets compile without warnings or missing platform cases (e.g. exhaustive `switch` statements across OS-conditional models).
  3. **Targeted Unit Tests**: Executes `RefineIDTests` via `xcodebuild test -scheme RefineID -destination 'platform=macOS' -only-testing:RefineIDTests`. Completes in ~6 seconds.
  4. **Loopback Isolation**: Does *not* invoke unbounded `xcodebuild test -scheme RefineID`, avoiding known Xcode test finalization hangs on local relay sockets.

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
  - Full automated regression test suites executed across dedicated, isolated target invocations.
  - Strict hardware protocol testing:
    - PACE establishment with CAN, anti-tamper penalty delay recovery (`FIA_AFL.1/PACE`).
    - PIN1 authentication and PIN2 qualified document signature operations.
    - Premature card tear / departure handling.
  - Review notes, export compliance declarations, and App Store metadata verification.
