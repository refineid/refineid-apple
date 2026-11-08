#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Usage: Scripts/dss-gate.sh
#
# The independent validation gate for the Swift signers. Runs
# RefineIDTests/DssGateExportTests, which signs a PDF and an ASiC-E
# container through the app's own timestamp, evidence and archive stages
# against synthetic authorities, then has the EU DSS validator judge both:
#
#   swift-pades.pdf      PAdES-BASELINE-LTA, TOTAL_PASSED
#   swift-asic-e.asice   XAdES-BASELINE-LTA, TOTAL_PASSED, ASiC-E
#
# A release build saves only these levels, so anything less fails.
# Documentation/testing-strategy.md describes the gate.
#
# DSS 6.5.1 is pinned in Scripts/dss-gate/dss.lock: each jar is fetched
# once from Maven Central into the cache and refused unless its SHA-256
# matches. After that nothing here uses a network: the test answers its
# requests in memory and DSS runs with no online source.
#
# Environment:
#   REFINEID_DSS_CACHE  jar cache (default ~/.cache/refineid/dss-gate)
#   JAVA_HOME           a JDK 17 or later; otherwise found as below

set -euo pipefail
cd "$(dirname "$0")/.."

lock="Scripts/dss-gate/dss.lock"
source_file="Scripts/dss-gate/DssGate.java"
cache="${REFINEID_DSS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/refineid/dss-gate}"
central="https://repo1.maven.org/maven2"
derived_data="build/DerivedData"
test_host_bundle="fi.refineid.ReFineID.testhost"
export_name="RefineIDDssGate"

fail() {
  printf 'dss-gate: %s\n' "$*" >&2
  exit 1
}

jdk_bin() {
  local candidate
  for candidate in \
    "${JAVA_HOME:-}" \
    "$(/usr/libexec/java_home 2>/dev/null || true)" \
    "$(brew --prefix openjdk 2>/dev/null || true)"; do
    if [[ -n "${candidate}" ]] && "${candidate}/bin/java" -version >/dev/null 2>&1 \
      && "${candidate}/bin/javac" -version >/dev/null 2>&1; then
      printf '%s/bin\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

bin="$(jdk_bin)" || fail "no JDK found: install a JDK 17 or later or set JAVA_HOME"

mkdir -p "${cache}"
classpath=""
while read -r digest coordinates; do
  case "${digest}" in '' | '#'*) continue ;; esac
  IFS=: read -r group artifact version <<<"${coordinates}"
  jar="${cache}/${artifact}-${version}.jar"
  if [[ ! -f "${jar}" ]] || [[ "$(shasum -a 256 "${jar}" | cut -d ' ' -f 1)" != "${digest}" ]]; then
    url="${central}/${group//.//}/${artifact}/${version}/${artifact}-${version}.jar"
    printf 'dss-gate: fetching %s\n' "${coordinates}"
    curl -fsSL -o "${jar}.part" "${url}" || fail "cannot fetch ${url}"
    if [[ "$(shasum -a 256 "${jar}.part" | cut -d ' ' -f 1)" != "${digest}" ]]; then
      rm -f "${jar}.part"
      fail "${coordinates} does not match its SHA-256 in ${lock}"
    fi
    mv "${jar}.part" "${jar}"
  fi
  classpath="${classpath}:${jar}"
done <"${lock}"
classpath="${classpath#:}"

classes="build/dss-gate/classes"
rm -rf "${classes}"
mkdir -p "${classes}"
"${bin}/javac" -nowarn -d "${classes}" -cp "${classpath}" "${source_file}"

# The sandboxed test host writes under its container; an unsandboxed
# one under the user's temporary directory.
candidates=(
  "${HOME}/Library/Containers/${test_host_bundle}/Data/tmp/${export_name}"
  "$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)${export_name}"
)
for candidate in "${candidates[@]}"; do rm -rf "${candidate}"; done

printf '=== Exporting the Swift signers'"'"' documents ===\n'
xcodebuild test -derivedDataPath "${derived_data}" -scheme RefineID -destination 'platform=macOS' \
  -only-testing:RefineIDTests/DssGateExportTests -quiet \
  || fail "the export test failed: the Swift signers did not finish a document"

exported=""
for candidate in "${candidates[@]}"; do
  if [[ -f "${candidate}/anchor-ca.der" ]]; then exported="${candidate}"; fi
done
[[ -n "${exported}" ]] || fail "the export test wrote no documents"

failed=0
judge() {
  local file=$1 expected=$2 container=$3 report
  report="$("${bin}/java" -cp "${classes}:${classpath}" DssGate \
    --anchor "${exported}/anchor-ca.der" --anchor "${exported}/anchor-tsa.der" \
    "${exported}/${file}" 2>&1)" || {
    printf '%s: DSS failed\n%s\n' "${file}" "${report}"
    failed=1
    return
  }
  local line
  line="$(grep '^signature ' <<<"${report}" || true)"
  if [[ "$(grep -c '^signature ' <<<"${report}")" == 1 ]] \
    && grep -q " format=${expected} indication=TOTAL_PASSED " <<<"${line}" \
    && grep -qx "container=${container}" <<<"${report}"; then
    printf '%s: %s TOTAL_PASSED, container %s\n' "${file}" "${expected}" "${container}"
  else
    printf '%s: required %s TOTAL_PASSED in container %s; DSS reports\n%s\n' \
      "${file}" "${expected}" "${container}" "${report}"
    failed=1
  fi
}

printf '=== Judging them with EU DSS 6.5.1 ===\n'
judge swift-pades.pdf PAdES-BASELINE-LTA -
judge swift-asic-e.asice XAdES-BASELINE-LTA ASiC-E

[[ "${failed}" == 0 ]] || fail "a Swift signer's document is below the release level"
printf 'dss-gate: the Swift signers reached B-LTA in DSS\n'
