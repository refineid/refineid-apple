# Status, 26.9.5

What works, what does not, and what each was measured with. Written from
device and Mac runs through 2026-09-05, not from intent. Code and document
status below is current through 2026-09-05.

## ANSSI: the dossier is ready to sign

`Documentation/anssi-declaration.md` is content-complete: no
placeholders, sections numbered to ANSSI's annexe I field by field,
declared as a private individual, French proofread (aspell plus a close
reading; the legal basis was corrected to LCEN article 30 on the way).
An earlier artifact was signed with the card at PAdES-BASELINE-LTA and
confirmed by two independent validators on 2026-08-03:

    dvv.fineid.fi:  QES | PAdES-BASELINE-LTA | TOTAL_PASSED | QESIG
    EU DSS demo:    PAdES-BASELINE-LTA | TOTAL_PASSED | QESig

The current French-only, three-page artifact supersedes that file and
is unsigned. It must be signed and validated again before filing.

The signing toolchain is `refineid card sign-document` in the internal
monorepo: pades, cades, cades-detached, asice-cades, asice/bdoc, levels
B/T/LT for all and LTA for pades and asice-cades, each level verified
against DVV on a real card. ANSSI's own annexe I form (an XFA PDF) was
also signed and validated the same way, so nothing in the filing needs
ink.

What remains is human: have the French read by a native speaker, then
render, sign and email the declaration to `controle@ssi.gouv.fr`.
ANSSI's annexe I is a template rather than the document -- filling one
is how you obtain the other -- and this declaration carries the same
content under the same headings in the same order, so nothing needs to
be typed into Adobe Reader. Steps and pitfalls -- including which annexe is
the right one and why the other looks right but is not -- are in
`export-compliance.md`.

## macOS: card login works, on both interfaces

Safari signs in with the card through a reader, driven entirely by this
app and its token extension -- with the card in the contact slot, and
with the card resting on a reader's contactless antenna. The second was
proven on 2026-07-27 against an ACR1581U, whose PICC interface the card
answers over T=CL:

    slots (3):
      ACS ACR1581 1S Dual Reader(1)
          state=valid card
          atr=3B 8F 80 01 80 31 B8 65 B0 85 05 10 24 12 24 60 82 90 00 22
    createSession: session requested, interface=contactless
    sign: exit ok out=103B ms=1012.7

A contactless signature costs about a second, nearly all of it the PACE
handshake that opens the secure channel; a contact one costs about a
third of that and needs no handshake at all. Measured across `admin.iki.fi` and
`card.refineid.fi`, several signatures each:

    supports: op=2 algo=msgX962SHA256 profile=ecdsaP384 -> YES
    sign: entry input=11782B
    sign: PIN1 verified; MSE:SET + PSO:HASH + PSO:CDS
    sign: local verify OK, 102 DER bytes
    sign: exit ok out=102B ms=343.8

Each signature is verified locally against the card's own public key
before it is handed back, so a wrong answer is caught here rather than by
the far end. PIN1 is asked for once and reused from the in-memory cache
for the following signatures (`reusing cached PIN1 - no prompt`), which
is what makes several sites in a row bearable.

Re-proven on 2026-07-28 against the current build, card on the reader's
antenna, whole exchange in 787 ms:

    supports: op=2 algo=msgX962SHA256 profile=ecdsaP384 -> YES
    sign: entry input=11782B algo=msgX962SHA256
    sign: PACE ok ms=396.2
    sign: PIN1 verified; MSE:SET + PSO:HASH + PSO:CDS
    sign: local verify OK, 102 DER bytes
    sign: exit ok out=102B ms=787.5

The refused attempt five seconds before it is the flow working, not
failing: a first `sign` with no PIN in hand returns
`authenticationRequired`, the system raises its PIN sheet, and the
repeat succeeds.

Setup on macOS is a card access number per card, entered once in the
Card menu; a card in the contact slot needs none at all.

Re-proven on 2026-08-22 against the production Release build 26.8.21
installed in /Applications - the store shape, remote card gated off.
Four sites verified by the owner with a contact reader: `suomi.fi`,
`oma.posti.fi` and `admin.iki.fi` over TLS 1.2, and `card.refineid.fi`
over TLS 1.3 after a Safari restart (its first failure was the retained
dead client-identity path, Documentation/troubleshooting.md). The TLS
1.3 signing path was also driven directly through `ctkd` against the
same build: a 130-byte CertificateVerify-shaped message signed with
`ecdsaSignatureMessageX962SHA384` in 315 ms, 103 DER bytes, verified
locally against the card's certificate. A Release extension logs
nothing, so the direct probe and the `ctkd` connection log are the
observation channels that remain.

Re-proven on 2026-09-03 with remote contactless card over Android phone reader:
macOS Safari client certificate authentication to `https://card.refineid.fi`
over TLS 1.3 was completed end-to-end using an Android phone (Samsung Galaxy S22)
acting as the contactless NFC reader. Safari presented the borrowed leaf
certificate `Perus (PIN 1) (KOISTINEN PETRI 14037871J)`, requested ECDSA P-384
signing through `RefineIDRappTokenExtension`, which relayed the request over
the encrypted Noise stream to the phone. The phone verified PIN 1 on the card
via NFC and returned the 96-byte signature, completing login.

Re-proven on 2026-09-05 with remote card in physical reader on iPhone:
macOS Safari client certificate authentication to `https://card.refineid.fi`
over TLS 1.3 was completed end-to-end using an iPhone with an attached physical
smart card reader acting as the RAPP authorization proxy. When Safari evaluated
client identities, only PIN 1 authentication identities were offered (PIN 2
identities are excluded from browser evaluations to prevent signing PIN prompts
during web login). Upon selecting the identity, the signature request was
relayed over the encrypted Noise session to the iPhone. The iPhone arbitrated
with priority given to the inserted physical card over wireless NFC presence,
raised a native interactive PIN 1 sheet on iOS, verified PIN 1 directly on the
attached card reader, and returned the cryptographic signature to macOS Safari,
successfully completing client TLS authentication. PIN 1 never left the iPhone,
and all reader PIN 1 cache was zeroized upon card removal.

Re-proven on 2026-09-05 with silent iPhone HSM mode (resting card under iPhone):
macOS client certificate authentication to `https://card.refineid.fi` completed
in 4.39s with the Finnish ID card resting continuously under the iPhone. The
iPhone acts as an ultra-fast Hardware Security Module (HSM): when the card is
already in place under the device, card detection completes in under 500 ms
(`wasPrompted = false`), executing the cryptographic signature with zero prompts,
zero alert sounds, zero vibrations, and zero UI sheet delays ("quiet as unix command
line on success"). Active guidance (audio `Handoff-EncoreInfinitum`, haptics, and
positioning sheet) activates only when the card is missing or displaced. On macOS,
`PersistentTokenRegistry.start()` retains published identities across app launches
when paired devices exist, and `PublishedIdentityName` avoids unentitled wildcard
token queries, eliminating main-thread stalls.

## Every card carries its own access number

A contactless card is sealed until PACE, and PACE is keyed by the six
digits printed on that particular card -- so one stored number served
one card, and a desk with two cards pushed the wrong number at one of
them on every insertion. The Card menu now keeps a directory: each
known card with its serial, model and number, added by proving the
typed number against the card that is present, deleted per row.

A sealed card is anonymous before PACE by design, so the driver cannot
ask which card it is holding. It filters instead: the answer to reset
names the card's model, and only the entries matching that model are
tried, newest first. Between two different card models that filter is
complete -- a generation `04` Gemalto and a generation `05` Thales can
never be offered each other's number -- and within one model it costs
at worst one refused handshake per stored number.

A refusal then latches for thirty seconds against the identical retry.
Without it a wrong number is a storm rather than an error: a failed
PACE tears the field, the card re-arrives, the system offers it again,
and the reader blinks and serves nobody until the card is lifted.
Editing the directory clears the latch, so correcting a number is
tried immediately.

## What a timeout on macOS is allowed to be

The per-APDU budget was two seconds, and it was right for the phone and
wrong everywhere else: it is derived from `ctkd` ending the system NFC
field about two seconds after the mint, and macOS has no such field --
there is no NFC smart-card slot there at all. On a reader that number
was a guillotine, cutting live PACE handshakes with `responseTimedOut`,
which tore the field and fed the retry storm above.

The card declares its own timing and the layer below already enforces
it: FWI in the ATS gives the frame waiting time on the contactless
interface, extensible by the card asking for more with S(WTX), and BWT
plays that role for T=1 on contact. A card that overruns is reported to
us as an error rather than as silence. So a per-APDU timer of ours is
either shorter than what the card may legally take -- and kills correct
work -- or longer, and never fires.

What genuinely needs a bound here is different: waiting for another
process to release the card, which no protocol timer covers, and the
whole signing operation, because the deadline that decides a macOS
login is the consumer's patience rather than the card's speed. Neither
is yet derived from a measured number; the current values are
inherited.

## How the driver knows which interface it is on

It asks the card rather than reading the slot's name. A dual-interface
reader publishes its contact, contactless and SAM interfaces under one
name differing only by a trailing index, and nothing in the name says
which index is the antenna -- while the card answers the question
itself: SELECT of the PKCS#15 application returns `6982` on the
contactless interface until PACE has run, and succeeds on the contact
one. One command, and no guessing.

Taking "the first slot" instead was a bug in three places at once: the
status screen described the empty SAM socket beside the card, and a
probe reported "no reader or card" about a card that was signing for
Safari at the time. `CardSlotSearch` is now the one implementation.

## Handing the card access number to the driver on macOS

The two processes cannot share a keychain item there. An item carries an
access list naming the application that created it, and a token
extension is a different application: it finds the item and is refused
the value with `errSecInteractionNotAllowed` (-25308), which it cannot
resolve, because a driver hosted by `ctkd` has no interface to authorize
with. A shared keychain access group is the right answer and is what iOS
uses, but it is a restricted entitlement and the local signing profile
will not carry it.

CryptoTokenKit's own token configuration is the channel instead, which
its header documents for exactly this: data that the token
implementation and its hosting application both use, that the system
does not interpret, with access credentials as the stated example. Only
the hosting application can write it and every other caller is handed an
empty store, so the driver's own app bundle is the boundary.

It costs one oddity worth knowing: every token configuration is listed
as a token, so this entry appears in `TKTokenWatcher` beside real cards.
It holds no keychain items and so offers Safari nothing, but anything
asking "is a card available?" must exclude it by name or it answers yes
with no card present.

## The discovery extension is iOS-only

It declares the travel-document application identifier so the phone's
NFC polling has something selectable before PACE. On macOS a reader
hands the card over without one, and the extension there could only
claim a card in order to refuse it, so it is no longer embedded in the
Mac app.

## iOS: setup and system-Safari signing work

Priming works end to end on the phone, over the phone's own NFC antenna,
in pure Swift:

    Card found -> Opening a secure channel -> Reading the certificate
    -> Card read -> Card details stored -> Card registered for Safari
    stored: true   registered: true

That exercises the ported PACE stack, secure messaging and the
certificate read against a real card. End-to-end system-Safari login has
now been proven with `suomi.fi`, `oma.posti.fi`,
`dvv.fineid.fi/en/authentication`, `card.refineid.fi` and
`admin.iki.fi`.

The first visit to a site can still need a repeat when iOS asks the holder
to accept the client certificate. In a measured `admin.iki.fi` attempt,
PACE was ready in 840 ms, but Apple ended that field 1.266 s later while
the certificate-consent UI was still open. Safari asked for the signature
3.141 s after the field ended. The extension correctly returned
`tokenNotFound` in 3.2 ms because that token instance no longer had a
card. The next attempt minted a fresh token and completed PACE, PIN1
verification and ECDSA signing in 1.107 s.

That first failure is not a bad certificate or signature. Certificate
selection belongs to iOS, cannot be accepted by the token extension, and
can outlive the field that caused iOS to discover the identity. Once the
choice is remembered, Safari reaches signing while the fresh field is
alive.

## iOS: a connected USB-C reader signs for Safari

The iPhone also uses a connected smart-card reader as an ordinary live
CryptoTokenKit token. This was proven on 2026-07-29 with the current
optimized Profile build and an HID OMNIKEY reader:

| Consumer | TLS path | CTK algorithm and input | Card result |
| --- | --- | --- | --- |
| DVV authentication test | TLS 1.2 | `ecdsaMessageSHA256`, 9,490 B | local verify OK, 103 B, 333 ms |
| DVV authentication test, follow-up | TLS 1.2 | `ecdsaMessageSHA256`, 9,488 B | local verify OK, 102 B, 334 ms |
| `card.refineid.fi` | TLS 1.3 | `ecdsaMessageSHA384`, 130 B | local verify OK, 104 B, 336 ms |

`oma.posti.fi` also completed its login with this token. After clearing
Safari's website state and creating a clean RefineID identity,
`suomi.fi` presented the identity-certificate consent and PIN1 sheets
and completed its login too. `admin.iki.fi` then completed its
renegotiated client-certificate login from the same clean state. The
first signature returned
`authenticationRequired`, CryptoTokenKit presented PIN1, and the repeat
succeeded. Later signatures reused the card-serial-bound in-process PIN1
while still sending VERIFY PIN1 to the card every time.

The same DVV page initially failed without one new token-extension line.
Terminating only Safari and reopening the page made the exchanges above
appear and the page succeed. That is a stale Safari client-identity/TLS
process state signature: never asked is not a card or token failure.

A successful reader mint removes every stored RefineID NFC prime and
persistent RefineID smart-card registration. The connected reader is
then the only offered RefineID transport, even when the reader card and a
previously primed NFC card have different serials or key profiles, until
NFC is deliberately minted again. Apple and third-party identities are
untouched.

With several connected readers, every supported inserted card is minted and
remains live, and every live token publishes its authentication identity.
Safari owns client-certificate selection. A live two-reader test on iOS 26.5
proved that Safari ignores distinct CTK item labels and renders each signed
X.509 subject. Two cards belonging to the same person can therefore look
identical in the picker; different subjects remain distinguishable. The app
shows only whether one or several usable USB-C reader tokens are connected.

The clean build-16 trace on 2026-07-28 removed one important ambiguity.
`ctkd` gave the system-owned NFC operation 1.833 seconds from field start
to forced termination. The token minted in 44.6 ms, held its session and
started PACE on a worker before `createToken` returned. The first two
commands answered, but the first GENERAL AUTHENTICATE never called back
before the field was ended:

| Exchange | Result | Elapsed |
| --- | --- | ---: |
| SELECT master file (`A4`) | response | 14.7 ms |
| MSE:SET AT (`22`) | response | 27.2 ms |
| GENERAL AUTHENTICATE nonce (`86`) | no response | 2,005.1 ms |

This disproves a Swift-concurrency starvation theory: PACE was already
running outside the signing callback and the callback waited for that
same work. It does not yet prove whether the missing response is card
position/field strength, a Core NFC/CTK handover issue, or another
transport bug.

Resolved on 2026-08-01. The single-field prime ran PACE to completion
inside a CryptoTokenKit field -- `86` nonce 33.5 ms, the two mapping
rounds 710.0 and 604.8 ms, mutual authentication 36.6 ms -- followed by
the certificate and serial reads and a successful registration. The
difference from build 16 is ownership, not transport: here the app holds
the field, and the extension's mint publishes from the prime without
taking the card session. A GENERAL AUTHENTICATE that never returns is
therefore contention for the card, not a limit of the interface.

For comparison, the reference Rust transport captured one complete failed
Suomi.fi attempt on the same phone and card. `ctkd` opened the retained
session at 23:47:46.812 and ended it at 23:47:48.689: 1,877 ms total.
The budget below is measured backwards from that real cutoff.

| Card operation | Command -> response | Time | Elapsed | Budget left |
| --- | ---: | ---: | ---: | ---: |
| SELECT master file | 7 B -> 2 B | 12 ms | 86 ms | 1,791 ms |
| PACE MSE:SET AT | 23 B -> 2 B | 19 ms | 107 ms | 1,770 ms |
| PACE encrypted nonce | 8 B -> 22 B | 34 ms | 143 ms | 1,734 ms |
| PACE generic mapping | 107 B -> 103 B | 712 ms | 862 ms | 1,015 ms |
| PACE key agreement | 107 B -> 103 B | 603 ms | 1,492 ms | 385 ms |
| PACE mutual authentication | 18 B -> 14 B | 44 ms | 1,560 ms | 317 ms |
| SELECT PKCS#15 | 35 B -> 16 B | 43 ms | 1,620 ms | 257 ms |
| VERIFY PIN1 | 35 B -> 16 B | 72 ms | 1,700 ms | 177 ms |
| MSE:SET DST | 35 B -> 16 B | 38 ms | 1,757 ms | 120 ms |
| PSO:HASH | 67 B -> 67 B | 92 ms | 1,858 ms | 19 ms |
| PSO:COMPUTE DIGITAL SIGNATURE | 19 B -> no reply | 7 ms to cutoff | 1,877 ms | 0 ms |

The final PSO has taken about 390 ms when it completes, so this attempt
needed roughly 380 ms more field time. The two card-side PACE EC rounds
alone consumed 1,315 ms.

The roughly 20-second lifetime seen earlier belonged to an app-owned
Core NFC tag-reader session, which priming no longer uses: since
2026-08-01 the prime runs in the app's own CryptoTokenKit field. That
field is held by the app rather than by a Safari operation, so it is not
rationed the way the signing budget above is. Safari's CryptoTokenKit
operation owns a replacement slot and has measured between about 1.8 and
2.45 seconds, depending on the attempt; the longer number cannot be used
as Safari's signing budget.

## Swift PACE arithmetic is no longer a field-budget problem

The original curve implementation stored fixed-width limbs in heap-backed
arrays and kept every intermediate point in affine coordinates. The first
caused allocation and copy-on-write traffic in every field operation; the
second calculated a field inverse for almost every scalar bit.

The limbs now use `InlineArray`, and scalar multiplication uses Jacobian
coordinates with mixed affine addition. It performs one field inverse when
the finished point is converted back to the public affine representation.
An independent full-width scalar vector agrees byte-for-byte with OpenSSL
3.6.3, in addition to the curve-order and synthetic PACE tests.

Measured on the M1 development Mac with Apple Swift 6.3.3:

| Build and implementation | One 383-bit `k * G` |
| --- | ---: |
| Debug, heap limbs, affine points | about 1,065 ms |
| Release, heap limbs, affine points | about 80 ms |
| Release, inline limbs, affine points | 18-20 ms |
| Release, inline limbs, Jacobian points | 3.5-5.0 ms |

These are host CPU measurements, not card or radio timings. A terminal PACE
run performs four full-width scalar multiplications and one shorter nonce
multiplication, so the change removes hundreds of milliseconds of avoidable
host work. The card's two long GENERAL AUTHENTICATE calculations still
dominate the phone trace.

The benchmark is reproducible from the repository:

    swiftc -O -whole-module-optimization \
      CardCore/Sources/CardCore/**/*.swift \
      Scripts/BrainpoolBenchmark.swift \
      -o /tmp/refineid-brainpool-benchmark
    /tmp/refineid-brainpool-benchmark

The shared Xcode scheme now launches with the `Profile` configuration:
`-O`, whole-module compilation, debug symbols and the DEBUG diagnostics.
Tests remain Debug. This matters on the phone -- installing the ordinary
Run action must not silently put `-Onone` arithmetic inside the NFC window.
`-Ounchecked` was also measured and was no faster than `-O`, so the safety
checks remain.

Xcode 26 still injects coverage into the local Swift package when building
through the scheme unless `CLANG_COVERAGE_MAPPING=NO
ENABLE_CODE_COVERAGE=NO` is supplied on the command line. A verified live
artifact has no `__llvm_prf*` or `__llvm_cov*` sections in either the app
or token extension.

## PACE is at this card's floor

Measured 2026-08-01 by reading EF.CardAccess from the card. It
advertises two suites and nothing else:

| Advertised | Domain parameter |
| --- | --- |
| PACE-ECDH-GM-AES-CBC-CMAC-256 (`0.4.0.127.0.7.2.2.4.2.4`) | 16, brainpoolP384r1 |
| PACE-ECDH-CAM-AES-CBC-CMAC-256 (`0.4.0.127.0.7.2.2.4.6.4`) | 16, brainpoolP384r1 |

So the two candidate savings are both absent. There is **no integrated
mapping**: the mapping Diffie-Hellman the card spends its first
GENERAL AUTHENTICATE round on cannot be avoided by choosing a
different suite. And there is **no smaller domain parameter**:
brainpoolP384r1 is the only curve on offer, so the scalar
multiplications cost what they cost.

Chip-authentication mapping is not a saving either. CAM folds chip
authentication into the mapping step, which is worth having when a
terminal performs chip authentication separately; RefineID does not, so
CAM would add the verification work of a protocol we do not run to a
handshake that would not get shorter. The suite stays as it is.

What does move the number is the field. The same card ran PACE in
1,068 ms in an app-owned field held still, against 1,333 ms during a
Safari login on the same day -- the two card rounds measured 535.6 and
370.2 ms in the first, 692.1 and 593.0 ms in the second. Coupling and
card position are worth more than any suite choice available here, and
that is a holder instruction rather than a code change.

## Why one login asks for the card more than once

Measured on device 2026-08-01, one client-certificate login:

| Field | Opened | What it did | Ended |
| --- | ---: | --- | ---: |
| selection | 09:07:36.794 | mint, session taken, PACE prepared in 1,444 ms | 09:07:38.921 |
| signature | 09:07:42.440 | mint, PACE, VERIFY PIN1, PSO -- signed in 1,903 ms | 09:07:44.606 |
| unused | 09:07:55.423 | mint, session taken, PACE started, nothing signed | -- |

The first field exists so the identity can be published for Safari's
certificate sheet. `ctkd` ends it about two seconds after the mint,
which is 09:07:38.921 here. The holder is still reading the consent
sheet at that point: Safari asked for the signature at 09:07:42.146,
3.2 seconds after the field had gone. The extension answered `-7` in
4.0 ms, `ctkd` opened a replacement field, and the signature completed
there. That is the second prompt, and it is the documented
ended-field-is-an-absent-token path working correctly.

Neither field is wasted work this side of the boundary: the consent UI
is outside the extension, cannot be preselected by it, and its duration
is the holder's reading speed. Once Safari remembers the choice for a
site, the repeat login reaches the signature inside its first field.

The third field is the open question. It opened 11 seconds after a
successful signature, minted, took a session, started PACE, and nothing
ever asked it to sign. Candidates, in order of likelihood: a second TLS
connection to the same origin performing its own client-certificate
handshake; a system consumer re-materializing the identity; or an app
query that wakes `ctkd`. Distinguishing them needs a trace taken with
the app closed and a single request in flight.

## Why the certificate cannot be chosen before the card is presented

Safari fills its client-certificate picker by enumerating `SecIdentity`
objects matching the server's CA hints. A `SecIdentity` is a certificate
plus a *usable private key*, and for a CryptoTokenKit smart-card token
that key exists only while the token does -- which is only while the
card is in a slot. No card, no key, no identity, nothing to list.

So the field must open first, for no reason except to bring the identity
into existence so the picker has something to show. That is what makes
the selection field structurally wasted rather than merely unlucky.

`registerSmartCard` does make a registered token's certificate
*attributes* visible cold. Safari does not select from attributes, so
they never reach the picker. This is the still-open item already filed
in `Documentation/releng/apple-feedback-nfc-ctk-registration.md`.

The Apple-side fix would be to populate the picker from registered
smart-card tokens' attributes, take the holder's choice, and only then
ask for the card -- one prompt, in the order a person expects. Nothing
in a token extension can reorder it.

Two things do help today. Safari remembering a site's choice removes the
picker, and the repeat login then reaches the signature inside its first
field. And an in-app handshake avoids the problem entirely, because the
app holds the card for the whole exchange; that is a product decision,
not a tweak, but it is the only route to a single-prompt login that does
not wait on Apple.

## An untried idea: release the held session when no signature comes

Not implemented. Recorded so it is not rediscovered as a new thought.

Measured on 2026-08-01, the selection field published its identity at
`36.820` and `ctkd` ended the field at `38.921`. The picker was usable
for the whole of those 2.1 seconds while "Ready to Scan" sat in front of
it. The extension cannot dismiss that panel -- `endSession` belongs to
`TKSmartCardSlotNFCSession`, which `ctkd` created and the extension
never sees.

What the extension does control is whether it keeps the card session. If
holding it is part of what keeps the field alive, releasing on publish
would let the panel go early. The idea is to hold as now but start a
short timer, and release if no `sign` request has arrived within roughly
300 ms: a signature field asks within about 69 ms, so the timer would
never fire on the path that matters, while a selection field would
release every time.

Two reasons this is an experiment and not a change. The two seconds look
like `ctkd`'s own budget rather than something we extend -- the Rust
reference measured 1.877 s and the Swift path 2.13 s under quite
different session handling -- so releasing may buy nothing at all. And
rule 1 below exists because releasing early breaks a signature that does
arrive; a selection field and a signature field are indistinguishable at
`createToken` time. Judge it by whether the panel dismisses sooner in
the extension trace, on the same card, both ways.

Each cost a measured failure to learn, and each looks like a platform
limitation when broken.

1. **Hold the card session taken during `createToken` and reuse it in the
   signature.** `ctkd` owns the NFC slot and ends it about two seconds
   after the mint, so a fresh session in the signature finds nothing and
   fails with `TKError -7`.
2. **Release that session only when the slot is genuinely `missing`.**
   Releasing on any other state tore down a signature part way through a
   read.
3. **Never read from the card what the prime already holds.** The
   authentication certificate (`EF.4331`), its matched issuing CA, and the token
   serial are public and unchanging; re-reading any of them costs more
   than the field has left. Priming reads only the authentication certificate,
   deferring the qualified signature certificate (`EF.4332`) to on-demand
   lazy loading during signing. Identity creation also resolves a known
   issuing CA from the app bundle before using the on-card compatibility
   fallback.
4. **Memoize retry counter probes.** Credential retry counters are probed at
   most once per card session across activation checks and credential reporting,
   avoiding redundant NFC roundtrips.

Two more, learned the same way: a sessionless `TKSmartCard.transmit` on
the built-in NFC slot is parked by `ctkd` forever, and `createToken` on
that slot must do no card I/O at all.

## Why there are two token extensions

`ctkd` polls for NFC cards using the select-identifier set an *extension*
declares. A driver that declares none gives it nothing to select, so the
card is never surfaced and the system's scan sheet waits forever.
Declaring the identifier on the driver that mints the token breaks the
other half: `ctkd` then stops invoking that driver even for the app's own
slot, nothing is minted, and registration fails on a token that does not
exist.

So the roles are split. `RefineIDTokenExtension` mints and holds the
registration and declares no identifier; `RefineIDDiscoveryExtension`
declares the eMRTD identifier and refuses to create tokens. The
identifier is the travel-document application, which a Finnish identity
card genuinely implements and which is selectable before PACE -- unlike
PKCS#15, which answers `SW=6982` until the secure channel exists.

## Secrets on the device

The card access number and PIN1 are stored as keychain items that are
`WhenUnlockedThisDeviceOnly` and non-synchronizable, so neither is
written into a backup, restored onto another device, or sent to iCloud.
Neither attribute implies the other; both are set.

Neither is behind a biometric access control at present. PIN1 was
briefly, and it is worth recording why it is not now: the token extension
has no interface to answer a prompt with while signing a request made in
Safari, so a gated value cannot serve the flow this app exists for.
Gating it also broke storage outright, because a protected item survives
a delete that skips the authentication interface and the add that follows
fails as a duplicate. The gate can return once the flow it must not block
is proven.

There is no fifteen-minute software signing window on iOS now. Safari can
request the token extension while the containing app is absent, and that
extension has no reliable UI in which to reopen a window. When the holder
explicitly chooses to store PIN1, the extension reads that stored value
for each contactless signature. Device unlock and the system certificate
consent remain the surrounding controls.

Reader authentication probes only PIN1 immediately before VERIFY. PIN2 and PUK
are not part of identity authentication and are read only when the holder opens
the explicit status/diagnostics flow. A freshly entered PIN1 that the card
accepts may remain in zeroizing, card-serial-bound memory for the extension
process lifetime. A confirmed PIN1 rejection removes the automatic identity's
stored PIN1, physical-card prime, and CryptoTokenKit registration; unrelated
transport and TLS failures leave them intact.

## Instruments

Every fix on 2026-07-27 came from an instrument rather than from
reasoning about the code, including the two that made priming work at
all. They are worth keeping.

- **Development-only in-app diagnostics** (Status -> Diagnostics): Debug
  and optimized Profile builds show registered tokens, watcher tokens,
  driver configurations, prime presence, stored-credential policy,
  platform transport availability, and the extension trace, with share
  and copy. TestFlight and Release exclude the diagnostics source files
  from the app target, and since 2026-07-30 carry no logging of any kind
  either -- no system log line, no file, no trace item, and not even the
  message literals. The release manager's `inspect-archive` command fails an archive in
  which any of them reappear. The report deliberately does not enumerate
  `com.apple.token` identities:
  that supposedly read-only query was measured presenting the NFC reader
  sheet and changing the failure being diagnosed.
- **Extension trace**: a rolling keychain buffer both extensions write
  and the app reads, in Debug and Profile only. On iOS 26
  `log stream --device` is gone and `log collect` fails, so this is the
  only way to see inside an extension. Sizes, instruction bytes, status words and timings only --
  never a PIN, CAN, serial or holder name, and `VERIFY` is redacted
  wholesale.
- **DEBUG-only launch modes**: `--diagnostics`, `--trace`,
  `--reset-card-state`, `--set-can`, `--forget-can`, `--set-pin1`,
  `--prime`. Absent from a Release build,
  verified by grepping the built binary.
- **macOS logging still works**, unlike iOS: `log show --predicate
  'subsystem == "fi.refineid.ReFineID"'` shows the extension directly.

## Known rough edges

- The certificate picker cannot be preselected on iOS. `SecIdentitySetPreferred`
  is macOS only, and the picker is a consent step rather than
  disambiguation: handing over a client certificate reveals the holder's
  identity to that site permanently. macOS can now remember a site
  through the card-details screen.
- On iOS the picker and the NFC sheet are both system UI and can overlap,
  with the picker drawing behind the sheet. Their stacking is not ours to
  set; a shorter signature is the only lever.
- On macOS the app and its extensions share no keychain access group, so
  the app cannot show the extensions' trace there. macOS logging covers
  it; on iOS the shared group is present and the trace works.
- Stale registrations from old build locations produce duplicate
  identities in the picker, one of which cannot sign. Deregister with
  `pluginkit -r` and re-insert the card so `ctkd` re-enumerates.

## Status update: 26.9.11

- **Cross-platform RAPP qualification verified**:
  Device pairing using clean 6-digit numeric codes (Noise XXpsk3) is verified
  and qualified across all supported platform combinations:
  Android - Mac, Android - Linux, Mac - iPhone, Mac - Android, Linux - Android,
  and Windows. All references to deprecated QR pairing are removed from documentation.
- **macOS App Store release path**:
  - **Virtual ID Card on macOS**: Lifting `DemoMode` and `VirtualIDCard` to
    macOS to provide an "Explore with a Virtual Demo Card" action in `StatusView`
    empty-state, preventing Guideline 2.1(a) rejection and enabling reviewer walkthrough.
  - **SCS Server Opt-In**: The 127.0.0.1 loopback signing server is made strictly
    opt-in behind an explicit Settings toggle, avoiding unprompted
    `SecTrustSettingsSetTrustSettings` dialogs on launch.
  - **Mac App Store Screenshots**: Building a dedicated screenshot pipeline
    to capture localized 2880x1800 App Store desktop screenshots driven by
    synthetic Virtual ID Card states.
