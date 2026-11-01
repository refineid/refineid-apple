#!/bin/sh
# Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.
#
# Makes this Mac trust DVV's test certificate chain, so Safari offers a DVV
# test card's identity for TLS client authentication.
#
# Safari offers a smart-card identity only when its chain evaluates to a
# trusted anchor; without one it answers the server's certificate request
# with no certificate and shows no picker. Production DVV cards chain to
# the DVV Gov. Root CA G3 roots; DVV test cards (personal and organisation)
# chain to DVV TEST Root CA G3 RSA or ECC instead.
#
# Nothing is taken from this repository: each certificate is downloaded
# from DVV's CA distribution point and accepted only when its SHA-256
# equals the one DVV publishes on its test CA page, fetched over HTTPS.
# The roots are added to the System keychain as trusted roots and the test
# issuing CAs as plain certificates.
#
# Usage: Scripts/trust-dvv-test-roots.sh   (asks for the admin password)
set -eu

CA_BASE='http://proxy.fineid.fi/ca'
PAGE='https://dvv.fi/en/test-ca-certificates'
KEYCHAIN='/Library/Keychains/System.keychain'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

curl -fsSL "$PAGE" -o "$work/page.html"
python3 -I - "$work/page.html" > "$work/page.txt" <<'EOF'
import html
import re
import sys

with open(sys.argv[1], encoding="utf-8") as page:
    text = html.unescape(re.sub(r"<[^>]+>", " ", page.read()))
print(re.sub(r"\s+", " ", text))
EOF

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

fetch_verified dvvtest3rc 'DVV TEST Root CA - G3 RSA'
fetch_verified dvvtest3ec 'DVV TEST Root CA - G3 ECC'
fetch_verified dvvtp5rc 'DVV TEST Certificates - G5R'
fetch_verified dvvtp5ec 'DVV TEST Certificates - G5E'

sudo security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN" "$work/dvvtest3rc.der"
sudo security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN" "$work/dvvtest3ec.der"
for intermediate in dvvtp5rc dvvtp5ec; do
  sudo security add-certificates -k "$KEYCHAIN" "$work/$intermediate.der" 2>/dev/null \
    || echo "$intermediate is already in the System keychain."
done
echo "DVV test roots trusted; DVV TEST Certificates G5R and G5E added."
