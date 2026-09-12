# Private Card Departure Signaling and Real-Time Token Withdrawal Plan

## 1. Executive Summary

This document specifies the architecture, threat model, and cryptographic protocol
design for real-time, privacy-preserving smart card departure notification in the
RefineID Authenticated Peer Protocol (RAPP).

When a citizen smart card is physically removed from a card reader connected to an
iPhone, macOS must withdraw the borrowed CryptoTokenKit (CTK) token immediately
(< 50 ms) without waiting for network timeouts. Crucially, this signaling must be
cryptographically confidential: **no third party or network eavesdropper on the local
network may learn that a card has been inserted or removed.**

---

## 2. Problem Analysis & Current State

### 2.1 The Latency Problem
Under the current transaction-oriented RAPP stream design:
1. **Transaction-scoped TCP connections**:
   The Mac dials the iPhone to read the authentication certificate or compute a signature,
   completes the operation, and closes the TCP socket. Between operations (while idle),
   no persistent TCP connection is held.
2. **30-Second Bonjour Debounce Hold**:
   Idle device availability is monitored on macOS via Bonjour mDNS browsing
   (`StreamRelayPresence`). Because Wi-Fi multicast and mDNS packets frequently drop in
   real-world environments, [`PersistentTokenRegistry+Presence.swift`](../Sources/App/PersistentTokenRegistry+Presence.swift)
   implements a 30-second hold:
   ```swift
   private static let advertisementLossHoldSeconds = 30
   ```
   If the iPhone stops advertising, the Mac intentionally delays 30 seconds before
   withdrawing the borrowed identity.
3. **NFC Prime Masking on iOS**:
   In [`HolderCardServing.swift`](../Sources/App/HolderCardServing.swift):
   ```swift
   let canServe = PrimeStore.storedCount() > 0 || CardPresence.shared.isReaderCardPresent
   ```
   If an NFC card was previously primed on the phone, `canServe` remains `true` even
   when the physical card reader is disconnected. The iPhone continues advertising, so
   the Mac never receives an absence signal.

### 2.2 Security & Privacy Threat Model

In shared or untrusted network environments (e.g., public Wi-Fi, coffee shops, hotels,
corporate LANs, or co-working spaces):
- **Eavesdropping on Cleartext Broadcasts**:
  Any station on the same subnet can monitor mDNS queries, responses, and TXT records.
- **Side-Channel Information Leakage**:
  - Broadcasting card availability changes in unencrypted mDNS TXT records (e.g.,
    `card=0` / `card=1`) leaks physical presence, user activity, and card insertion
    timing to passive observers.
  - Toggling the Bonjour service advertisement on and off with card insertion/removal
    leaks user behavioral telemetry and enables correlation attacks.
- **Requirement**:
  **Card presence and departure must remain strictly confidential between the paired
  devices.** Network observers must see only uniform, opaque encrypted packets.

---

## 3. Cryptographic & Protocol Architecture

```
┌────────────────────────────────────────────────────────┐
│                        iPhone                          │
│  [Smart Card Reader] ──> Physical Card Removed         │
│          │                                             │
│          ▼                                             │
│  TKSmartCardSlotManager detects removal                │
│          │                                             │
│          ▼                                             │
│  Encrypted RAPP Frame: session.close(card_unavailable) │
└──────────────────────────┬─────────────────────────────┘
                           │ Noise AEAD Tunnel
                           │ (ChaCha20-Poly1305)
                           ▼
┌────────────────────────────────────────────────────────┐
│                         macOS                          │
│  RappPersistentRequesterClient decrypts frame          │
│          │                                             │
│          ▼                                             │
│  RappConnectionCoordinator: .closed(cardUnavailable)   │
│          │                                             │
│          ▼                                             │
│  PersistentTokenRegistry: IMMEDIATE WITHDRAWAL (<50ms) │
│  (CryptoTokenKit identity removed from system)         │
└────────────────────────────────────────────────────────┘
```

### 3.1 Static, Opaque Rendezvous Identity
- The phone advertises only an opaque, pseudorandom service name derived from the
  pre-shared pairing secret:
  $$\text{Service Name} = \text{"rf-"} + \text{HMAC-SHA256}(\text{rendezvousToken}, \text{"stream-rendezvous"})[0\dots 16]$$
- No plaintext metadata (no device names, user names, cardholder identifiers, SATU,
  or presence attributes) is included in the mDNS TXT records.
- The advertisement remains constant while the application is active and paired,
  preventing external timing correlation based on advertisement toggling.

### 3.2 In-Band Encrypted Control Session
- While a reader-backed card is active and its identity is borrowed by macOS, a
  persistent, lightweight authenticated RAPP session is maintained between the Mac
  and iPhone.
- The transport is encrypted and authenticated using the Noise Protocol framework
  with `ChaCha20-Poly1305` authenticated encryption with associated data (AEAD)
  and ephemeral session keys.
- Lightweight authenticated liveness pings (`liveness.ping` / `liveness.pong`)
  traverse the tunnel at regular intervals, producing fixed-size ciphertext frames.
  To a passive network observer, a card departure signal is indistinguishable from
  a routine keepalive packet.

### 3.3 Authenticated Encrypted Departure Signal
When [`TKSmartCardSlotManager`](https://developer.apple.com/documentation/cryptotokenkit/tksmartcardslotmanager)
signals that the card has been extracted from the reader slot:
1. **Immediate Proxy Event**:
   [`CardPresence.swift`](../Sources/App/CardPresence.swift) updates `isReaderCardPresent = false`.
2. **Encrypted Close Notification**:
   The phone proxy dispatcher immediately emits a `session.close` message
   ([`MessageType.sessionClose`](../CardCore/Sources/RappEngine/Wire/MessageType.swift))
   with the registered close reason [`CloseReasonName.cardUnavailable`](../CardCore/Sources/RappEngine/Engine/CloseReasonName.swift):
   ```cbor
   {
     "type": "session.close",
     "reason": "card_unavailable"
   }
   ```
3. **No Pairing Revocation**:
   Per formal RAPP specification (`INV-18` in `SessionCloseBehaviorTests`), `card_unavailable`
   closes the active operational session but strictly preserves the long-term mutual pairing.
4. **Zero Cache Leakage**:
   The iPhone immediately purges the PIN 1 cache ([`ReaderPin1Cache.shared.clear()`](../Sources/App/ReaderPin1Cache.swift))
   and drops local ephemeral reader token state.

### 3.4 Immediate Sub-50ms CryptoTokenKit Withdrawal on macOS
1. **Decryption and Verification**:
   The Mac's [`RappConnectionCoordinator`](../CardCore/Sources/CardCore/RappConnectionCoordinator.swift)
   receives and decrypts the authenticated `session.close` envelope.
2. **Event Delivery**:
   The coordinator emits:
   ```swift
   .closed(reason: .operation(.cardUnavailable))
   ```
3. **Instant Token Unpublishing**:
   [`PersistentTokenRegistry`](../Sources/App/PersistentTokenRegistry.swift) handles the event:
   - Differentiates between *unauthenticated Wi-Fi packet loss* (which retains the 30s debounce)
     and an *authenticated in-band hardware departure signal* (which triggers instant 0s withdrawal).
   - Calls `PersistentTokenRegistry.withdrawPublishedIdentity()` synchronously.
   - Notifies CryptoTokenKit via `TKTokenWatcher`, dropping the smart card certificate
     from Safari and macOS TLS client identity selectors within tens of milliseconds.

---

## 4. Protocol Specification & State Machine

### 4.1 Message Encodings
All control frames follow deterministic canonical CBOR encoding within Noise transport envelopes:

| Envelope Field | Value | Description |
| :--- | :--- | :--- |
| `type` | `"session.close"` | Model discriminant |
| `reason` | `"card_unavailable"` | Physical smart card is no longer accessible |
| `operationID` | `<16-byte UUID>` | ID of the in-flight or last completed operation |

### 4.2 State Invariants
- **INV-CARD-DEPART-1**: Physical card disconnection must never result in unencrypted
  network broadcasts or modified plaintext mDNS records.
- **INV-CARD-DEPART-2**: An authenticated `card_unavailable` event must withdraw all
  borrowed identities from CryptoTokenKit immediately without entering loss-hold timers.
- **INV-CARD-DEPART-3**: `card_unavailable` must not invalidate or delete the long-term
  pairing record in `RappDeviceVault`. When the card is re-inserted, the existing pairing
  is immediately reused without user intervention.

---

## 5. Implementation Roadmap

### Phase 1: In-Band Departure Dispatch (iOS)
- In [`PhonePersistentTokenRelay`](../Sources/App/PhonePersistentTokenRelay.swift), maintain
  the active coordinator session while the reader card is present.
- When `CardPresence.shared.isReaderCardPresent` drops to `false`:
  - If a coordinator session is open, dispatch `coordinator.close(reason: .cardUnavailable)`.
  - Flush frame delivery queue and disconnect the underlying socket.

### Phase 2: Instant Withdrawal Handling (macOS)
- In [`PersistentTokenRegistry`](../Sources/App/PersistentTokenRegistry.swift), observe
  the active RAPP coordinator's termination events.
- On receipt of `.closed(reason: .operation(.cardUnavailable))` or `.terminal(..., .cardRemovedBeforeTransmit)`:
  - Cancel any pending `advertisementLossTask`.
  - Invoke `Self.withdrawPublishedIdentity()` immediately.
  - Reset `holderLine` and update UI status to reflect card absence.

### Phase 3: Verification & Test Suite
- **Engine Unit Tests**: Extend `CardCore/Tests/RappEngineTests/SessionCloseBehaviorTests.swift`
  to verify that `card_unavailable` payload serializes deterministically and maps correctly
  to `RappTerminalReason`.
- **End-to-End Loopback Tests**: In `Tests/CardCoreTests/RappIntegrationTests.swift`, add a test
  case simulating reader extraction during an idle borrow period, asserting that token
  withdrawal is executed within < 50 ms.
- **Privacy Audit**: Wi-Fi packet capture verification verifying that zero plaintext
  mDNS or broadcast packets are emitted when the smart card is removed.
