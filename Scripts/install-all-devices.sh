#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

# Stamps the version and installs the latest synchronized build on this
# Mac (/Applications), the connected physical iOS device, the iPad
# simulator, or a subset of those.
#
# Run after a feature commit so every machine that can run the app
# matches the tree. Discover devices at runtime; do not pass stored
# UDIDs. The stamp rewrite of Version.xcconfig is not part of the
# feature commit.
#
# Usage:
#   Scripts/install-all-devices.sh [--device-only | --simulator-only | --macos-only] [--prime-mock-card]
#

set -euo pipefail
cd "$(dirname "$0")/.."

prime_mock_card=false
target_device=true
target_simulator=true
target_macos=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prime-mock-card)
      prime_mock_card=true
      shift
      ;;
    --device-only)
      target_simulator=false
      target_macos=false
      shift
      ;;
    --simulator-only)
      target_device=false
      target_macos=false
      shift
      ;;
    --macos-only)
      target_device=false
      target_simulator=false
      shift
      ;;
    --no-simulator)
      target_simulator=false
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--device-only | --simulator-only | --macos-only | --no-simulator] [--prime-mock-card]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

echo "Stamping version..."
./Scripts/stamp-version.sh

read -r yy mm dd hh mn <<<"$(date -u '+%y %m %d %H %M')"
version="${yy}.$((10#$mm)).$((10#$dd))"
build=$((10#$hh * 10 + 10#$mn / 10))

echo "Version stamped: ${version} (${build})"

pids=()

# 1. This Mac
if [ "$target_macos" = true ]; then
  (
    echo "Installing on this Mac at /Applications..."
    ./Scripts/install-macos.sh
  ) &
  pids+=($!)
fi

# 2. Physical Device
if [ "$target_device" = true ]; then
  device_id=$(xcrun devicectl list devices 2>/dev/null | grep -E "iPhone|iPad" | grep -v "Simulator" | awk '{print $3}' | head -n 1 || true)
  if [[ -z "$device_id" ]]; then
    device_id=$(xcrun devicectl list devices 2>/dev/null | grep -E "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | awk '{print $3}' | head -n 1 || true)
  fi

  if [[ -n "$device_id" ]]; then
    (
      echo "Installing on physical iOS device ${device_id}..."
      ./Scripts/install-ios-development.sh "$device_id"
      if [ "$prime_mock_card" = true ]; then
        echo "Priming mock test card on device..."
        device_name=$(xcrun devicectl list devices 2>/dev/null | grep "$device_id" | awk '{print $1}' || true)
        if [[ -n "$device_name" ]]; then
          xcrun devicectl device process launch \
            --device "$device_id" \
            --terminate-existing \
            fi.refineid.ReFineID --device-name "$device_name" --prime-mock-card
        else
          xcrun devicectl device process launch \
            --device "$device_id" \
            --terminate-existing \
            fi.refineid.ReFineID --prime-mock-card
        fi
      fi
    ) &
    pids+=($!)
  else
    echo "No physical iOS device detected via devicectl."
  fi
fi

# 3. iPad Simulator
if [ "$target_simulator" = true ]; then
  sim_id=$(xcrun simctl list devices available 2>/dev/null | grep -E "iPad Pro 13-inch" | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | head -n 1 || true)
  if [[ -z "$sim_id" ]]; then
    sim_id=$(xcrun simctl list devices available 2>/dev/null | grep -E "iPad" | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | head -n 1 || true)
  fi

  if [[ -n "$sim_id" ]]; then
    (
      echo "Installing on iPad simulator ${sim_id}..."
      # Ensure only the iPad simulator is running
      for booted_non_ipad in $(xcrun simctl list devices booted 2>/dev/null | grep -v "iPad" | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" || true); do
        xcrun simctl shutdown "$booted_non_ipad" 2>/dev/null || true
      done
      xcrun simctl boot "$sim_id" 2>/dev/null || true
      sim_derived_data="/tmp/refineid-ipad-sim"
      xcodebuild \
        -project RefineID.xcodeproj \
        -scheme RefineID \
        -destination "platform=iOS Simulator,id=${sim_id}" \
        -derivedDataPath "$sim_derived_data" \
        -configuration Debug \
        CLANG_COVERAGE_MAPPING=NO \
        ENABLE_CODE_COVERAGE=NO \
        -quiet \
        build
      xcrun simctl install "$sim_id" "${sim_derived_data}/Build/Products/Debug-iphonesimulator/RefineID.app"
      xcrun simctl launch --terminate-running-process "$sim_id" fi.refineid.ReFineID
      open -a Simulator --args -CurrentDeviceUDID "$sim_id"
      osascript -e 'tell application "Simulator" to activate' 2>/dev/null || true
      echo "iPad simulator updated and running."
    ) &
    pids+=($!)
  fi
fi

for pid in "${pids[@]}"; do
  wait "$pid"
done

echo "Selected targets synchronized on version ${version} (${build})."
