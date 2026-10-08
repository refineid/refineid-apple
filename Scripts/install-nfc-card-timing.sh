#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Build, sign, install, and launch the NFC card timing sample on one iPhone.
#
# The sample lives in Samples/NFCCardTiming and its project is generated
# from project.yml with xcodegen; this script regenerates it first so the
# YAML stays the source of truth.
#
# Usage:
#
#   Scripts/install-nfc-card-timing.sh [<device name or identifier>]
#
# If no device argument is provided, the first connected physical device is
# detected automatically via devicectl.

set -euo pipefail
cd "$(dirname "$0")/.."

device="${1:-}"
if [[ -z "$device" ]]; then
  device=$(xcrun devicectl list devices 2>/dev/null | grep -E "iPhone|iPad" | grep "available" | grep -oE "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}" | head -n 1 || true)
  if [[ -z "$device" ]]; then
    echo "install-nfc-card-timing: no available physical iOS device found; specify device name or identifier" >&2
    exit 1
  fi
  echo "install-nfc-card-timing: auto-detected device ${device}"
fi

if [[ "$device" =~ ^[0-9a-fA-F-]+$ ]]; then
  destination="platform=iOS,id=${device}"
else
  destination="platform=iOS,name=${device}"
fi

sample="Samples/NFCCardTiming"
derived_data="/tmp/refineid-nfc-card-timing"
configuration="Release"
app_path="${derived_data}/Build/Products/${configuration}-iphoneos/NFCCardTiming.app"
bundle_id="fi.refineid.NFCCardTiming"

(cd "$sample" && xcodegen generate --quiet)
echo "building NFCCardTiming (${configuration}) for ${device}"
xcodebuild \
  -project "${sample}/NFCCardTiming.xcodeproj" \
  -scheme NFCCardTiming \
  -configuration "$configuration" \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  -allowProvisioningUpdates \
  -quiet \
  build

codesign --verify --deep --strict "$app_path"
xcrun devicectl device install app --device "$device" "$app_path"
xcrun devicectl device process launch --device "$device" --terminate-existing "$bundle_id"
echo "installed and launched NFCCardTiming"
