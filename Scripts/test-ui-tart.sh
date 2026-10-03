#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Runs RefineID macOS UI tests headlessly inside an isolated Tart macOS VM.
#
# Because macOS XCUITest requires an active WindowServer session with Accessibility
# (AXUIElement) event synthesis, running UI tests on a developer's workstation steals
# keyboard/mouse focus and pops up windows. Running them inside a headless Tart VM
# completely isolates WindowServer and prevents desktop disruption.
#
# Usage:
#   Scripts/test-ui-tart.sh [VM_NAME]
#
# Default VM_NAME: "macos-ci"
#
# Prerequisites:
#   brew install cirruslabs/cli/tart
#   tart pull ghcr.io/cirruslabs/macos-sonoma-xcode:latest macos-ci
#   (or any macOS VM with Xcode installed)

set -euo pipefail
cd "$(dirname "$0")/.."

VM_NAME="${1:-macos-ci}"

if ! command -v tart >/dev/null 2>&1; then
  printf 'Error: tart is not installed. Install it with: brew install cirruslabs/cli/tart\n' >&2
  exit 1
fi

if ! tart list | grep -q -w "${VM_NAME}"; then
  printf 'Tart VM "%s" not found.\n\n' "${VM_NAME}"
  printf 'Available Tart VMs:\n'
  tart list || true
  printf '\nTo pull a pre-configured macOS VM with Xcode:\n'
  printf '  tart pull ghcr.io/cirruslabs/macos-sonoma-xcode:latest %s\n\n' "${VM_NAME}"
  printf 'Or clone an existing VM:\n'
  printf '  tart clone <source-vm> %s\n' "${VM_NAME}"
  exit 1
fi

REPO_DIR="$(pwd)"
VM_RUNNER_DIR="/Volumes/My Shared Files/refineid-apple"

printf '==> Running RefineID macOS UI tests in headless Tart VM "%s"...\n' "${VM_NAME}"

# Run the VM headlessly in the background with directory sharing
tart run "${VM_NAME}" --no-gui --dir "refineid-apple:${REPO_DIR}" &
VM_PID=$!

cleanup() {
  printf '\n==> Stopping Tart VM...\n'
  tart stop "${VM_NAME}" >/dev/null 2>&1 || true
  kill -9 "${VM_PID}" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

# Wait for VM SSH / IP to become available
printf '==> Waiting for VM IP...\n'
VM_IP=""
for _ in {1..30}; do
  if VM_IP="$(tart ip "${VM_NAME}" 2>/dev/null)" && [ -n "${VM_IP}" ]; then
    break
  fi
  sleep 2
done

if [ -z "${VM_IP}" ]; then
  printf 'Error: Could not retrieve IP for VM "%s".\n' "${VM_NAME}" >&2
  exit 1
fi

printf '==> Tart VM online at %s. Running UI tests...\n' "${VM_IP}"

# Execute UI tests inside the VM
tart exec "${VM_NAME}" /bin/bash -lc "
  set -euo pipefail
  cd '${VM_RUNNER_DIR}'
  xcodebuild test -scheme RefineID -destination 'platform=macOS' -only-testing:RefineIDUITests
"

printf '\n==> Headless UI tests in Tart VM completed successfully!\n'
