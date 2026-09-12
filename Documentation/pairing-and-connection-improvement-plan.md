# Pairing Usability, Security Analysis, and Connection Stability Plan

## 1. Summary

This document specifies the improvements to the RefineID Authenticated Peer
Protocol (RAPP) pairing experience, security threat model, and persistent
connection lifecycle between borrowing devices (iPad, Mac) and card-holding
devices (iPhone).

## 2. 6-Character Hyphen-Free Pairing Code

### 2.1 Specification
- Replace the 8-character hyphenated pairing code format (`ABCD-1234`) with
  a 6-character alphanumeric code without punctuation (`0-9`, `A-Z`, or
  Crockford Base32).
- Example: `K7P9M2`.

### 2.2 Entropy and Security Analysis
- **Alphabet**: 36 symbols (`[0-9, A-Z]`) yields 5.17 bits per character.
- **Search Space**: $36^6 = 2,176,782,336$ combinations (~31.0 bits of entropy).
- **Time-to-Live (TTL)**: 180 seconds (3 minutes) before automatic offer expiration.
- **On-Link Constraint**: RAPP pairing listeners are published only on the local
  network via mDNS (`_refineid-stream._tcp`). Off-path remote attackers cannot
  reach the listener.
- **Online Guessing Bound**: At a network rate of 100 connection attempts/sec, an
  attacker can test at most 18,000 codes in the 180-second window:
  $$\text{Collision Probability} = \frac{18,000}{2,176,782,336} \approx 0.00083\% \quad (1 \text{ in } 120,000)$$
- **Comparison to Standards**:
  - Bluetooth Secure Simple Pairing: 6 decimal digits ($10^6$ combinations, ~20 bits).
  - Apple AirPlay / HomeKit PIN: 4 decimal digits ($10^4$ combinations, ~13.3 bits).
  - A 6-character alphanumeric code provides over $2,176\times$ the entropy of standard
    Bluetooth passkey pairing.

### 2.3 User Experience Benefits
- Eliminates keyboard mode switching between letters and symbols on iOS/iPadOS.
- Fits standard auto-advancing 6-cell verification input components.
- Crockford Base32 variant eliminates confusing glyphs (`0/O`, `1/I/L`).

## 3. Zero-Knowledge Diffie-Hellman Key Exchange

### 3.1 Handshake (Noise XXpsk3 over Curve25519)
- Both devices generate ephemeral Curve25519 Diffie-Hellman keypairs.
- The 6-character code is hashed with SHA-256 and mixed into the cryptographic
  transcript state using HKDF.
- The pairing code is never transmitted in plaintext over the wire.
- Passive or active network eavesdroppers cannot deduce the pairing code from
  the recorded packet stream.

### 3.2 Long-Term Key Vaulting
- Upon handshake completion, the pairing code is discarded from memory.
- The resulting mutual static Curve25519 public keys, a unique `pairID`, and a
  256-bit `rendezvousToken` are stored securely in `RappDeviceVault` (backed by the
  system Keychain).

## 4. Self-Healing Connection Stability and Silent Rendezvous

### 4.1 Reconnection without Pairing Codes
- If the network drops or the application restarts, devices reconnect without
  prompting the user for a new code.
- Discovery occurs via hashed mDNS service names:
  $$\text{Service Name} = \text{"rf-"} + \text{SHA256}(\text{rendezvousToken})[0\dots 16]$$
- Reconnections authenticate mutually via static Diffie-Hellman keys.

### 4.2 CryptoTokenKit State Continuity
- `PersistentTokenRegistry` restores published identities on launch.
- Safari mTLS sessions proceed without redundant reader roundtrips.

## 5. Automated Test Orchestration

- `Scripts/pair-devices.sh` automates the offer and acceptance ceremony between
  the iPad simulator and physical iPhone test harness.
- `refineid-android/scripts/test-pairing-e2e.sh` automates the cross-platform
  pairing test between macOS (`--offer-remote-reader`) and attached Android
  hardware via ADB with zero manual interaction.
- `SafariCardLoginUITests.swift` includes pre-flight validation
  (`ensureCryptoTokenIdentityReady`) to verify active CryptoTokenKit publishing
  prior to driving browser flows.

## 6. Automatic Same-AppleID Pairing (Noise IK)

For devices sharing the same Apple ID account, see the full specification in
[`Documentation/same-apple-id-automatic-pairing.md`](same-apple-id-automatic-pairing.md).
It details zero-interaction key distribution via private iCloud sync and direct
pre-authenticated Noise IK handshakes.
