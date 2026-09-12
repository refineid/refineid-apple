#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

# Automates capturing App-Store-ready iPhone screenshots (APP_IPHONE_67: 1290x2796)
# using an iOS Simulator with clean status bar and localized app states.
#
# Usage:
#   Scripts/store-screenshot-ios.sh [--all] [--locale <en-US|fi|sv>] [--scenario <name>] [--output-dir <path>]
#
# Defaults to generating 01-app-main.png for all supported locales (en-US, fi, sv)
# and saving them into Metadata/screenshots/<locale>/APP_IPHONE_67/01-app-main.png.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TARGET_LOCALES=("en-US" "fi" "sv")
CUSTOM_OUTPUT_DIR=""
SCENARIO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --locale)
      TARGET_LOCALES=("$2")
      shift 2
      ;;
    --scenario)
      SCENARIO="$2"
      shift 2
      ;;
    --output-dir)
      CUSTOM_OUTPUT_DIR="$2"
      shift 2
      ;;
    --all)
      TARGET_LOCALES=("en-US" "fi" "sv")
      shift
      ;;
    -h|--help)
      echo "Usage: Scripts/store-screenshot-ios.sh [--all] [--locale <en-US|fi|sv>] [--scenario <name>] [--output-dir <path>]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

echo "==> Finding or creating 6.7\"/6.9\" iPhone simulator device..."
DEVICE_UDID="$(python3 - << 'PYEOF'
import subprocess, json

def get_udid():
    out = subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j'])
    data = json.loads(out)
    preferred_names = ['iPhone 16 Plus', 'iPhone 15 Pro Max', 'iPhone 14 Pro Max', 'RefineID-Screenshot-iPhone16Plus']
    for runtime, devices in data.get('devices', {}).items():
        if 'iOS' not in runtime:
            continue
        for name in preferred_names:
            for d in devices:
                if d.get('name') == name and d.get('isAvailable', True):
                    return d['udid']
    # If not found, create one
    runtimes = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'runtimes', '-j'])).get('runtimes', [])
    ios_runtimes = [r['identifier'] for r in runtimes if 'iOS' in r.get('name', '') and r.get('isAvailable', True)]
    if not ios_runtimes:
        raise RuntimeError("No available iOS simulator runtime found")
    runtime_id = ios_runtimes[-1]
    created = subprocess.check_output([
        'xcrun', 'simctl', 'create',
        'RefineID-Screenshot-iPhone16Plus',
        'com.apple.CoreSimulator.SimDeviceType.iPhone-16-Plus',
        runtime_id
    ]).decode('utf-8').strip()
    return created

print(get_udid())
PYEOF
)"

echo "Using simulator UDID: $DEVICE_UDID"

# Boot device if not already booted
DEV_STATE="$(python3 -c "
import subprocess, json
out = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '-j']))
for rt, devs in out.get('devices', {}).items():
    for d in devs:
        if d['udid'] == '$DEVICE_UDID':
            print(d.get('state', ''))
" )"

if [[ "$DEV_STATE" != "Booted" ]]; then
  echo "==> Booting simulator..."
  xcrun simctl boot "$DEVICE_UDID"
fi

echo "==> Waiting for simulator to finish booting..."
xcrun simctl bootstatus "$DEVICE_UDID"

echo "==> Setting clean status bar (9:41, full battery, full signal)..."
xcrun simctl status_bar "$DEVICE_UDID" override \
  --time "9:41" \
  --batteryState charged \
  --batteryLevel 100 \
  --wifiBars 3 \
  --cellularBars 4

echo "==> Building RefineID for iOS Simulator..."
xcodebuild build \
  -project "$REPO_ROOT/RefineID.xcodeproj" \
  -scheme RefineID \
  -destination "platform=iOS Simulator,id=$DEVICE_UDID" \
  -configuration Debug \
  -quiet

DERIVED_DATA_DIR="$(xcodebuild -project "$REPO_ROOT/RefineID.xcodeproj" -scheme RefineID -showBuildSettings -configuration Debug -destination "platform=iOS Simulator,id=$DEVICE_UDID" | grep -m 1 "TARGET_BUILD_DIR =" | awk -F '= ' '{print $2}')"
APP_BUNDLE="$DERIVED_DATA_DIR/RefineID.app"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Error: Built app bundle not found at $APP_BUNDLE" >&2
  exit 1
fi

echo "==> Installing app on simulator..."
xcrun simctl uninstall "$DEVICE_UDID" fi.refineid.ReFineID 2>/dev/null || true
xcrun simctl install "$DEVICE_UDID" "$APP_BUNDLE"

for LOCALE in "${TARGET_LOCALES[@]}"; do
  echo "==> Capturing screenshot for locale: $LOCALE..."
  
  LANG_CODE="$LOCALE"
  if [[ "$LOCALE" == "en-US" ]]; then
    LANG_CODE="en"
  fi
  
  SCENARIO_NAME="${SCENARIO:-registered-nfc}"
  LAUNCH_ARGS=("-AppleLanguages" "($LANG_CODE)" "-AppleLocale" "$LOCALE" "--hide-diagnostics" "--mock-remote-connected" "--virtual-card" "$SCENARIO_NAME")

  xcrun simctl ui "$DEVICE_UDID" appearance light

  xcrun simctl terminate "$DEVICE_UDID" fi.refineid.ReFineID 2>/dev/null || true
  xcrun simctl launch "$DEVICE_UDID" fi.refineid.ReFineID "${LAUNCH_ARGS[@]}"

  # Wait for UI to settle (virtual card state needs extra time)
  sleep 5
  
  if [[ -n "$CUSTOM_OUTPUT_DIR" ]]; then
    OUT_DIR="$CUSTOM_OUTPUT_DIR/$LOCALE/APP_IPHONE_67"
  else
    OUT_DIR="$REPO_ROOT/Metadata/screenshots/$LOCALE/APP_IPHONE_67"
  fi
  mkdir -p "$OUT_DIR"
  
  OUT_FILE="$OUT_DIR/01-app-main.png"
  xcrun simctl io "$DEVICE_UDID" screenshot "$OUT_FILE"
  
  # Verify dimensions
  WIDTH="$(sips -g pixelWidth "$OUT_FILE" | awk '/pixelWidth/ {print $2}')"
  HEIGHT="$(sips -g pixelHeight "$OUT_FILE" | awk '/pixelHeight/ {print $2}')"
  echo "    Saved: $OUT_FILE ($WIDTH x $HEIGHT)"
  
  xcrun simctl terminate "$DEVICE_UDID" fi.refineid.ReFineID 2>/dev/null || true
done

echo "==> App Store iPhone screenshot generation complete."
