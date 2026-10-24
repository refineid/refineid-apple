# Card transports: contact reader, iPhone NFC, and RAPP remote proxy

RefineID reaches a Finnish identity card over three operational transports.
They terminate in the same place -- a CryptoTokenKit token extension that
publishes the card's certificate and key to the keychain, so Safari,
`URLSession`, and any other system consumer use the card as an ordinary
client-certificate identity.

| Transport | Platforms | Card interface | Access control |
|---|---|---|---|
| Contact / PC-SC reader | macOS, iPadOS, iOS (USB-C) | contact | PIN1 |
| Phone antenna (NFC) | iOS 26+, iPadOS 26+ | contactless | CAN, then PIN1 |
| Remote proxy (RAPP) | macOS (requester) via iOS 26+ (proxy) | contact or contactless on phone | PIN1 prompted natively on phone |

Both local transports are production features on iPhone. Its TestFlight and App
Store builds must include the built-in NFC path. NFC is not a diagnostic
facility or future roadmap item, and a bug in automatic activation must be
fixed without disabling that path. Remote proxy (RAPP) enables a Mac to use
a card held by an iPhone without physical card reader hardware on the Mac.

macOS has no NFC smart-card slot at all: `TKSmartCardSlotManager`'s NFC
surface is `API_UNAVAILABLE(macos)`. Every NFC path in this repository is
therefore behind `#if canImport(CoreNFC)` plus an iOS 26 availability
check. The app and extension derive the usable transport from what the
platform actually presents; there is no separate preference to become
stale.

## Why the contactless interface needs a CAN

A FINEID card seals its PKCS#15 application on the contactless
interface: every read is refused with `SW=6982` ("security status not
satisfied") until **PACE** has run. PACE is a password-authenticated key
agreement -- here over brainpoolP384r1, keyed by the six-digit **CAN**
printed on the card -- that both proves proximity and establishes a
secure-messaging channel for all later APDUs.

So the contactless flow has one extra step and one extra secret compared
to contact:

    contact:      SELECT -> read -> VERIFY PIN1 -> PSO:CDS
    contactless:  PACE(CAN) -> SELECT -> read -> VERIFY PIN1 -> PSO:CDS

The CAN is not a PIN: it authorizes *reading* the card in a field, not
signing. PIN1 still gates every signature.

## The travel-document application, and what it holds

The card is also an ICAO 9303 travel document. Its eMRTD application
(AID `A0000002471001`) answers a SELECT on **either** interface --
measured over a contact reader on 2026-08-04, not only contactless --
but every file inside it is refused with `SW=6982` until PACE has run,
exactly like the PKCS#15 application contactless. The same CAN and the
same brainpoolP384r1 PACE open both.

`EF.COM` on a 2026 card lists five data groups:

| Data group | Tag | Content |
|---|---|---|
| DG1 | `61` | machine-readable zone |
| DG2 | `75` | facial image |
| DG3 | `63` | fingerprints, sealed behind extended access control |
| DG7 | `67` | **the holder's handwritten signature** |
| DG14 | `6E` | chip authentication public keys |

DG7 carries one instance -- the count is explicit in the template and
the declared length leaves room for no other -- as a baseline JPEG,
528 x 88 pixels, about 3.7 kB. That is the image the holder signed at
the registration desk, and reading it needs nothing the app does not
already do for a login: PACE with the CAN, then a plain READ BINARY
behind the secure channel. No PIN is presented, so no retry counter is
touched.

## The NFC architecture on iOS 26

iOS 26 added `TKSmartCardSlotManager.createNFCSlot(message:)` and
`TKSmartCardTokenRegistrationManager`. The shape that works, proven on
device (see `Documentation/ios-native-nfc-safari.md`):

1. **Prime, once per card, in one field.** The app opens an NFC slot,
   runs PACE with the CAN, reads the authentication certificate (`EF.4331`)
   and card serial, checks activation state with memoized retry probes, stores
   them plus the CAN in a keychain item shared with the extension as soon as
   they are read, so the extension's mint overlaps the rest of the hold, and
   registers the token -- all inside the same hold. The qualified signature
   certificate (`EF.4332`) is not read at setup: the first signature that
   needs it reads it in its own card session and caches it in the prime of
   the card whose CAN opened that session. Issuing and root CA certificates
   come from the persisted CA cache; the card's issuing CA is read only when
   no cached one matches the leaf's issuer, and its root only when no cached
   root issued that CA. A card root is admitted only when it is self-signed,
   a CA within its validity and the verified issuer of the issuing CA. A
   cached CA is retired only by its own expiry. The card is identified by a
   hash of its ATR. Two bridges make the
   single field work: a registration mark, written before the slot opens, tells
   the extension to publish without taking the card session; and the extension's
   mint waits briefly for the prime (`TokenDriver.awaitPrime`), because `ctkd`
   asks for the token the moment the card arrives, while PACE is still running.
   An already-primed card skips the card I/O and the whole hold is the
   registration.
2. **Login.** The app opens an NFC slot; ctkd asks the driver for a
   token; the driver materializes it from the stored prime (no card I/O
   is possible before PACE, so it must not try). The app waits for
   publication with `TKTokenWatcher`, then materializes a `SecIdentity`
   from the `com.apple.token` keychain group, passing PIN1 in an
   `LAContext` so no separate prompt is needed.
3. **Handshake.** The identity answers the client-certificate challenge.
   The extension runs PACE, verifies PIN1, and performs the on-card
   signature -- reaching the card through the slot the app is holding.

### Four rules that the implementation must not violate

Each of these was learned from a measured failure, and each looks like a
platform limitation when broken.

1. **Always open a card session (`beginSession`) before card I/O, on the
   NFC slot too.** A sessionless `TKSmartCard.transmit` on the built-in
   NFC slot is parked by ctkd indefinitely: no error, no timeout. With a
   session, the same card answers in about 20 ms.
2. **Never release the NFC slot session while a signature is in
   flight.** CryptoTokenKit deletes a token's keychain items when the
   token goes away, and the slot session's lifetime is the slot's
   lifetime. Releasing it mid-handshake destroys the key the handshake
   needs; TLS fails with `errSSLClosedAbort` (-9858).
3. **Keep diagnostics off the handshake path.** A single bounded probe
   APDU at the head of the sign path is enough to miss the TLS deadline.
4. **Register a token only while its card is live in the slot.**
   `TKSmartCardTokenRegistrationManager.registerSmartCard` accepts a
   driver-created live-slot token; a persistent token injected through a
   driver configuration is rejected.

A cross-process token use also raises a one-time system "Token Access
Request" dialog. Until the user grants it, identity queries block for
roughly 25 seconds and then return `errSecItemNotFound`.

## The Remote Authorization Proxy Protocol (RAPP) transport

RAPP bridges macOS (and iPad requesters) to an iPhone authorizer over an
end-to-end encrypted Noise channel (`Noise_KK` for sessions). This allows
Mac Safari and system TLS clients to authenticate using a citizen card
held on the phone without requiring a smart card slot or USB reader on the Mac.

1. **Card interface on the proxy.** The iPhone proxy can reach the card
   through its built-in NFC antenna or through an attached physical CCID reader
   (Lightning or USB-C). When a physical reader is connected, it takes immediate
   priority over contactless NFC presence.
2. **Strict credential boundary.** PIN 1 and PIN 2 never leave the iPhone.
   When the Mac initiates web authentication, the iPhone raises an interactive
   native PIN 1 sheet. The PIN is presented directly to the attached card or
   contactless chip on the phone. Only the resulting cryptographic signature is
   returned across the encrypted RAPP channel.
3. **Reader PIN 1 volatility.** Unlike NFC where PIN 1 may be stored in the
   local keychain if explicitly configured by the holder, a physical reader card's
   PIN 1 exists only in volatile memory during the physical insertion. The moment
   the card is disconnected or the reader unplugged, cached PIN 1 state is
   immediately zeroized.
4. **Opt-in serving on iPhone.** Remote serving is off by default: a fresh
   install never advertises, browses, or asks for notification permission
   until the holder turns Remote Access on or enters a pairing code shown
   on the requesting computer. Pairings stay stored while serving is off,
   so turning it back on reconnects without a new code.
5. **Permissions asked only when undecided.** Turning Remote Access on
   shows no alert of the app's own. The system prompts are the only
   questions, and only while a permission is undecided. Local network
   access is probed until it has been seen once; only a real denial turns
   the switch back off with a Settings redirect. Declined notifications
   show as a row with Settings on the Remote Access screen.
6. **Card requests are Time Sensitive.** A paired computer that needs the
   card needs it now, so the request notification uses the Time Sensitive
   interruption level and can break through a Focus and notification
   summaries. The holder can still turn Time Sensitive off for any Focus.
   The notification is removed when the request ends, and requests left
   from an earlier run are cleared when the app becomes active.
7. **The holder name travels as the card states it.** Whenever the
   iPhone sends the card holder's name to a computer, it sends the
   certificate's name exactly as the card carries it, in the card's case
   and order, with the trailing personal identifier removed, for example
   `MEIKÄLÄINEN MATTI`. Nothing recases or reorders it on the wire; a
   display that wants another casing applies it locally.
8. **Encrypted in-band card departure.** When a card is disconnected during an
   active proxy session, the proxy immediately transmits an encrypted in-band
   `session.close(card_unavailable)` message. This unblocks the Mac browser
   prompt instantly without exposing card presence transitions to passive network
   eavesdroppers.

## What is still open

System **Safari** with the card absent is not solved: a registered
token's certificate attributes are visible cold, but the `SecIdentity`
reference is not, because the reference requires a usable private key and
the key requires a live card. Safari enumerates non-interactively, gets
nothing, and never offers the certificate. In-app flows are unaffected --
they hold the card in the field for the whole handshake.

## Automatic transport selection

The physical environment is the preference. A connected reader is used
when the platform offers its slot; otherwise iOS can open the built-in
NFC slot. The app does not expose switches for transports that are either
present or absent independently of those switches.

The token extension makes the same decision from the slot that caused
CryptoTokenKit to invoke it. macOS offers only contact slots; iOS can
offer contact or built-in NFC.

On iOS, a successful connected-reader mint removes every stored RefineID
NFC prime and persistent RefineID smart-card registration. Connecting a
reader and inserting a usable card is the holder's global transport
choice within RefineID, even when the reader card and a previously primed
NFC card have different serials or key profiles. Apple and third-party
identities are untouched. The live reader token is then the sole RefineID
transport until the holder deliberately mints an NFC identity again.

When several readers contain supported cards, CryptoTokenKit still mints
and keeps one live token for every card. Every live token publishes its
authentication certificate and key. Safari's native client-certificate
sheet selects the identity; RefineID does not rank the cards or add a
second picker.

Safari renders the signed X.509 subject in that sheet, not the CTK item's
`kSecAttrLabel`. Cards issued to the same subject can therefore appear as
duplicate rows. This is intentional: altering the signed certificate
would make it unusable, while cards issued to different people already
carry distinguishable subjects.

## The reader token lifecycle, and why the screen trusts the slot

CryptoTokenKit asks the token extension to mint a reader card's token
once per physical insertion -- the slot transitions empty to valid, and
`ctkd` invokes `createToken`. It does not invoke it again for a card that
was already in the reader when the extension loads, which is what happens
when the app is reinstalled or updated over a card left in the slot. The
slot then reports a valid card the whole time, yet no RefineID token is
ever published for it, and no session activity from the app re-triggers
the mint. On the next real insertion the card mints normally again.
A restart of the user's own `ctkd`, the token watcher launchd starts on
demand, reads the slots afresh and mints such a card without a
re-insertion (observed, not documented by Apple); the release manager's
Mac install does that when a card is in the reader.

Two rules follow from this, and from the card interfaces above.

- **The slot is the source of truth that a card is present; a published
  token is not.** The reader identity screen shows a card when the slot
  reports one, token or no token. When a token exists it names the holder
  from what the token published. When none does -- the reload case above
  -- the holder name is read straight off the card: a contact reader
  reaches it with no PACE and no CAN, so the read costs a SELECT and one
  certificate read. The read waits out the system's own minting window
  first and takes the token if it arrives, so it never contends with a
  mint in progress. Treating "no token" as "no card" is the same mistake
  as treating a card that could not be read as a card that is absent; the
  screen must distinguish present-but-unreadable-yet from absent.

- **RAPP is a consumer of the reader card, never a competitor for it.**
  The remote-serving holder may open the card to prepare it for a waiting
  requester, but only after the card's token has published. Opening the
  card while `ctkd` is still minting takes the card from under the mint,
  the mint's first command goes unanswered, and -- because the mint is
  one-shot -- the card is left with no token until it is physically
  reinserted. Whether a computer is connected, over BLE or the stream
  transport, therefore has no bearing on whether the phone sees its own
  reader card. A reader with a card always takes priority over a RAPP
  connection; it never wipes one, because serving that reader card to the
  computer is a valid case in itself.

An exchange that ends with neither a reply nor an error -- the card's
session no longer reaching it -- is named `exchangeUnanswered`, distinct
from a malformed reply, and the extension retries it once like any lost
link rather than failing the whole insertion on a transient drop.
