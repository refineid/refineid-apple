#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Tiered test and quality gate runner for RefineID.
#
# Usage:
#   Scripts/test.sh                # the PR tier, the same as `Scripts/test.sh pr`
#   Scripts/test.sh commit         # fast pre-commit tier (whitespace check + lint)
#   Scripts/test.sh pr             # PR / pre-push tier (lint, package tests, iOS build,
#                                  #   RefineIDTests on macOS and iOS, CardCoreTests, DSS gate)
#   Scripts/test.sh nfc-signing    # retained-field lifecycle and PACE regression tests
#   Scripts/test.sh macos-mvp      # localized local-card UI checks
#   Scripts/test.sh plan <tier>    # print each step and its resolved command, run none
#   Scripts/test.sh --help
#
# Each tier is a list of step records, so a suite is named once and the same
# list drives both the run and `plan`:
#
#   title | kind | destination | reason | argument...
#
# kind is `command` (run the arguments), `swift` (`swift test --package-path`),
# `test` (`xcodebuild test`) or `build` (`xcodebuild build`). destination is
# `macos`, `ios` or `simulator` for the xcodebuild kinds and empty for the
# others. reason is the line the gate prints when the step fails.
#
# `plan` prints a tier's steps with their commands resolved and executes
# none of them. A value the run resolves later — the simulator's name, HEAD's
# tree, a result bundle's path — prints as a placeholder. The tests read the
# plan to assert a suite is in the right tier instead of reading this file's
# text, and not running anything there keeps the plan free of Xcode and Git.

set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  printf '%s\n' \
    'Usage: Scripts/test.sh [commit|pr|nfc-signing|macos-mvp]' \
    '       Scripts/test.sh plan [commit|pr|nfc-signing|macos-mvp]'
}

step() {
  printf '\n=== %s ===\n' "$1"
}

fail() {
  printf '\nTEST GATE FAILED: %s\n' "$1" >&2
  exit 1
}

# The name of the first available iPhone simulator, read from the JSON on
# stdin, or a sentence saying none is installed.
first_iphone_simulator() {
  python3 -c '
import json, sys

for runtime in json.load(sys.stdin)["devices"].values():
    for device in runtime:
        if "iPhone" in device["name"]:
            print(device["name"])
            raise SystemExit

raise SystemExit("no iPhone simulator is installed")
'
}

# Gate builds go into this checkout's own build directory, which leaves
# with the worktree. Every app bundle the gate built is unregistered from
# Launch Services on exit: a registered build product carrying the app's
# bundle identifier competes with /Applications/RefineID.app for the
# app's privacy permissions.
derived_data="build/DerivedData"
result_bundle=""
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

unregister_gate_builds() {
  local products="${derived_data}/Build/Products"
  [[ -d "${products}" && -x "${lsregister}" ]] || return 0
  find "${products}" -maxdepth 2 -name '*.app' -type d -print0 \
    | xargs -0 -n 1 "${lsregister}" -u 2>/dev/null || true
}

plan=0
if [[ "${1:-}" == "plan" || "${1:-}" == "--plan" ]]; then
  plan=1
  shift
fi
mode="${1:-pr}"

step_command=()
fields=()
resolved_destination=""
simulator_name=""
simulator_listed=0

# Sets resolved_destination for a step's destination field. `plan` answers
# with a placeholder instead of asking simctl which simulators exist, so
# printing a plan never depends on the installed platforms.
resolve_destination() {
  resolved_destination=""
  case "$1" in
    macos) resolved_destination="platform=macOS" ;;
    ios) resolved_destination="generic/platform=iOS" ;;
    simulator)
      if [[ ${plan} -eq 1 ]]; then
        resolved_destination="platform=iOS Simulator,name=<first available iPhone>"
        return 0
      fi
      if [[ ${simulator_listed} -eq 0 ]]; then
        simulator_listed=1
        simulator_name="$(xcrun simctl list devices available -j | first_iphone_simulator)" \
          || simulator_name=""
      fi
      [[ -n ${simulator_name} ]] \
        || fail "No iPhone simulator is available to run RefineIDTests. Install one in Xcode's Settings > Platforms, or run this tier on a Mac that has one."
      resolved_destination="platform=iOS Simulator,name=${simulator_name}"
      ;;
    *) fail "unknown step destination '$1'" ;;
  esac
}

# Fills step_command and step_command_text for one step record's kind and
# arguments, so the same resolution serves the run and the plan.
resolve_command() {
  local kind=$1
  local destination=$2
  shift 2
  step_command=()
  case "${kind}" in
    command)
      step_command=("$@")
      ;;
    swift)
      step_command=(swift test --package-path "$1")
      ;;
    test)
      resolve_destination "${destination}"
      step_command=(
        xcodebuild test -derivedDataPath "${derived_data}" -scheme RefineID \
          -destination "${resolved_destination}" "$@" -quiet
      )
      ;;
    build)
      resolve_destination "${destination}"
      step_command=(
        xcodebuild -derivedDataPath "${derived_data}" -scheme RefineID \
          -destination "${resolved_destination}" -quiet build CODE_SIGNING_ALLOWED=NO
      )
      ;;
    *)
      fail "unknown step kind '${kind}'"
      ;;
  esac
}

# One command line per step for `plan`, quoting an argument that carries a
# space so the printed line reads the way it would be typed.
print_command() {
  local first=1 argument
  for argument in "${step_command[@]}"; do
    [[ ${first} -eq 1 ]] || printf ' '
    first=0
    case "${argument}" in
      *' '*) printf "'%s'" "${argument}" ;;
      *) printf '%s' "${argument}" ;;
    esac
  done
  printf '\n'
}

# Splits a step record on '|' into fields. A here-string would ask bash for a
# temporary file, which a sandboxed test host cannot create, so the split is
# done by parameter expansion instead.
split_record() {
  local remaining=$1
  fields=()
  while [[ -n ${remaining} ]]; do
    fields+=("${remaining%%|*}")
    case "${remaining}" in
      *'|'*) remaining="${remaining#*|}" ;;
      *) return 0 ;;
    esac
  done
}

# Runs, or with `plan` prints, each step record in order.
run_tier() {
  local record="" title="" kind="" destination="" reason=""
  local index=0 argument=""
  local -a arguments=() expanded=()
  if [[ ${plan} -eq 0 ]]; then
    trap unregister_gate_builds EXIT
  fi
  for record in "$@"; do
    index=$((index + 1))
    arguments=()
    expanded=()
    split_record "${record}"
    title="${fields[0]}"
    kind="${fields[1]}"
    destination="${fields[2]:-}"
    reason="${fields[3]:-}"
    if [[ ${#fields[@]} -gt 4 ]]; then
      arguments=("${fields[@]:4}")
    fi
    if [[ ${#arguments[@]} -gt 0 ]]; then
      for argument in "${arguments[@]}"; do
        case "${argument}" in
          '{result_bundle}')
            if [[ -z ${result_bundle} ]]; then
              if [[ ${plan} -eq 1 ]]; then
                result_bundle="build/macos-mvp-ui-<UTC timestamp>.xcresult"
              else
                result_bundle="build/macos-mvp-ui-$(date -u +%Y%m%dT%H%M%SZ).xcresult"
              fi
            fi
            expanded+=("${result_bundle}")
            ;;
          *)
            expanded+=("${argument}")
            ;;
        esac
      done
    fi
    if [[ ${#expanded[@]} -gt 0 ]]; then
      resolve_command "${kind}" "${destination}" "${expanded[@]}"
    else
      resolve_command "${kind}" "${destination}"
    fi
    if [[ ${plan} -eq 1 ]]; then
      printf '\n=== %d. %s ===\n' "${index}" "${title}"
      print_command
    else
      step "${index}. ${title}"
      "${step_command[@]}" || fail "${reason}"
    fi
  done
}

case "${mode}" in
  -h | --help | help)
    usage
    exit 0
    ;;

  commit)
    commit_plan=(
      "Testing gate inspection and execution|command||Gate plan tests failed.|python3|-B|Scripts/TestGatePlans.py"
      "Testing the documentation gate|command||Documentation gate tests failed.|python3|-B|Scripts/TestDocumentationGate.py"
    )
    # The receipt gate is re-tested only when a file it covers is staged.
    if [[ ${plan} -eq 1 ]]; then
      commit_plan+=(
        "Checking the quality receipt gate behavior, when a receipt gate file is staged|command||Quality receipt gate tests failed.|python3|-B|Scripts/TestQualityReceipt.py"
      )
    elif ! git diff --cached --quiet -- Scripts/QualityReceipt.py Scripts/TestQualityReceipt.py; then
      commit_plan+=(
        "Checking the quality receipt gate behavior|command||Quality receipt gate tests failed.|python3|-B|Scripts/TestQualityReceipt.py"
      )
    fi
    commit_plan+=(
      "Checking for whitespace errors in staged changes|command||Staged changes contain trailing whitespace or whitespace errors.|git|diff|--cached|--check"
      "Running lint and layout gate (Scripts/lint.sh)|command||Lint gate failed.|Scripts/QualityReceipt.py|lint-index"
    )
    run_tier "${commit_plan[@]}"
    if [[ ${plan} -eq 0 ]]; then
      printf 'Commit gate passed.\n'
    fi
    ;;

  pr)
    if [[ ${plan} -eq 1 ]]; then
      checked_head="<HEAD>"
      checked_tree="<tree>"
    else
      checked_head="$(git rev-parse HEAD)"
      checked_tree="$(git rev-parse 'HEAD^{tree}')"
    fi
    pr_plan=(
      "Testing gate inspection and execution|command||Gate plan tests failed.|python3|-B|Scripts/TestGatePlans.py"
      "Testing the documentation gate|command||Documentation gate tests failed.|python3|-B|Scripts/TestDocumentationGate.py"
      "Requiring a clean checkout|command||Push checks require a clean checkout.|Scripts/QualityReceipt.py|verify-clean-head"
      "Testing exact-tree lint receipts|command||Quality receipt gate tests failed.|python3|-B|Scripts/TestQualityReceipt.py"
      "Running lint and layout gate for HEAD|command||Lint gate failed.|Scripts/QualityReceipt.py|lint-head"
      "Running CardCore package tests|swift||CardCore package tests failed.|CardCore"
      "Running PKCS11Bridge package tests|swift||PKCS11Bridge package tests failed.|PKCS11Bridge"
      "Verifying iOS compilation|build|ios|iOS build failed. Check for platform-conditional compilation issues."
      "Running unit test suite (RefineIDTests on macOS)|test|macos|Unit tests failed.|-only-testing:RefineIDTests"
      # The phone's suites compile only where REFINEID_REMOTE_CARD is on,
      # which is nowhere on macOS: they run on the simulator, in the host
      # whose module the tests import.
      "Running unit test suite (RefineIDTests on the iOS simulator)|test|simulator|Unit tests failed on the iOS simulator.|-only-testing:RefineIDTests"
      "Running core test suite (CardCoreTests on macOS, without RAPP integration)|test|macos|CardCore tests failed.|-only-testing:CardCoreTests|-skip-testing:CardCoreTests/RappIntegrationTests"
      # RappIntegrationTests runs in its own invocation: a combined run can
      # stall while Xcode finalizes its test record.
      "Running RAPP integration tests (CardCoreTests/RappIntegrationTests on macOS)|test|macos|RAPP integration tests failed.|-only-testing:CardCoreTests/RappIntegrationTests"
      "Running simulator-only engine tests on iOS (Bluetooth-gated, offer handoff)|test|simulator|Simulator-only engine tests failed.|-only-testing:CardCoreTests/RappBleAppearanceWatcherTests|-only-testing:CardCoreTests/CardCanOfferTests"
      "Judging the Swift signers' documents with EU DSS (Scripts/dss-gate.sh)|command||A Swift signer's document is below the release level in DSS.|Scripts/dss-gate.sh"
      "Running the direct-download DMG builder command-line tests|command||The direct-download DMG builder command-line tests failed.|swift|Scripts/TestMacosNotarizedDmgBuilder.swift"
      "Running the App Store Connect release manager command-line tests|command||The App Store Connect release manager command-line tests failed.|swift|Scripts/TestAppleAppStoreConnectReleaseManager.swift"
      "Verifying the checked-out commit did not change during the push checks|command||The checked-out commit changed during push checks.|Scripts/QualityReceipt.py|verify-head|${checked_head}|${checked_tree}"
    )
    run_tier "${pr_plan[@]}"
    if [[ ${plan} -eq 0 ]]; then
      printf '\nPR gate passed: gate tests, lint, DMG builder and release manager command-line tests, CardCore and PKCS11Bridge package tests, iOS build, RefineIDTests on macOS and iOS, CardCoreTests, RappIntegrationTests, simulator Bluetooth and offer-handoff tests, and the DSS gate.\n'
    fi
    ;;

  nfc-signing)
    nfc_plan=(
      "Testing retained NFC field lifecycle and PACE|test|macos|NFC signing regression tests failed.|-only-testing:CardCoreTests/HeldCardSessionTests|-only-testing:CardCoreTests/PaceEstablishmentTests|-only-testing:CardCoreTests/CommandApduTests|-only-testing:CardCoreTests/CardExchangeTraceTests|-only-testing:CardCoreTests/CardExchangeProgressTests|-only-testing:CardCoreTests/OnDemandPinExperimentTests|-only-testing:CardCoreTests/OnDemandPinPublicationTests|-only-testing:CardCoreTests/SecureMessagingChannelTests|-only-testing:RefineIDTests/SmartCardTransmitTests"
    )
    run_tier "${nfc_plan[@]}"
    ;;

  macos-mvp)
    ui_plan=(
      "Checking the macOS MVP user interface|test|macos|macOS MVP UI checks failed.|-testPlan|RefineIDUITests|-only-testing:RefineIDUITests/MacMvpUITests|-resultBundlePath|{result_bundle}"
    )
    run_tier "${ui_plan[@]}"
    ;;

  *)
    usage >&2
    exit 2
    ;;
esac
