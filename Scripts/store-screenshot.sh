#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
# 

# Capture the frontmost RefineID window onto an App-Store-ready
# canvas: 2880x1800 (16:10), window centred, dark background.
#
#   Scripts/store-screenshot.sh NAME
#
# Writes ~/Desktop/refineid-store-screenshots/NAME.png. Screenshots
# for the store carry synthetic or redacted data only: capture the
# no-card and document states, never a real holder's identity.

set -euo pipefail

name="${1:?usage: store-screenshot.sh NAME}"
out_dir="$HOME/Desktop/refineid-store-screenshots"
mkdir -p "$out_dir"

bounds="$(osascript -e '
  tell application "System Events" to tell (first process whose name is "RefineID")
    set p to position of window 1
    set s to size of window 1
    return ((item 1 of p) as text) & "," & ((item 2 of p) as text) & "," & ((item 1 of s) as text) & "," & ((item 2 of s) as text)
  end tell')"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
screencapture -o -R "$bounds" "$work/window.png"

# 2880x1800 is the largest accepted 16:10 size; padColor keeps the
# window on a calm dark field matching the app.
sips -p 1800 2880 --padColor 1C1C1E \
  "$work/window.png" --out "$out_dir/$name.png" >/dev/null

echo "wrote $out_dir/$name.png"
