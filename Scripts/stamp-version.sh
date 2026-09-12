#!/usr/bin/env bash
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
# 

# Stamp the calendar release version everywhere it is written.
#
# Run manually when cutting a release; install-macos.sh also runs it,
# so every installed build carries the bucket it was built in.
#
# The version lives in two files, and this stamps both so they never
# drift. Everything the app itself ships derives from the first: the
# Info.plists set no version and inherit these two settings
# (GENERATE_INFOPLIST_FILE), so there is one source for the app.
#
#   Version.xcconfig
#     MARKETING_VERSION (CFBundleShortVersionString) = YY.M.D
#         Release date, no zero padding.
#     CURRENT_PROJECT_VERSION (CFBundleVersion)      = H * 10 + M / 10
#         The ten-minute bucket of UTC the build is cut in. UTC, so it
#         is monotonic across machines and does not repeat an hour at
#         the daylight-saving fall-back.
#
#   PKCS11Bridge/Sources/PKCS11Bridge/ModuleVersion.swift
#     A separate deliverable, the PKCS#11 module, reports its version
#     through the PKCS#11 C API (CK_VERSION), so it needs the version
#     as a compile-time constant it cannot read from a bundle. Stamped
#     to YY.M.D.BUCKET.
#
# A stamp is a three-line diff. It used to be a forty-eight line one,
# because both project settings were written into every target's build
# settings in every configuration; Version.xcconfig exists to keep the
# project file still.
#
# Usage:
#
#   Scripts/stamp-version.sh            # stamp the project
#   Scripts/stamp-version.sh --dry-run  # print the version, change nothing
#   Scripts/stamp-version.sh --tag dev  # stamp, then tag the CURRENT commit
#
# Tagging is opt-in on purpose. Stamping only sets a build number, which
# is wanted often; a tag asserts that a particular commit is a release
# for a named channel, which is a decision and is wanted rarely. The
# channel is one of dev, beta or rc.

set -euo pipefail
cd "$(dirname "$0")/.."

read -r yy mm dd hh mn <<<"$(date -u '+%y %m %d %H %M')"
version="${yy}.$((10#$mm)).$((10#$dd))"
bucket=$((10#$hh * 10 + 10#$mn / 10))

channel=""
case "${1:-}" in
  --dry-run)
    echo "would stamp ${version} (${bucket})"
    exit 0
    ;;
  --tag)
    channel="${2:-}"
    case "$channel" in
      dev | beta | rc) ;;
      *)
        echo "--tag needs a channel: dev, beta or rc" >&2
        exit 2
        ;;
    esac
    ;;
  "") ;;
  *)
    echo "unknown argument: ${1}" >&2
    exit 2
    ;;
esac

# The PKCS#11 module reports its own version through C_GetInfo and
# C_GetTokenInfo, and a module claiming a different build from the app
# it ships with is a support report that starts with a wrong fact.
module_version="PKCS11Bridge/Sources/PKCS11Bridge/ModuleVersion.swift"
sed -i '' -E "s/(internal static let text = \").*(\")/\1${version}.${bucket}\2/" "$module_version"
grep -q "internal static let text = \"${version}.${bucket}\"" "$module_version" ||
  {
    echo "stamping changed nothing in ${module_version}" >&2
    exit 1
  }

config="Version.xcconfig"
sed -i '' -E "s/^(MARKETING_VERSION = ).*/\1${version}/" "$config"
sed -i '' -E "s/^(CURRENT_PROJECT_VERSION = ).*/\1${bucket}/" "$config"

# sed reports nothing when a pattern matches nothing, and a stamp that
# silently changed no version would be found at the next release.
grep -q "^MARKETING_VERSION = ${version}$" "$config" &&
  grep -q "^CURRENT_PROJECT_VERSION = ${bucket}$" "$config" ||
  { echo "stamp did not take in ${config}; check its two settings" >&2; exit 1; }

if [[ -n "$channel" ]]; then
  tag="ios-v${version}-${channel}.${bucket}"
  # The stamp itself is left uncommitted deliberately: the tag names the
  # commit that is already reviewed, and quietly committing a version
  # on the way to tagging would hide a change nobody read.
  if ! git diff --quiet -- "$config"; then
    echo "stamped ${version} (${bucket}), NOT tagged: commit the stamp first, then re-run" >&2
    exit 1
  fi
  git tag -a "$tag" -m "RefineID ${version} (${bucket}), ${channel}"
  echo "stamped ${version} (${bucket}) and tagged ${tag}. Push it with: git push origin ${tag}"
  exit 0
fi

echo "stamped ${version} (${bucket}). Next: review the diff, commit, then Scripts/stamp-version.sh --tag <channel>"
