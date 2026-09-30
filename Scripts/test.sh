#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Tiered test and quality gate runner for RefineID.
#
# Usage:
#   Scripts/test.sh           # default: runs PR tier (lint, iOS/macOS build, targeted unit tests)
#   Scripts/test.sh commit    # fast pre-commit tier (whitespace check + lint)
#   Scripts/test.sh pr        # PR / pre-push tier (lint, dual-platform build, RefineIDTests)
#   Scripts/test.sh full      # release tier (runs all test suites in isolated invocations)
#   Scripts/test.sh macos-mvp # localized local-card UI and excluded-service checks

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

case "${mode}" in
  commit)
    step "Checking for whitespace errors in staged changes"
    if ! git diff --cached --check; then
      fail "Staged changes contain trailing whitespace or whitespace errors."
    fi

    step "Running lint and layout gate (Scripts/lint.sh)"
    Scripts/lint.sh || fail "Lint gate failed."
    printf 'Commit gate passed.\n'
    ;;

  pr)
    step "1. Running lint and layout gate (Scripts/lint.sh)"
    Scripts/lint.sh || fail "Lint gate failed."

    step "2. Verifying iOS compilation"
    xcodebuild -scheme RefineID -destination 'generic/platform=iOS' -quiet build CODE_SIGNING_ALLOWED=NO \
      || fail "iOS build failed. Check for platform-conditional compilation issues."

    step "3. Running unit test suite (RefineIDTests on macOS)"
    xcodebuild test -scheme RefineID -destination 'platform=macOS' -only-testing:RefineIDTests -quiet \
      || fail "Unit tests failed."

    printf '\nPR gate passed: Code is properly formatted, builds on both platforms, and unit tests pass.\n'
    ;;

  macos-mvp)
    step "Checking the macOS MVP user interface"
    result_path="build/macos-mvp-ui-$(date -u +%Y%m%dT%H%M%SZ).xcresult"
    xcodebuild test -scheme RefineID -destination 'platform=macOS' \
      -only-testing:RefineIDUITests/MacMvpUITests \
      -only-testing:RefineIDUITests/ScsSettingsUITests \
      -resultBundlePath "${result_path}" -quiet \
      || fail "macOS MVP UI checks failed."
    ;;

  full|release)
    step "1. Running PR gate checks"
    "$0" pr

    step "2. Running isolated CardCore crypto & protocol tests"
    # Runs CardCore tests excluding heavy loopbacks that trigger Xcode runner hang
    xcodebuild test -scheme RefineID -destination 'platform=macOS' -only-testing:CardCoreTests -skip-testing:CardCoreTests/RappIntegrationTests -quiet \
      || fail "CardCore tests failed."

    printf '\nFull release test suite passed.\n'
    ;;

  *)
    printf 'Usage: %s [commit|pr|full|macos-mvp]\n' "$0" >&2
    exit 2
    ;;
esac
