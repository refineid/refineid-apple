#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Tiered test and quality gate runner for RefineID.
#
# Usage:
#   Scripts/test.sh           # default: runs PR tier (lint, package tests, iOS build, targeted unit tests)
#   Scripts/test.sh commit    # fast pre-commit tier (whitespace check + lint)
#   Scripts/test.sh pr        # PR / pre-push tier (lint, package tests, iOS build, RefineIDTests)
#   Scripts/test.sh nfc-signing # retained-field lifecycle and PACE regression tests
#   Scripts/test.sh full      # release regression tier (PR checks plus core and isolated RAPP tests)
#   Scripts/test.sh macos-mvp # localized local-card UI checks

set -euo pipefail
cd "$(dirname "$0")/.."

mode="${1:-pr}"

step() {
  printf '\n=== %s ===\n' "$1"
}

fail() {
  printf '\nTEST GATE FAILED: %s\n' "$1" >&2
  exit 1
}

# Gate builds go into this checkout's own build directory, which leaves
# with the worktree. Every app bundle the gate built is unregistered from
# Launch Services on exit: a registered build product carrying the app's
# bundle identifier competes with /Applications/RefineID.app for the
# app's privacy permissions.
derived_data="build/DerivedData"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

unregister_gate_builds() {
  local products="${derived_data}/Build/Products"
  [[ -d "${products}" && -x "${lsregister}" ]] || return 0
  find "${products}" -maxdepth 2 -name '*.app' -type d -print0 \
    | xargs -0 -n 1 "${lsregister}" -u 2>/dev/null || true
}
trap unregister_gate_builds EXIT

case "${mode}" in
  commit)
    if ! git diff --cached --quiet -- Scripts/QualityReceipt.py Scripts/TestQualityReceipt.py; then
      step "Checking quality receipt gate behavior"
      python3 -B Scripts/TestQualityReceipt.py \
        || fail "Quality receipt gate tests failed."
    fi

    step "Checking for whitespace errors in staged changes"
    if ! git diff --cached --check; then
      fail "Staged changes contain trailing whitespace or whitespace errors."
    fi

    step "Running lint and layout gate (Scripts/lint.sh)"
    Scripts/QualityReceipt.py lint-index || fail "Lint gate failed."
    printf 'Commit gate passed.\n'
    ;;

  pr)
    Scripts/QualityReceipt.py verify-clean-head \
      || fail "Push checks require a clean checkout."
    checked_head="$(git rev-parse HEAD)"
    checked_tree="$(git rev-parse 'HEAD^{tree}')"

    step "1. Testing exact-tree lint receipts"
    python3 -B Scripts/TestQualityReceipt.py \
      || fail "Quality receipt gate tests failed."

    step "2. Running lint and layout gate for HEAD"
    Scripts/QualityReceipt.py lint-head || fail "Lint gate failed."

    step "3. Running CardCore package tests"
    swift test --package-path CardCore \
      || fail "CardCore package tests failed."

    step "4. Running PKCS11Bridge package tests"
    swift test --package-path PKCS11Bridge \
      || fail "PKCS11Bridge package tests failed."

    step "5. Verifying iOS compilation"
    xcodebuild -derivedDataPath "${derived_data}" -scheme RefineID -destination 'generic/platform=iOS' -quiet build CODE_SIGNING_ALLOWED=NO \
      || fail "iOS build failed. Check for platform-conditional compilation issues."

    step "6. Running unit test suite (RefineIDTests on macOS)"
    xcodebuild test -derivedDataPath "${derived_data}" -scheme RefineID -destination 'platform=macOS' -only-testing:RefineIDTests -quiet \
      || fail "Unit tests failed."

    Scripts/QualityReceipt.py verify-head "${checked_head}" "${checked_tree}" \
      || fail "The checked-out commit changed during push checks."

    printf '\nPR gate passed: Lint, package tests, iOS compilation, and app unit tests pass.\n'
    ;;

  nfc-signing)
    step "Testing retained NFC field lifecycle and PACE"
    xcodebuild test -derivedDataPath "${derived_data}" -scheme RefineID -destination 'platform=macOS' \
      -only-testing:CardCoreTests/HeldCardSessionTests \
      -only-testing:CardCoreTests/PaceEstablishmentTests \
      -only-testing:CardCoreTests/CommandApduTests \
      -only-testing:CardCoreTests/CardExchangeTraceTests \
      -only-testing:CardCoreTests/CardExchangeProgressTests \
      -only-testing:CardCoreTests/OnDemandPinExperimentTests \
      -only-testing:CardCoreTests/OnDemandPinPublicationTests \
      -only-testing:CardCoreTests/SecureMessagingChannelTests \
      -only-testing:RefineIDTests/SmartCardTransmitTests -quiet \
      || fail "NFC signing regression tests failed."
    ;;

  macos-mvp)
    step "Checking the macOS MVP user interface"
    result_path="build/macos-mvp-ui-$(date -u +%Y%m%dT%H%M%SZ).xcresult"
    xcodebuild test -derivedDataPath "${derived_data}" -scheme RefineID -testPlan RefineIDUITests -destination 'platform=macOS' \
      -only-testing:RefineIDUITests/MacMvpUITests \
      -resultBundlePath "${result_path}" -quiet \
      || fail "macOS MVP UI checks failed."
    ;;

  full|release)
    step "1. Running PR gate checks"
    "$0" pr

    step "2. Running isolated CardCore crypto & protocol tests"
    xcodebuild test -derivedDataPath "${derived_data}" -scheme RefineID -destination 'platform=macOS' -only-testing:CardCoreTests -skip-testing:CardCoreTests/RappIntegrationTests -quiet \
      || fail "CardCore tests failed."

    step "3. Running isolated RAPP integration tests"
    xcodebuild test -derivedDataPath "${derived_data}" -scheme RefineID -destination 'platform=macOS' -only-testing:CardCoreTests/RappIntegrationTests -quiet \
      || fail "RAPP integration tests failed."

    printf '\nAutomated release regression suites passed.\n'
    ;;

  *)
    printf 'Usage: %s [commit|pr|full|nfc-signing|macos-mvp]\n' "$0" >&2
    exit 2
    ;;
esac
