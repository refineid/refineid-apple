#!/bin/sh
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Makes this Mac trust DVV's test certificate chain, or stops trusting it,
# so Safari offers a DVV test card's identity for TLS client authentication.
#
# Safari offers a smart-card identity only when its chain evaluates to a
# trusted anchor; without one it answers the server's certificate request
# with no certificate and shows no picker. Production DVV cards chain to
# the DVV Gov. Root CA G3 roots; DVV test cards (personal and organisation)
# chain to DVV TEST Root CA G3 RSA or ECC instead.
#
# install: nothing is taken from this repository. Each certificate is
# downloaded from DVV's CA distribution point and accepted only when its
# SHA-256 equals the one DVV publishes on its test CA page, fetched over
# HTTPS. The roots are added to the System keychain as trusted roots and
# the test issuing CAs as plain certificates.
#
# uninstall: removes the roots' trust settings and deletes the four
# certificates from the System keychain, found by name.
#
# Usage: Scripts/trust-dvv-test-roots.sh install|uninstall
#        (asks for the admin password)
set -eu

CA_BASE='http://proxy.fineid.fi/ca'
PAGE='https://dvv.fi/en/test-ca-certificates'
KEYCHAIN='/Library/Keychains/System.keychain'
ROOTS='dvvtest3rc:DVV TEST Root CA - G3 RSA
dvvtest3ec:DVV TEST Root CA - G3 ECC'
INTERMEDIATES='dvvtp5rc:DVV TEST Certificates - G5R
dvvtp5ec:DVV TEST Certificates - G5E'

usage() {
  echo "Usage: $0 install|uninstall" >&2
  exit 2
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The SHA-256 DVV publishes right after a certificate's name.
published_sha256() {
  python3 -I - "$work/page.txt" "$1" <<'EOF'
import re
import sys

with open(sys.argv[1], encoding="utf-8") as page:
    text = page.read()
match = re.search(re.escape(sys.argv[2]) + r" ([0-9a-f]{64})\b", text)
print(match.group(1) if match else "")
EOF
}

# Downloads one certificate and checks it against DVV's published hash.
fetch_verified() { # file name
  curl -fsSL "$CA_BASE/$1.crt" -o "$work/$1.der"
  expected=$(published_sha256 "$2")
  actual=$(shasum -a 256 "$work/$1.der" | cut -d ' ' -f 1)
  if [ -z "$expected" ]; then
    echo "DVV's test CA page lists no SHA-256 for \"$2\"; nothing installed." >&2
    exit 1
  fi
  if [ "$expected" != "$actual" ]; then
    echo "\"$2\" from $CA_BASE/$1.crt does not match DVV's published SHA-256; nothing installed." >&2
    exit 1
  fi
}

install() {
  curl -fsSL "$PAGE" -o "$work/page.html"
  python3 -I - "$work/page.html" > "$work/page.txt" <<'EOF'
import html
import re
import sys

with open(sys.argv[1], encoding="utf-8") as page:
    text = html.unescape(re.sub(r"<[^>]+>", " ", page.read()))
print(re.sub(r"\s+", " ", text))
EOF
  printf '%s\n%s\n' "$ROOTS" "$INTERMEDIATES" | while IFS=: read -r file name; do
    fetch_verified "$file" "$name"
  done
  printf '%s\n' "$ROOTS" | while IFS=: read -r file name; do
    sudo security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN" "$work/$file.der"
  done
  printf '%s\n' "$INTERMEDIATES" | while IFS=: read -r file name; do
    sudo security add-certificates -k "$KEYCHAIN" "$work/$file.der" 2>/dev/null \
      || echo "$name is already in the System keychain."
  done
  echo "DVV test roots trusted; DVV TEST Certificates G5R and G5E added."
}

# Deletes every System keychain certificate with exactly this name, and
# its admin trust settings first when it is a root.
remove_named() { # name is_root
  security find-certificate -a -c "$1" -Z "$KEYCHAIN" 2>/dev/null \
    | awk '/^SHA-1 hash:/ { print $3 }' > "$work/hashes"
  if [ ! -s "$work/hashes" ]; then
    echo "$1 is not in the System keychain."
    return
  fi
  while read -r hash; do
    if [ "$2" = root ]; then
      security find-certificate -a -c "$1" -Z -p "$KEYCHAIN" \
        | awk -v h="$hash" '/^SHA-1 hash:/ { keep = ($3 == h) } keep && !/^SHA/' \
        > "$work/root.pem"
      sudo security remove-trusted-cert -d "$work/root.pem" 2>/dev/null || true
    fi
    sudo security delete-certificate -Z "$hash" "$KEYCHAIN"
  done < "$work/hashes"
  echo "$1 removed."
}

uninstall() {
  printf '%s\n' "$ROOTS" | while IFS=: read -r file name; do
    remove_named "$name" root
  done
  printf '%s\n' "$INTERMEDIATES" | while IFS=: read -r file name; do
    remove_named "$name" intermediate
  done
}

[ $# -eq 1 ] || usage
case "$1" in
  install) install ;;
  uninstall) uninstall ;;
  *) usage ;;
esac
