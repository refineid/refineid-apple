#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
# 

# Build, verify and install RefineID into /Applications on this Mac.
#
# /Applications is the only place a copy may live. A CryptoTokenKit
# driver is registered by the system from wherever it finds the bundle,
# so every stray copy -- a DerivedData build, a /tmp build, a second one
# in ~/Applications -- becomes a competing registration for the same
# driver class. The system then picks one, silently, and it is not
# necessarily the one being edited. This script installs to
# /Applications and removes the rest.
#
# The signature is checked before installing, and a revoked certificate
# fails the run. That is not a formality: a revoked certificate does not
# merely warn, it stops launchd from spawning the token extension at all
# (POSIX 163, "Launchd job spawn failed"). ctkd then reports "no token
# driver found" for a perfectly good card, Safari is offered no
# identity, and the site never asks for a certificate -- which looks
# exactly like a bug in this app and is not one.
#
# Usage:
#
#   Scripts/install-macos.sh                 build, verify, install, launch
#   Scripts/install-macos.sh --check         verify what is installed
#   Scripts/install-macos.sh --configuration Release
#
set -euo pipefail
cd "$(dirname "$0")/.."

app_name="RefineID.app"
installed="/Applications/${app_name}"
derived_data="/tmp/refineid-macos-install"
configuration="Debug"
check_only="no"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) check_only="yes"; shift ;;
    --configuration) configuration="${2:?--configuration needs a value}"; shift 2 ;;
    *) echo "usage: $0 [--check] [--configuration NAME]" >&2; exit 2 ;;
  esac
done

# Every install carries the ten-minute bucket it was built in, so the
# About window answers "am I running the copy just installed?" - a
# build number that only moved on release cuts could not.
if [[ "$check_only" == "no" ]]; then
  Scripts/stamp-version.sh
fi

fail() { echo "install-macos: $*" >&2; exit 1; }
note() { echo "install-macos: $*"; }

# Every signing identity this Mac could use, and whether it is usable.
# `security` reports a revoked certificate as a valid identity with a
# parenthesised error, so the error is what has to be read.
report_identities() {
  note "code-signing identities:"
  security find-identity -v -p codesigning 2>/dev/null | sed 's/^/  /'
}

# Refuses anything the system will not launch: a broken seal, or a
# certificate that has been revoked since the bundle was signed.
verify_signature() {
  local bundle="$1"
  local output
  if ! output="$(codesign --verify --deep --strict "$bundle" 2>&1)"; then
    echo "$output" | sed 's/^/  /' >&2
    if echo "$output" | grep -q "CSSMERR_TP_CERT_REVOKED"; then
      report_identities >&2
      fail "the signing certificate is REVOKED. launchd will refuse to spawn the
  token extension, ctkd will report no token driver for the card, and
  Safari will never be offered an identity. Issue a new development
  certificate in Xcode (Settings > Accounts > Manage Certificates) and
  run this again."
    fi
    fail "signature verification failed for ${bundle}"
  fi
  note "signature valid: $(codesign -dvv "$bundle" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
}

# Any macOS copy outside /Applications is a competing driver
# registration. iOS build products are left alone: they carry no
# `Contents/MacOS`, cannot be loaded here, and deleting them would throw
# away device builds for no benefit.
is_macos_bundle() {
  [[ -d "$1/Contents/MacOS" ]]
}

lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks"
lsregister="${lsregister}/LaunchServices.framework/Support/lsregister"

# Deleting a bundle does not withdraw what Launch Services recorded
# about it, and an iOS bundle that is rightly left on disk still claims
# our identifier. Launch Services answers identifier lookups with one
# winner among the claimants, so a stray decides what the Dock and the
# switcher draw for the running app, and a build product that carries no
# macOS icon draws nothing at all. Withdrawing the claim costs a device
# build nothing: rebuilding it registers the bundle again.
unregister_copy() {
  [[ -x "$lsregister" ]] || return 0
  "$lsregister" -u "$1" 2>/dev/null || true
}

# Build products are not documents. Left indexed, every configuration of
# every checkout answers a search for the app by name, and the one copy
# that may be launched is buried among them.
# The marker is placed before the build runs, because a tree is indexed
# as it is written and a marker added afterwards only stops the next
# pass.
hide_from_spotlight() {
  mkdir -p "$1" 2>/dev/null || return 0
  touch "$1/.metadata_never_index" 2>/dev/null || true
}

remove_stray_copies() {
  local found=0
  local candidates
  candidates="$(
    {
      mdfind -name "$app_name" 2>/dev/null | grep -F "/${app_name}" || true
      # Deep enough to reach a build nested inside a scratch directory:
      # /private/tmp/<agent>/<session>/scratchpad/<build>/Build/Products/
      # <configuration>/RefineID.app is already nine levels down.
      # The build/ directory in this checkout holds the archives a
      # release is cut from, which mdfind stops reporting once the tree
      # is hidden from the index.
      find /Applications -maxdepth 1 -name ".*${app_name}*" -type d 2>/dev/null || true
      for root in /tmp /private/tmp "$HOME/Library/Developer/Xcode/DerivedData" \
        build derivedData; do
        [[ -d "$root" ]] || continue
        find "$root" -maxdepth 12 -name "$app_name" -type d 2>/dev/null || true
      done
    } | sort -u
  )"
  local built_real=""
  if [[ -n "${built:-}" && -d "$built" ]]; then
    built_real="$(cd "$built" 2>/dev/null && pwd -P || true)"
  fi
  while IFS= read -r stray; do
    [[ -z "$stray" ]] && continue
    [[ "$stray" == "$installed" ]] && continue
    [[ "$stray" == *".xcarchive/"* ]] && continue
    local stray_real=""
    if [[ -d "$stray" ]]; then
      stray_real="$(cd "$stray" 2>/dev/null && pwd -P || true)"
    fi
    if [[ -n "$built_real" && -n "$stray_real" && "$stray_real" == "$built_real" ]]; then
      continue
    fi
    unregister_copy "$stray"
    unregister_token_plugins "$stray"
    if ! is_macos_bundle "$stray"; then
      note "unregistered non-macOS copy: $stray"
      continue
    fi
    note "removing stray macOS copy: $stray"
    rm -rf "$stray"
    found=$((found + 1))
  done <<<"$candidates"
  [[ "$found" -eq 0 ]] && note "no stray macOS copies found"
  return 0
}

# Build trees from earlier sessions, which are scratch and not history.
#
# Each debugging session leaves a derived-data tree or an archive in the
# temporary directory, and they are hundreds of megabytes each.
#
# A week, because the age is the only evidence this has that a tree is
# nobody's. Hours do not cover a single session, let alone the baseline
# someone kept from yesterday to compare against; anything younger is
# assumed to belong to work still in progress, possibly another
# worker's. Three things are spared outright: the tree this run uses,
# anything git knows as a worktree -- removing one of those behind
# git's back leaves metadata pointing at nothing -- and everything
# newer than the cut-off. What is removed is named, with its size.
remove_stale_build_trees() {
  local minimum_age_days=7
  local minimum_age_minutes=$((minimum_age_days * 24 * 60))
  local worktrees
  worktrees="$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')"
  local freed=0
  local tree
  while IFS= read -r tree; do
    [[ -z "$tree" ]] && continue
    [[ "$tree" == "$derived_data" ]] && continue
    grep -qxF "$tree" <<<"$worktrees" && continue
    local size
    size="$(du -sh "$tree" 2>/dev/null | cut -f1)"
    note "removing stale build tree (${size}): $tree"
    rm -rf "$tree"
    freed=$((freed + 1))
  done < <(
    find /private/tmp -maxdepth 1 -mindepth 1 \
      \( -iname 'refineid*' -o -iname 'RefineID*' \) \
      -mmin "+${minimum_age_minutes}" 2>/dev/null | sort
  )
  [[ "$freed" -eq 0 ]] && note "no stale build trees found"
  return 0
}

# What the system currently believes about our driver.
report_registrations() {
  note "registered CryptoTokenKit drivers for this app:"
  pluginkit -m -p com.apple.ctk-tokens -vvv 2>/dev/null \
    | grep -A2 "fi.refineid" | sed 's/^/  /' || note "  (none registered)"
  note "what the smart-card system sees:"
  system_profiler SPSmartCardsDataType 2>/dev/null \
    | sed -n '/SmartCard Drivers/,/Available SmartCards (keychain)/p' \
    | grep -i refineid | sed 's/^/  /' || note "  (no RefineID driver listed)"
}

# Whether the built extension would run the same code as the installed
# one.
#
# The binaries alone, not the bundle: every install stamps a fresh
# build number into Info.plist, so comparing bundles would find a
# difference every time and ask for the card back for a change ctkd
# never executes.
#
# Every executable in the appex, not just the named one: a Debug
# build carries its code in RefineIDTokenExtension.debug.dylib and
# leaves the executable a loader stub, so the stub matches across any
# code change and answered "unchanged" for builds that were not.
extension_is_unchanged() {
  local name built_dir live_dir binary live_binary
  for name in RefineIDTokenExtension RefineIDRappTokenExtension; do
    built_dir="${built}/Contents/PlugIns/${name}.appex/Contents/MacOS"
    live_dir="${installed}/Contents/PlugIns/${name}.appex/Contents/MacOS"
    [[ -d "$built_dir" ]] || continue
    [[ -d "$live_dir" ]] || return 1
    for binary in "$built_dir"/*; do
      [[ -f "$binary" ]] || continue
      live_binary="${live_dir}/$(basename "$binary")"
      [[ -f "$live_binary" ]] || return 1
      [[ "$(unsigned_hash "$binary")" == "$(unsigned_hash "$live_binary")" ]] || return 1
    done
  done
}

# A binary's hash with its signature removed.
#
# Signing embeds a fresh signature on every build, so two binaries
# compiled from identical sources never match byte for byte. What has
# to match is the code.
unsigned_hash() {
  local scratch
  scratch="$(mktemp -t refineid-appex.XXXXXX)" || return 1
  cp "$1" "$scratch"
  codesign --remove-signature "$scratch" >/dev/null 2>&1 || true
  shasum -a 256 "$scratch" | cut -d' ' -f1
  rm -f "$scratch"
}

# The iOS Simulator process is also named RefineID. Only the macOS
# bundle layout has Contents/MacOS, so a name match would terminate
# a simulator install this script does not own.
macos_app_is_running() {
  pgrep -f "/RefineID.app/Contents/MacOS/RefineID" >/dev/null 2>&1
}

# Ends every macOS RefineID process so the bundle can be replaced.
kill_macos_app() {
  local pid
  macos_app_is_running || return 0
  note "killing the running macOS app"
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    kill -KILL "$pid" 2>/dev/null || true
  done < <(pgrep -f "/RefineID.app/Contents/MacOS/RefineID" || true)
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    macos_app_is_running || return 0
    sleep 0.1
  done
}

# Withdraws every CryptoTokenKit plugin the bundle registered, so a
# deleted copy cannot keep answering as the live driver.
unregister_token_plugins() {
  local bundle="$1"
  local plugin
  [[ -d "$bundle/Contents/PlugIns" ]] || return 0
  for plugin in "$bundle/Contents/PlugIns/"*.appex; do
    [[ -d "$plugin" ]] || continue
    pluginkit -r "$plugin" 2>/dev/null || true
  done
}

# Registers every CryptoTokenKit plugin in the installed bundle. The
# remote-card driver is a second appex beside the local-card one, and
# registering only the first leaves pairing answering from a stray.
register_token_plugins() {
  local bundle="$1"
  local plugin
  local registered=0
  [[ -d "$bundle/Contents/PlugIns" ]] || return 1
  for plugin in "$bundle/Contents/PlugIns/"*.appex; do
    [[ -d "$plugin" ]] || continue
    if pluginkit -a "$plugin" 2>/dev/null; then
      note "extension registered: $(basename "$plugin")"
      registered=1
    fi
  done
  [[ "$registered" -ne 0 ]]
}

# A card insertion is CryptoTokenKit's supported discovery boundary.
# Replacing a live extension leaves ctkd holding the old token and
# executable; restarting ctkd only strands the reader daemons on dead
# XPC endpoints. Leave the reader connected and remove only the card.
card_is_inserted() {
  system_profiler SPSmartCardsDataType 2>/dev/null | grep -q "ATR:"
}

refineid_identity_is_live() {
  sc_auth identities 2>/dev/null | grep -q "fi.refineid"
}

wait_for_card_release() {
  card_is_inserted || return 0
  if [[ ! -t 0 ]]; then
    fail "a card is inserted. Remove only the card, leave the USB reader connected, and run this again."
  fi
  note "remove the card; leave the USB reader connected"
  while card_is_inserted; do
    sleep 1
  done
  note "card removed; waiting for CryptoTokenKit to withdraw its token"
  for _ in 1 2 3 4 5; do
    refineid_identity_is_live || return 0
    sleep 1
  done
  fail "CryptoTokenKit still publishes the removed card. Log out before replacing the extension."
}

# PlugInKit may retain an idle extension process briefly after its card
# leaves. Ending our processes is sufficient; the next insertion starts
# the copy inside the newly installed app.
stop_refineid_extensions() {
  pkill -f "/RefineIDTokenExtension.appex/Contents/MacOS/RefineIDTokenExtension" \
    2>/dev/null || true
  pkill -f "/RefineIDDiscoveryExtension.appex/Contents/MacOS/RefineIDDiscoveryExtension" \
    2>/dev/null || true
  pkill -f "/RefineIDRappTokenExtension.appex/Contents/MacOS/RefineIDRappTokenExtension" \
    2>/dev/null || true
}

if [[ "$check_only" == "yes" ]]; then
  [[ -d "$installed" ]] || fail "nothing installed at ${installed}"
  verify_signature "$installed"
  report_registrations
  exit 0
fi

hide_from_spotlight "$derived_data"
hide_from_spotlight "$HOME/Library/Developer/Xcode/DerivedData"
hide_from_spotlight build
hide_from_spotlight derivedData

note "building ${configuration} for macOS"
xcodebuild \
  -project RefineID.xcodeproj \
  -scheme RefineID \
  -configuration "$configuration" \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data" \
  -allowProvisioningUpdates \
  CLANG_COVERAGE_MAPPING=NO \
  ENABLE_CODE_COVERAGE=NO \
  -quiet \
  build

built="${derived_data}/Build/Products/${configuration}/${app_name}"
[[ -d "$built" ]] || fail "build produced no ${app_name}"

# Verified BEFORE anything is replaced, so a bad certificate leaves the
# working copy in place rather than a broken one.
verify_signature "$built"

remove_stray_copies
kill_macos_app
# The card boundary belongs to the token extension, not to the window.
# Replacing a live extension leaves ctkd holding the old executable, so
# that replacement waits for the card to leave; a build whose extension
# is byte for byte the one already installed replaces nothing the card
# is using, and asking for the card back would be a ritual.
if extension_is_unchanged; then
  note "extension unchanged; installing without asking for the card"
else
  wait_for_card_release
fi
# Always: the bundle underneath a running extension is about to be
# replaced, and a process left running on a replaced bundle answers
# nothing. ctkd then waits ten seconds per request and the app hangs
# at launch with its icon bouncing. Ending it needs no card.
stop_refineid_extensions

note "installing to ${installed}"
unregister_token_plugins "$installed"
rm -rf "$installed"
cp -R "$built" "$installed"
verify_signature "$installed"

# The extensions are registered directly. Launching the app only to make
# the system notice them, then quitting it again, put a window on screen
# and took it away on every install.
note "registering the extensions"
if ! register_token_plugins "$installed"; then
  note "pluginkit refused; launching the app once so the system sees it"
  open -g -a "$installed"
  sleep 3
  kill_macos_app
fi

note "launching ${installed}"
open "$installed"
note "done. Insert the card; CryptoTokenKit will mint it with the new driver."
