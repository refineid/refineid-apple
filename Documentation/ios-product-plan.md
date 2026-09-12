# iOS product plan: RefineID for iPhone (lead product)

Status: accepted direction, 2026-07-23

## 1. What the product is

An iOS app that makes a Finnish identity card usable.

1. Use the iPhone's built-in NFC antenna, or attach a USB-C smart-card
   reader and insert the card.
2. See card, reader, and PIN1/PIN2/PUK retry status, side-effect-free.
3. Log into Finnish services **in Safari** with the card's
   authentication certificate through the system client-cert flow.

Both card transports are production v1 features. Built-in NFC ships in
TestFlight and App Store builds; it is not a development-only or future
feature.

## 2. Minimal pure-Swift Safari driver

The is pure Swift and absolutely minimal - the smallest CTK
smart-card driver that makes Safari login work.

What the driver contains (the whole protocol surface of v1):

- card recognition and named application/file selection (SELECT AID);
- bounded certificate and chain reads with response continuation;
- a side-effect-free PIN1 retry-state read before reader authentication;
- the reader PIN1 retry floor (three or more attempts proceeds, one or two
  refuses before any prompt, unreadable state fails closed);
- PIN1 `VERIFY` with at-most-once transport and rejected-PIN memory;
- `MSE:SET` + `PSO:CDS` signing and ECDSA/RSA result normalization;
- token publication through the CTK extension.

No PACE, no secure messaging, no TLS, no X.509 parsing - the contact
path does not need the first two, and the platform provides the rest.
Minimality is the security argument: the driver stays reviewable.

The Rust core remains the reference oracle.

## 4. Features and conventions

- Calendar versioning `YY.M.D` with ten-minute-bucket build numbers;
  tagged releases.
- Safety invariants: the PIN1 retry floor (proceed only at three or more
  attempts), token-bound memory only for a PIN1 the card accepted, at-most-once
  credential transport, and wrong-PIN rejection memory. Normal minting and
  authentication never probe PIN2 or PUK. The
  system-driven NFC field also omits the PIN1 preflight because its measured
  deadline cannot carry that extra APDU; it uses the explicitly stored PIN1
  and revokes the identity on a confirmed rejection.

## 6. Production NFC

NFC-for-Safari is proven on iPhone and is required in production. iOS 26
provides `createNFCSlot`, `TKSmartCardTokenRegistrationManager`, and
system-summoned NFC on demand. The measured implementation primes and
registers the card in one CryptoTokenKit field. Later client-certificate
requests summon a fresh field; the extension retains that card session,
establishes PACE, checks PIN1, and signs.

TestFlight and App Store configurations must retain the complete NFC
priming, registration, discovery, and signing path. An unsolicited system
NFC sheet is a defect in when that path is requested, not a reason to remove
or configuration-gate NFC. Fix the trigger while preserving deliberate NFC
setup and authentication end to end.

`Documentation/card-transports.md` records the architecture and measured
constraints. The 2026-07-28 entry in `Documentation/decisions.md` records
the end-to-end device result and the decision to stop deferring NFC.
