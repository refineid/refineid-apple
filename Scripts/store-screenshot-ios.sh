#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

# Automates capturing App-Store-ready iPhone and iPad screenshots:
#   - APP_IPHONE_67: 1290x2796 (iPhone 6.7"/6.9")
#   - APP_IPAD_PRO_3GEN_129: 2048x2732 (iPad Pro 12.9")
# using iOS Simulators with clean status bars and localized app states.
#
# Usage:
#   Scripts/store-screenshot-ios.sh [--all] [--device <iphone|ipad|all>] [--locale <en-US|fi|sv>] [--scenario <name>] [--output-dir <path>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TARGET_LOCALES=("en-US" "fi" "sv")
CUSTOM_OUTPUT_DIR=""
SCENARIO=""
TARGET_DEVICE="all"
CAPTURE_ASSETS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --locale)
      TARGET_LOCALES=("$2")
      shift 2
      ;;
    --device)
      TARGET_DEVICE="$2"
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
    --capture-assets)
      CAPTURE_ASSETS=true
      shift
      ;;
    --all)
      TARGET_LOCALES=("en-US" "fi" "sv")
      TARGET_DEVICE="all"
      shift
      ;;
    -h|--help)
      echo "Usage: Scripts/store-screenshot-ios.sh [--all] [--device <iphone|ipad|all>] [--locale <en-US|fi|sv>] [--scenario <name>] [--capture-assets] [--output-dir <path>]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

ensure_booted() {
  local udid="$1"
  local state
  state="$(python3 -c "
import subprocess, json
out = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '-j']))
for rt, devs in out.get('devices', {}).items():
    for d in devs:
        if d['udid'] == '$udid':
            print(d.get('state', ''))
")"
  if [[ "$state" != "Booted" ]]; then
    echo "==> Booting simulator ($udid)..."
    xcrun simctl boot "$udid"
  fi
  xcrun simctl bootstatus "$udid"
}

set_pristine_status_bar() {
  local udid="$1"
  xcrun simctl ui "$udid" appearance dark
  xcrun simctl status_bar "$udid" override \
    --time "9:41" \
    --batteryState charged \
    --batteryLevel 100 \
    --wifiBars 3 \
    --cellularBars 4
}

sanitize_ipad_status_bar() {
  local file="$1"
  swift - "$file" << 'SWIFTEOF' 2>/dev/null || true
import AppKit
let path = CommandLine.arguments[1]
guard let img = NSImage(contentsOfFile: path),
      let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { exit(0) }
let w = cgImg.width, h = cgImg.height
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(0) }
ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: w, height: h))
let rep = NSBitmapImageRep(cgImage: cgImg)
let bgCol = rep.colorAt(x: 20, y: 20) ?? NSColor.black
ctx.setFillColor(bgCol.cgColor)
ctx.fill(CGRect(x: 88, y: h - 55, width: 345, height: 55))
if let res = ctx.makeImage(), let data = NSBitmapImageRep(cgImage: res).representation(using: .png, properties: [:]) {
    try? data.write(to: URL(fileURLWithPath: path))
}
SWIFTEOF
}

# 1. Resolve iPhone UDID if needed
IPHONE_UDID=""
if [[ "$TARGET_DEVICE" == "all" || "$TARGET_DEVICE" == "iphone" ]]; then
  echo "==> Finding or creating 6.7\"/6.9\" iPhone simulator device..."
  IPHONE_UDID="$(python3 - << 'PYEOF'
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
  echo "Using iPhone simulator UDID: $IPHONE_UDID"
  ensure_booted "$IPHONE_UDID"
  set_pristine_status_bar "$IPHONE_UDID"
fi

# 2. Resolve iPad UDID if needed
IPAD_UDID=""
if [[ "$TARGET_DEVICE" == "all" || "$TARGET_DEVICE" == "ipad" ]]; then
  echo "==> Finding or creating iPad Pro 12.9\" simulator device..."
  IPAD_UDID="$(python3 - << 'PYEOF'
import subprocess, json

def get_ipad_udid():
    out = subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j'])
    data = json.loads(out)
    preferred_names = ['RefineID-Screenshot-iPadPro129', 'iPad Pro (12.9-inch) (6th generation)']
    for runtime, devices in data.get('devices', {}).items():
        if 'iOS' not in runtime:
            continue
        for name in preferred_names:
            for d in devices:
                if name.lower() in d.get('name', '').lower() and d.get('isAvailable', True):
                    return d['udid']
    runtimes = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'runtimes', '-j'])).get('runtimes', [])
    ios_runtimes = [r['identifier'] for r in runtimes if 'iOS' in r.get('name', '') and r.get('isAvailable', True)]
    if not ios_runtimes:
        raise RuntimeError("No available iOS simulator runtime found")
    runtime_id = ios_runtimes[-1]
    created = subprocess.check_output([
        'xcrun', 'simctl', 'create',
        'RefineID-Screenshot-iPadPro129',
        'com.apple.CoreSimulator.SimDeviceType.iPad-Pro-12-9-inch-6th-generation-16GB',
        runtime_id
    ]).decode('utf-8').strip()
    return created

print(get_ipad_udid())
PYEOF
  )"
  echo "Using iPad simulator UDID: $IPAD_UDID"
  ensure_booted "$IPAD_UDID"
  set_pristine_status_bar "$IPAD_UDID"
fi

# Build destination simulator
BUILD_SIM_UDID="${IPHONE_UDID:-$IPAD_UDID}"

echo "==> Building RefineID for iOS/iPadOS Simulator..."
xcodebuild build \
  -project "$REPO_ROOT/RefineID.xcodeproj" \
  -scheme RefineID \
  -destination "platform=iOS Simulator,id=$BUILD_SIM_UDID" \
  -configuration Debug \
  -quiet

DERIVED_DATA_DIR="$(xcodebuild -project "$REPO_ROOT/RefineID.xcodeproj" -scheme RefineID -showBuildSettings -configuration Debug -destination "platform=iOS Simulator,id=$BUILD_SIM_UDID" | grep -m 1 "TARGET_BUILD_DIR =" | awk -F '= ' '{print $2}')"
APP_BUNDLE="$DERIVED_DATA_DIR/RefineID.app"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Error: Built app bundle not found at $APP_BUNDLE" >&2
  exit 1
fi

# Install on targets
if [[ -n "$IPHONE_UDID" ]]; then
  echo "==> Installing app on iPhone simulator..."
  xcrun simctl uninstall "$IPHONE_UDID" fi.refineid.ReFineID 2>/dev/null || true
  xcrun simctl install "$IPHONE_UDID" "$APP_BUNDLE"
fi

if [[ -n "$IPAD_UDID" ]]; then
  echo "==> Installing app on iPad simulator..."
  xcrun simctl uninstall "$IPAD_UDID" fi.refineid.ReFineID 2>/dev/null || true
  xcrun simctl install "$IPAD_UDID" "$APP_BUNDLE"
fi

for LOCALE in "${TARGET_LOCALES[@]}"; do
  LANG_CODE="$LOCALE"
  LOC_SUFFIX="$LOCALE"
  if [[ "$LOCALE" == "en-US" ]]; then
    LANG_CODE="en"
    LOC_SUFFIX="en"
  fi

  if [[ -n "$CUSTOM_OUTPUT_DIR" ]]; then
    IPHONE_OUT_DIR="$CUSTOM_OUTPUT_DIR/$LOCALE/APP_IPHONE_67"
    IPAD_OUT_DIR="$CUSTOM_OUTPUT_DIR/$LOCALE/APP_IPAD_PRO_3GEN_129"
  else
    IPHONE_OUT_DIR="$REPO_ROOT/Metadata/screenshots/$LOCALE/APP_IPHONE_67"
    IPAD_OUT_DIR="$REPO_ROOT/Metadata/screenshots/$LOCALE/APP_IPAD_PRO_3GEN_129"
  fi
  ASSETS_DIR="$REPO_ROOT/Metadata/screenshots/assets"
  mkdir -p "$IPHONE_OUT_DIR" "$IPAD_OUT_DIR" "$ASSETS_DIR"

  # Capture iPhone if targeted
  if [[ -n "$IPHONE_UDID" ]]; then
    echo "==> Capturing iPhone screenshots for locale: $LOCALE..."
    SCENARIO_NAME="${SCENARIO:-registered-nfc}"

    # 1. Main screen
    LAUNCH_ARGS=("-AppleLanguages" "($LANG_CODE)" "-AppleLocale" "$LOCALE" "--hide-diagnostics" "--mock-remote-connected" "--virtual-card" "$SCENARIO_NAME")
    xcrun simctl terminate "$IPHONE_UDID" fi.refineid.ReFineID 2>/dev/null || true
    xcrun simctl launch "$IPHONE_UDID" fi.refineid.ReFineID "${LAUNCH_ARGS[@]}"
    sleep 5
    if [[ "$CAPTURE_ASSETS" == "true" ]]; then
      OUT_FILE="$ASSETS_DIR/iphone-main-${LOC_SUFFIX}.png"
    else
      OUT_FILE="$IPHONE_OUT_DIR/01-app-main.png"
    fi
    xcrun simctl io "$IPHONE_UDID" screenshot "$OUT_FILE"
    echo "    Saved: $OUT_FILE ($(sips -g pixelWidth -g pixelHeight "$OUT_FILE" | awk '/pixel/ {printf "%s ", $2}'))"
    xcrun simctl terminate "$IPHONE_UDID" fi.refineid.ReFineID 2>/dev/null || true

    # 2. Document signing screen
    LAUNCH_ARGS=("-AppleLanguages" "($LANG_CODE)" "-AppleLocale" "$LOCALE" "--hide-diagnostics" "--open-document-signing" "--virtual-card" "$SCENARIO_NAME")
    xcrun simctl launch "$IPHONE_UDID" fi.refineid.ReFineID "${LAUNCH_ARGS[@]}"
    sleep 5
    if [[ "$CAPTURE_ASSETS" == "true" ]]; then
      OUT_FILE="$ASSETS_DIR/iphone-documents-${LOC_SUFFIX}.png"
    else
      OUT_FILE="$IPHONE_OUT_DIR/02-documents.png"
    fi
    xcrun simctl io "$IPHONE_UDID" screenshot "$OUT_FILE"
    echo "    Saved: $OUT_FILE ($(sips -g pixelWidth -g pixelHeight "$OUT_FILE" | awk '/pixel/ {printf "%s ", $2}'))"
    xcrun simctl terminate "$IPHONE_UDID" fi.refineid.ReFineID 2>/dev/null || true
  fi

  # Capture iPad if targeted
  if [[ -n "$IPAD_UDID" ]]; then
    echo "==> Capturing iPad screenshots for locale: $LOCALE..."
    xcrun simctl spawn "$IPAD_UDID" defaults write "Apple Global Domain" AppleLanguages -array "$LANG_CODE" 2>/dev/null || true
    xcrun simctl spawn "$IPAD_UDID" defaults write "Apple Global Domain" AppleLocale -string "$LOCALE" 2>/dev/null || true
    SCENARIO_NAME="${SCENARIO:-activated-reader}"

    # 1. Main screen
    LAUNCH_ARGS=("-AppleLanguages" "($LANG_CODE)" "-AppleLocale" "$LOCALE" "--hide-diagnostics" "--mock-remote-connected" "--virtual-card" "$SCENARIO_NAME")
    xcrun simctl terminate "$IPAD_UDID" fi.refineid.ReFineID 2>/dev/null || true
    xcrun simctl launch "$IPAD_UDID" fi.refineid.ReFineID "${LAUNCH_ARGS[@]}"
    sleep 5
    if [[ "$CAPTURE_ASSETS" == "true" ]]; then
      OUT_FILE="$ASSETS_DIR/ipad-main-${LOC_SUFFIX}.png"
    else
      OUT_FILE="$IPAD_OUT_DIR/01-main.png"
    fi
    xcrun simctl io "$IPAD_UDID" screenshot "$OUT_FILE"
    sanitize_ipad_status_bar "$OUT_FILE"
    echo "    Saved: $OUT_FILE ($(sips -g pixelWidth -g pixelHeight "$OUT_FILE" | awk '/pixel/ {printf "%s ", $2}'))"
    xcrun simctl terminate "$IPAD_UDID" fi.refineid.ReFineID 2>/dev/null || true

    # 2. Document signing screen
    LAUNCH_ARGS=("-AppleLanguages" "($LANG_CODE)" "-AppleLocale" "$LOCALE" "--hide-diagnostics" "--open-document-signing" "--virtual-card" "$SCENARIO_NAME")
    xcrun simctl launch "$IPAD_UDID" fi.refineid.ReFineID "${LAUNCH_ARGS[@]}"
    sleep 5
    if [[ "$CAPTURE_ASSETS" == "true" ]]; then
      OUT_FILE="$ASSETS_DIR/ipad-documents-${LOC_SUFFIX}.png"
    else
      OUT_FILE="$IPAD_OUT_DIR/02-documents.png"
    fi
    xcrun simctl io "$IPAD_UDID" screenshot "$OUT_FILE"
    sanitize_ipad_status_bar "$OUT_FILE"
    echo "    Saved: $OUT_FILE ($(sips -g pixelWidth -g pixelHeight "$OUT_FILE" | awk '/pixel/ {printf "%s ", $2}'))"
    xcrun simctl terminate "$IPAD_UDID" fi.refineid.ReFineID 2>/dev/null || true
  fi
done

if [[ "$CAPTURE_ASSETS" == "true" ]]; then
  echo "==> Re-generating final marketing screenshots via generate-store-screenshots.swift..."
  swift "$REPO_ROOT/Scripts/generate-store-screenshots.swift" --platform all --locale all
fi

echo "==> App Store screenshot generation complete."
