#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
# 

# Build, sign, install, and launch an optimized diagnostic build on one iPhone or iPad.
#
# The calendar version and ten-minute build number are command-line Xcode
# overrides. The project file is never edited, so repeated device builds do
# not create version-only Git changes.
#
# Usage:
#
#   Scripts/install-ios-development.sh [<device name or identifier>]
#
# If no device argument is provided, the first connected physical device is
# detected automatically via devicectl.
#
# Example:
#
#   Scripts/install-ios-development.sh My-iPhone
#   Scripts/install-ios-development.sh

set -euo pipefail
cd "$(dirname "$0")/.."

device="${1:-}"
if [[ -z "$device" ]]; then
  device=$(xcrun devicectl list devices 2>/dev/null | grep -E "iPhone|iPad" | grep -v "Simulator" | awk '{print $3}' | head -n 1 || true)
  if [[ -z "$device" ]]; then
    device=$(xcrun devicectl list devices 2>/dev/null | grep -E "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | awk '{print $3}' | head -n 1 || true)
  fi
  if [[ -z "$device" ]]; then
    echo "install-ios-development: no physical iOS device found; specify device name or identifier as argument" >&2
    exit 2
  fi
  echo "install-ios-development: auto-detected device ${device}"
fi

read -r yy mm dd hh mn <<<"$(date -u '+%y %m %d %H %M')"
version="${yy}.$((10#$mm)).$((10#$dd))"
build=$((10#$hh * 10 + 10#$mn / 10))
derived_data="/tmp/refineid-apple-development"
configuration="Profile"
app_path="${derived_data}/Build/Products/${configuration}-iphoneos/RefineID.app"

if [[ "$device" =~ ^[0-9a-fA-F-]+$ ]]; then
  destination="platform=iOS,id=${device}"
else
  destination="platform=iOS,name=${device}"
fi

echo "building RefineID ${version} (${build}) (${configuration}, optimized) for ${device}"
xcodebuild \
  -project RefineID.xcodeproj \
  -scheme RefineID \
  -configuration "$configuration" \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build" \
  CLANG_COVERAGE_MAPPING=NO \
  ENABLE_CODE_COVERAGE=NO \
  -quiet \
  build

codesign --verify --deep --strict "$app_path"
xcrun devicectl device install app --device "$device" "$app_path"

device_name=$(xcrun devicectl list devices 2>/dev/null | grep "$device" | awk '{print $1}' || true)
if [[ -n "$device_name" ]]; then
  xcrun devicectl device process launch \
    --device "$device" \
    --terminate-existing \
    fi.refineid.ReFineID --device-name "$device_name"
else
  xcrun devicectl device process launch \
    --device "$device" \
    --terminate-existing \
    fi.refineid.ReFineID
fi

echo "installed and launched RefineID ${version} (${build})"
