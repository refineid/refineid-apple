# Contactless cards on macOS

How a sealed contactless card becomes a published identity on a Mac,
and the platform facts the design rests on. The flow is out of the
first App Store release (`Documentation/decisions.md`, 2026-08-11):
`FEATURE_CONTACTLESS` is off and the `application-groups` entitlement
it needs is removed, so no group container is created. This document
describes the flow as built.

## The flow

A contactless FINEID card refuses SELECT of its application with
`6982` until PACE has run (FINEID S1), and PACE needs the card access
number printed on the card face. On a Mac the token driver runs PACE,
so the number the holder types in the app has to reach the driver.

The status window shows one entry row - CAN beside six digit boxes -
only when the reader's slot proves the card is on a contactless
interface. The sixth digit submits on its own. The driver tries a
number once; a refusal shakes the row and turns it red, and a mint
that succeeds replaces the row with the published identity.

## Interface detection without card I/O

A contactless card has no answer to reset of its own; a PC/SC reader
synthesizes one with the fixed prefix `3B 8x 80 01` (PC/SC part 3,
section 3.1.3.2.3). The slot's ATR therefore answers "which interface
is this card on" without opening a session, and the entry row is
gated on exactly that. A contact card is never asked for a CAN.

## How the number reaches the driver

`TKTokenDriver.Configuration` cannot carry it. The SDK header is
explicit: `driverConfigurations` is populated for the hosting
application only, and every other caller - the token extension
included - is handed an empty store. A number written there is
unreadable exactly where it is needed.

The working channel is the app group container both processes are
entitled to (`OfferedAccessNumber` in CardCore): the app writes the
offered number as an owner-only file, the driver reads it during
unseal, and a refusal marker file flows back the other way for the
entry row's feedback.

The offer lives for the app run: a stale one is withdrawn at launch,
the current one at quit. It deliberately survives the card leaving
the field - a contactless card leaves between taps, and the offer
exists to serve the next tap. An earlier version withdrew it on card
departure, which deleted the number in the moment between lifting the
card and laying it back, starving the very mint it was typed for.

## Why the row asks for the card again

`ctkd` evaluates a card against its drivers when the card arrives.
When no driver can serve it - a sealed card before its number is
entered - the verdict stands until the card arrives again. Only a
physical arrival counts: a PC/SC warm reset (`SCARD_RESET_CARD`) and
an unpower (`SCARD_UNPOWER_CARD`) both succeed at PC/SC level and
produce no re-evaluation, which was established empirically against
a dual-interface reader. No software substitute exists, so after the
number is offered the row says the one thing that works: lift the
card and lay it back.

The PC/SC reset is still performed (`SlotCardReset`, through the C
target `PcscCardReset` - the PCSC module is marked unimportable from
Swift while its C interface remains supported), so a future macOS
that re-evaluates on reset starts working without a change here.

## One attempt per number

PACE failures are counted by the card, which slows down after refused
attempts. Two mechanisms keep the flow to one attempt per number
entered: nothing is sent while typing (the boxes submit only when the
sixth digit lands), and the driver latches a refused number by
fingerprint (`RefusedUnseal`) so re-arrivals of the card do not retry
it. Entering a different number is what re-arms the attempt.

## Reading the extension's side

Debug bundles carry their code in `<name>.debug.dylib` beside a
loader-stub executable; probes of binary content and the install
gate's change detection both have to look at the dylib, not the
executable. The extension's file log lives in its container under
`tmp/refineid-token-extension.log` in development builds; release
builds write no diagnostics.

## Organization cards

An organization card (FINEID S4-2) has no card access number. On the
antenna it answers `6985` to everything but EF.CardAccess until PACE
has run with PIN 1 or PIN 2 as the password (FINEID S1 v4.0,
organizational cards, section 2.1), so nothing identifies the card or
yields its certificates before the holder types a PIN.

- **Contact first.** A contact read of an organization card leaves its
  certificates and chip serial in `OrganizationPrimeStore`, keyed by the
  historical bytes of the answer to reset, which the card carries
  unchanged on both interfaces (card-types.md). The newest contact read
  of a card model replaces the one before it.
- **On the antenna.** The driver publishes the identity from that prime
  with no card I/O and no PIN. Without one, the window keeps "Put the
  card in the reader's card slot."
- **Signing.** The PIN is settled first, from the system PIN sheet or
  the PIN 1 the card accepted before. PACE then runs with it over the
  suite EF.CardAccess names (generic mapping, P-384 preferred). MSE:Set
  AT answers the PIN's state, and the retry floor decides on it before
  the first GENERAL AUTHENTICATE, because the card takes a try there and
  returns it only when the handshake completes. A completed PACE counts
  as the PIN verified: the key signs with no VERIFY, and no VERIFY
  status probe is sent in the channel, which the card refuses there
  (`6988`). PIN 1 signs with the authentication key after the chip
  serial matches the prime's; PIN 2 signs in DF.ESIGN under the
  organization qualified key reference, the digest inline in one
  PSO:CDS, and the signature is verified against the prime's
  certificate before it is returned.
- **Documents.** The window's document signing finds the card on the
  antenna by its `6985` and opens it with the PIN 2 typed for the
  signature, the same way.
