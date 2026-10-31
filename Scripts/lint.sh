#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Usage: Scripts/lint.sh
#
# The lint gate, and the only SwiftLint invocation the pre-commit and
# pre-push hooks run. Run this script. Do not run:
#
#   swiftlint lint --autocorrect --format --progress --check-for-updates --enable-all-rules
#
# --enable-all-rules ignores disabled_rules, so it cannot honour the
# carve register in .swiftlint.yml (it turns on rules that contradict
# each other and rules that fight swift-format). --format reformats
# with SourceKit, a different layout owner than swift-format.
#
# Gate:
# - swift-format owns layout
# - SwiftLint owns defects (strict, carve register, baseline)
# - swiftc typechecks the standalone scripts under Scripts/, which no
#   scheme or package compiles
# - typing-discipline custom rules live in .swiftlint.yml
# - suppression comments must match Scripts/lint-suppression-register.json
#   exactly (add or drop one only by editing that register)
#
# A clean run prints nothing. Findings go to stderr.
# Run from anywhere; operates on the repository.
#
# To bootstrap or review the suppression register after changing
# suppressions, print the tree-derived register to stdout for human
# review, then copy the reviewed output over
# Scripts/lint-suppression-register.json in the same commit:
#
#   Scripts/lint.sh regenerate-register

set -euo pipefail
cd "$(dirname "$0")/.."

mode="${1:-check}"
if [ "${mode}" != "check" ] && [ "${mode}" != "regenerate-register" ]; then
  printf 'usage: %s [check|regenerate-register]\n' "$0" >&2
  exit 2
fi

fail() {
  local name=$1
  local log=$2
  printf 'lint FAIL: %s\n' "${name}" >&2
  if [[ -n ${log} ]]; then
    printf '%s\n' "${log}" >&2
  fi
  exit 1
}

format_paths=(
  Sources Tests
  CardCore/Sources/CardCore CardCore/Sources/RappEngine
  CardCore/Tests CardCore/Package.swift
  PKCS11Bridge/Sources PKCS11Bridge/Tests PKCS11Bridge/Package.swift
  Scripts/BrainpoolBenchmark.swift
)

format_log=$(
  swift format lint --strict --recursive "${format_paths[@]}" 2>&1
) || fail "swift-format" "${format_log}"

# The baseline records the structural debt (type ordering, file splits,
# magic numbers) present when the gate was raised. New findings fail;
# paying debt down rewrites the baseline.
swiftlint_log=$(
  swiftlint lint --quiet --baseline .swiftlint-baseline.json 2>&1
) || fail "swiftlint" "${swiftlint_log}"

# A script that `swift` runs is typechecked alone. A script compiled
# into the CardCore module is typechecked with the CardCore sources it
# uses. Every Swift file under Scripts/ must appear in one call.
macos_sdk=$(xcrun --show-sdk-path --sdk macosx)
typechecked_scripts=()

typecheck() {
  local name=$1
  shift
  local path
  for path in "$@"; do
    case "${path}" in
      Scripts/*) typechecked_scripts+=("${path}") ;;
    esac
  done
  local log
  log=$(swiftc -typecheck -sdk "${macos_sdk}" "$@" 2>&1) || fail "typecheck ${name}" "${log}"
}

typecheck "release manager" Scripts/apple-app-store-connect-release-manager.swift
typecheck "store screenshots" Scripts/generate-store-screenshots.swift
typecheck "card logins" Scripts/test-card-logins.swift
typecheck "icon" Scripts/generate-icon.swift
typecheck "slack icon" Scripts/generate-slack-icon.swift
typecheck "stamp samples" \
  CardCore/Sources/CardCore/PdfStampRenderer.swift \
  CardCore/Sources/CardCore/StampMark.swift \
  CardCore/Sources/CardCore/Values/PdfValues.swift \
  Scripts/RenderStampSamples.swift
typecheck "brainpool benchmark" \
  CardCore/Sources/CardCore/Crypto/U384.swift \
  CardCore/Sources/CardCore/Crypto/FieldP384.swift \
  CardCore/Sources/CardCore/Crypto/BrainpoolPoint.swift \
  CardCore/Sources/CardCore/Crypto/BrainpoolP384r1.swift \
  CardCore/Sources/CardCore/Values/BrainpoolP384r1Values.swift \
  CardCore/Sources/CardCore/Values/Sec1Values.swift \
  Scripts/BrainpoolBenchmark.swift

untypechecked=$(
  comm -23 <(find Scripts -name '*.swift' | sort) \
    <(printf '%s\n' "${typechecked_scripts[@]}" | sort)
)
if [[ -n ${untypechecked} ]]; then
  fail "typecheck" "not typechecked (add a typecheck call to Scripts/lint.sh):"$'\n'"${untypechecked}"
fi

register_path="Scripts/lint-suppression-register.json"
if [ "${mode}" = "check" ] && [ ! -f "${register_path}" ]; then
  fail "lint locks" "missing ${register_path}; print a reviewed replacement with: Scripts/lint.sh regenerate-register"
fi

lock_log=$(
  python3 - "${mode}" "${format_paths[@]}" 2>&1 << 'PY'
import json, re, sys
from collections import Counter
from pathlib import Path

mode = sys.argv[1]
argv = sys.argv[2:]

register = {"swiftlint": [], "swift_format_ignore": []}
if mode == "check":
    register = json.loads(
        Path("Scripts/lint-suppression-register.json").read_text(encoding="utf-8")
    )

files = []
for raw in argv:
    path = Path(raw)
    if path.is_file():
        files.append(path)
    else:
        files.extend(path.rglob("*.swift"))
files = sorted(set(files))

disable_re = re.compile(
    r"swiftlint:(disable(?::(?:next|this|previous))?|enable)\s+([^\n]+?)\s*$",
    re.M,
)
fmt_re = re.compile(
    r"^[ \t]*//[ \t]*swift-format-ignore(?:-file)?(?::\s*([^\n]+))?\s*$",
    re.M,
)

actual_lint = Counter()
actual_fmt = Counter()
for path in files:
    rel = path.as_posix()
    text = path.read_text(encoding="utf-8")
    for match in disable_re.finditer(text):
        command = match.group(1)
        rules = tuple(sorted(match.group(2).split()))
        actual_lint[(rel, command, rules)] += 1
    for match in fmt_re.finditer(text):
        rule = (match.group(1) or "").strip()
        actual_fmt[(rel, rule)] += 1

expected_lint = Counter()
for entry in register["swiftlint"]:
    key = (entry["file"], entry["command"], tuple(entry["rules"]))
    expected_lint[key] += entry["count"]

expected_fmt = Counter()
for entry in register["swift_format_ignore"]:
    expected_fmt[(entry["file"], entry["rule"])] += entry["count"]

if mode == "regenerate-register":
    print(json.dumps({
        "swiftlint": [
            {"file": key[0], "command": key[1], "rules": list(key[2]),
             "count": count}
            for key, count in sorted(actual_lint.items())
        ],
        "swift_format_ignore": [
            {"file": key[0], "rule": key[1], "count": count}
            for key, count in sorted(actual_fmt.items())
        ],
    }, indent=2, sort_keys=False))
    sys.exit(0)

failed = False
for label, actual, expected in (
    ("swiftlint suppression", actual_lint, expected_lint),
    ("swift-format-ignore", actual_fmt, expected_fmt),
):
    extra = actual - expected
    missing = expected - actual
    if extra or missing:
        failed = True
        sys.stderr.write(f"lint lock FAIL: {label} does not match "
                         "Scripts/lint-suppression-register.json\n")
        for key, count in sorted(extra.items()):
            sys.stderr.write(f"  extra x{count}: {key}\n")
        for key, count in sorted(missing.items()):
            sys.stderr.write(f"  missing x{count}: {key}\n")

if failed:
    sys.stderr.write(
        "Fix the finding, or change the register in the same commit. "
        "Do not add a suppression without removing one from the register.\n"
    )
    sys.exit(1)
PY
) || fail "lint locks" "${lock_log}"

if [ "${mode}" = "regenerate-register" ]; then
  printf '%s\n' "${lock_log}"
fi
