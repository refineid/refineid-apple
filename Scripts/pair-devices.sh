#!/bin/sh
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
set -e

IPAD_UDID="${IPAD_UDID:-$(xcrun simctl list devices 2>/dev/null | grep -i "iPad" | grep "Booted" | grep -o -E "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | head -n 1 || true)}"
IPHONE_UDID="${IPHONE_UDID:-$(xcrun devicectl list devices 2>/dev/null | grep -E "iPhone|iPad" | grep -w "physical" | awk '{ for (i = 2; i <= NF; i++) if ($i == "(UDID)") { print $(i - 1); exit } }' || true)}"
OFFER_LOG="/tmp/ipad_pairing_offer.log"

if [ -z "$IPAD_UDID" ]; then
  echo "Error: No booted iPad simulator found. Start an iPad simulator first or set IPAD_UDID." >&2
  exit 1
fi

if [ -z "$IPHONE_UDID" ]; then
  echo "Error: No connected physical iOS device found. Connect a device or set IPHONE_UDID." >&2
  exit 1
fi

echo "==> Driving automated pairing between iPhone ($IPHONE_UDID) and iPad simulator ($IPAD_UDID)..."
rm -f "$OFFER_LOG"

# 1. Terminate running instances
xcrun simctl terminate "$IPAD_UDID" fi.refineid.ReFineID 2>/dev/null || true

# 2. The iPhone holds the card, so it shows the code (RAPP v26.10.1 section 3).
echo "==> Showing a pairing code on the iPhone..."
xcrun devicectl device process launch \
  --device "$IPHONE_UDID" \
  --terminate-existing \
  --console \
  fi.refineid.ReFineID --offer-remote-reader > "$OFFER_LOG" 2>&1 &
CUSTODIAN_PID=$!

CODE=""
for i in $(seq 1 60); do
  if grep -q "offer-remote-reader: offer " "$OFFER_LOG" 2>/dev/null; then
    CODE=$(grep "offer-remote-reader: offer " "$OFFER_LOG" | head -n 1 | awk '{print $3}')
    break
  fi
  sleep 0.5
done

if [ -z "$CODE" ]; then
  echo "Error: Failed to obtain the pairing code from the iPhone."
  cat "$OFFER_LOG"
  exit 1
fi

# 3. The iPad requester types the code.
echo "==> Typing the pairing code on the iPad simulator..."
SIMCTL_CHILD_REFINEID_PAIR_OFFER="$CODE" \
  xcrun simctl launch --console "$IPAD_UDID" fi.refineid.ReFineID --pair-with-offer

wait "$CUSTODIAN_PID" || true
echo "==> Pairing ceremony completed between iPhone and iPad."
