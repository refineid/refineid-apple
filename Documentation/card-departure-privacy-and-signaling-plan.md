# Private Card Departure Signaling and Real-Time Token Withdrawal

## 1. Summary

When the card a phone holds leaves, the Mac must stop offering the
borrowed CryptoTokenKit (CTK) identity within a bounded time, without
anyone on the local network learning that a card was inserted or removed,
and without withdrawing an identity a browser is about to use whenever a
session drops for a moment.

RAPP v26.10.22 §8.4 settles this with an in-band message and an eventually
consistent offer: the custodian sends `card.status` right after
`session.ready` on every session and again whenever the card it holds
changes, and a requester offers the identity of a card a session
confirmed by fingerprint, also between sessions, until 120 seconds pass
with no report of that card present. This document records the design as
it is built on Apple platforms.

---

## 2. Problem

### 2.1 What the earlier design did

Under the transaction-oriented design the Mac dialled the phone to read
the certificate or compute a signature and closed the socket afterwards.
Between operations nothing was held open, so the only sign of the phone
was its Bonjour record, and the only sign of its card was that record's
presence or absence:

1. Bonjour browse results drop a live name for a moment without the
   holder having left, so the Mac waited thirty seconds before
   withdrawing an identity whose advertisement vanished.
2. A phone with a primed near-field card advertised whether or not a
   reader was attached, so the Mac never received an absence signal from
   a phone whose reader card had been pulled.
3. A browser that retried against a card that could not answer put the
   phone through back-to-back card waits; the token extension carried a
   request back-off to dampen that.

### 2.2 Privacy requirement

On a shared network any station can read mDNS queries, responses and
TXT records. Publishing a card attribute (`card=0`, `card=1`), or
toggling the advertisement with the card, hands a passive observer the
holder's card use and its timing.

Card presence and departure stay confidential between the paired
devices. A network observer sees uniform encrypted frames and nothing
else.

---

## 3. Architecture

```
+------------------------------------------------------------+
|                          iPhone                            |
|  Reader card removed, or near-field prime cleared          |
|          |                                                 |
|          v                                                 |
|  HolderCardServing -> PhonePersistentTokenRelay            |
|          |                                                 |
|          v                                                 |
|  Encrypted RAPP frame: card.status, absent, zero digest    |
+---------------------------+--------------------------------+
                            | Noise session (ChaCha20-Poly1305)
                            v
+------------------------------------------------------------+
|                           macOS                            |
|  RappHeldRequesterSession decrypts the frame               |
|          |                                                 |
|          v                                                 |
|  RappConnectionCoordinator: .cardStatus(.absent)           |
|          |                                                 |
|          v                                                 |
|  PersistentTokenRegistry withdraws the CTK identity        |
+------------------------------------------------------------+
```

### 3.1 Random session identity

- The phone listens under a fresh random name, `refineid-` and eight hex
  characters, drawn whenever listening starts. Nothing derived from a
  rendezvous token is published (discovery hierarchy §4.1 to §4.3).
- The TXT record carries `v=1`, `mode=session` and rotating discovery
  hints for the pairings the phone serves (discovery hierarchy §4.3). A
  hint links the record to a pairing only within its window and only for
  the peer that holds the key.
- No device name, user name, cardholder identifier, SATU or card
  attribute is published. The record says the phone is on the network;
  whether a card can answer is said only inside the session.

### 3.2 Standing session

- While the phone's record is on the network, the Mac app holds one
  requester session with it
  ([`RappHeldRequesterSession`](../CardCore/Sources/CardCore/RappHeldRequesterSession.swift)).
  The session carries the phone's `card.status`, the certificate read an
  offered identity needs, and the liveness probes of RAPP §8.3: a ping
  after 5 seconds of silence, the session over after 30.
- Liveness probes and status reports are frames of the same shape; a
  card departure is indistinguishable from a keepalive to an observer.
- The token extension dials its own session for a signature, and a
  request that finds no session open waits for one within the request's
  own deadline. The phone yields an idle standing session to that dial
  ([`StreamRelayListener`](../CardCore/Sources/CardCore/StreamRelayListener.swift)
  `yieldsIdleConnection`), and the Mac dials again once the extension is
  done; the identity stays offered meanwhile.

### 3.3 The status message

`card.status` is an authenticated in-session message (RAPP v26.10.22
§7.1):

```
{ "type": "card.status",
  "body": { "card_present": <bool>, "certificate_fingerprint": <32 bytes> } }
```

The fingerprint is the SHA-256 digest of the DER of the card's
authentication certificate while a card is present, and 32 zero bytes
while none is, so the message has one size whatever it says.

The phone sends it when the session is established and whenever the card
it holds changes
([`PhonePersistentTokenRelay.reportCardStatus`](../Sources/App/PhonePersistentTokenRelay+CardStatus.swift)).
A card is present from the moment a reader holds it until it is removed,
and an NFC card from the moment the holder adds it to the phone until the
holder removes it there (§8.4 item 1). An operation the card did not
answer ends with `card_error` and changes nothing: the next operation
asks the holder to present the card again.

### 3.4 Withdrawal on macOS

[`PersistentTokenRegistry`](../Sources/App/PersistentTokenRegistry.swift)
offers the identity of a card a session confirmed by fingerprint and keeps
offering it between sessions (§8.4 item 3). It withdraws the identity when,
for 120 seconds (the engine's identity-offer grace), no session has been
open or the phone has reported absence, with no `card.status` reporting the
card present in that time
([`RemoteIdentityOffer`](../Sources/App/RemoteIdentityOffer.swift)). It
withdraws at once when the pairing is forgotten or revoked, when the phone
announces withdrawal (§4.5), and when a session names a different card,
which it then reads afresh before offering anything; a report of absence
is never a different card. Losing the phone's record only stops dialing.
A reader card in the Mac outranks all of it.

A phone that forgot the pairing (§4.6) ends the open session with
`pairing_revoked`, or answers the next session with that close in place
of `session.ready`; either way the Mac forgets the pairing, withdraws the
identity and names the phone in the identity row.

---

## 4. Invariants

- **INV-CARD-DEPART-1**: a card leaving or arriving changes no plaintext
  record and no advertisement.
- **INV-CARD-DEPART-2**: an authenticated `card.status` of absent starts
  the 120-second grace; a different card present withdraws the borrowed
  identity at once.
- **INV-CARD-DEPART-3**: card absence changes nothing in
  `RappDeviceVault`; the pairing and the session stay, and the next
  `card.status` of present offers the identity again without a
  ceremony.
- **INV-CARD-DEPART-4**: no identity is offered that a session has not
  confirmed by fingerprint, and none outlives 120 seconds without a report
  of its card present.

---

## 5. Verification

- The engine's `card.status` body is replayed byte for byte against
  `rapp-operation-v26.10.22.json` (`OperationBodyTests`).
- The `pairing_revoked` close of a forgotten pairing, in session and on
  the next session in both directions, is driven end to end
  (`RevocationDriveTests`).
- The state tables are checked against
  `rapp-state-machine-v26.10.22.yaml` in both directions
  (`StateConformanceTests`).
- `RemoteIdentityOfferTests` pins the offer's lapse at the grace, and that
  absence starts it while a different card withdraws at once.
- `NetworkContractTests.advertisementsCarryNoDeviceIdentity` pins what
  the phone publishes.
