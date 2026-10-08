#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Usage:
#   Scripts/format.sh              # format all Swift source files in project
#   Scripts/format.sh --staged     # format only git-staged Swift files
#   Scripts/format.sh <files...>   # format specific files
#
# Formats Swift code in-place using swift-format according to .swift-format.

set -euo pipefail
cd "$(dirname "$0")/.."

format_paths=(
  Sources Tests Samples
  CardCore/Sources/CardCore CardCore/Sources/RappEngine
  CardCore/Tests CardCore/Package.swift
  PKCS11Bridge/Sources PKCS11Bridge/Tests PKCS11Bridge/Package.swift
  Scripts/BrainpoolBenchmark.swift
)

if [ "${1:-}" = "--staged" ]; then
  # Format only staged Swift files
  staged_files=()
  while IFS= read -r file; do
    if [[ -f "${file}" && "${file}" == *.swift ]]; then
      staged_files+=("${file}")
    fi
  done < <(git diff --cached --name-only --diff-filter=ACM)

  if [ ${#staged_files[@]} -gt 0 ]; then
    swift format format --in-place "${staged_files[@]}"
    git add "${staged_files[@]}"
    printf 'Formatted and re-staged %d Swift file(s).\n' "${#staged_files[@]}"
  else
    printf 'No staged Swift files to format.\n'
  fi
elif [ "$#" -gt 0 ]; then
  # Format user-specified files
  swift format format --in-place "$@"
  printf 'Formatted %d file(s).\n' "$#"
else
  # Format all designated project paths
  swift format format --in-place --recursive "${format_paths[@]}"
  printf 'Formatted all project Swift sources.\n'
fi
