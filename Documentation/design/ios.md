# iPhone and iPad

The iPhone and iPad app as it is. The UI principles every screen follows
are in [ui.md](ui.md).

## The identity row

The main screen's "Identity" section shows the holder as one row: the
`person` symbol, then the holder's name. The row opens no other page.

- **Identity on the phone.** The row ends in a red `minus.circle` button,
  "Remove identity from phone". It removes the identity from the phone at
  once, with no confirmation, and the card access number entry returns.
- **Card in an attached reader.** Each card in the reader has the same row,
  with no button: the name comes from the card in the reader.

Removing the identity unregisters the card's token, so the system's token
list no longer holds it and Safari is not offered the card. It also deletes
the stored certificates the token is built from and revokes the phone's
pairings. The card access number stays stored, so setting the card up again
needs only a tap. The token extension may keep PIN 1 in memory until
iOS ends the extension, which the app cannot do. With no token registered,
that memory serves nothing.

The app does not read, store or show the holder's photo.

## The card in the phone's near field

When a paired computer needs the card and the holder's card is a
near-field card, the phone opens a near field on the CryptoTokenKit slot
(`TKSmartCardSlotManager.createNFCSlot`), runs PACE and serves the
operation. The field, its card session and the PACE channel stay open for
the next operation from any session for as long as the platform keeps the
slot (`WarmNearField`). A burst of signatures, such as the several TLS
handshakes of one browser login, costs one tap and one PACE; PIN 1 is
verified with the held PIN before every signature, since the card keeps
no PIN state between signatures.

- **Upkeep.** The slot is looked at every second; one SELECT keeps it
  alive after 2 seconds without an exchange.
- **End.** The field ends when the slot is gone (the card left, the sheet
  was closed, or the platform ended it), when a keep-alive or an operation
  goes unanswered, 50 seconds after it was asked for, when the app goes to
  the background, when serving stops or the last session closes, and
  before a PIN prompt, which the sheet would cover.
- **Summons.** An operation that finds the field warm runs on it while the
  app sits inactive under its own sheet. An app with no warm field, or in
  the background, summons the holder.
- **Errors.** A development build reports every opening and ending of the
  field with its cause, and every refusal during the reader's pause, to
  the error display.

The platform sets the limits. Measured on an iPhone 15 Pro Max, an idle
slot goes 6 to 8 seconds after the last exchange and a kept-alive slot 11
to 22 seconds after it was given; after any ending the reader refuses a
new slot for 8 to 11 seconds (`nfcd` code 47). Core NFC's
`NFCTagReaderSession` gives no longer field: a tag connection is limited
to about 20 seconds within a 60-second reader session, with a cooldown
between sessions, and `restartPolling()` reactivates the card and reruns
PACE. Core NFC is also unavailable to extensions and allows one reader
session in the system, so it would be a second NFC stack beside the slot
the token extension signs through.

## Setting a card up

The setup entry is labelled "Card Access Number (CAN)" for every card:
one hidden field of four to twelve digits, then the eye that shows them,
then the camera that reads a personal card's six printed digits. A scan
leaves the field hidden. "Read Identity Card" reads the card on the
phone's antenna in one hold, and the card decides on that tap what the
digits are.

- **Which card.** The card's first answer, before any password, names
  its kind: `6985` an organization card, any other answer a personal
  card.
- **Personal card.** The entry must be the six digits printed on the
  card. Any other length ends the hold as an incorrect card access
  number, with no PACE run and nothing sent. Six digits run PACE, and
  the number is stored once PACE proves it.
- **Organization card.** The card has no printed number: it opens only
  with PACE and PIN 1 or PIN 2 as the password (FINEID S1 v4.0,
  organizational cards, section 2.1), so the entry is its PIN 1. PACE
  with PIN 1 opens the channel the certificates are read through, and
  the organization prime (certificates and chip serial only) is stored
  under the card model's historical bytes. PIN 1 is spent on that one
  handshake and is neither stored nor held; the field is emptied when
  the hold ends, and the digits never become a card access number.
- **Wrong PIN 1.** The card's refusal is shown as for any PIN 1, with
  the tries left, and the retry floor decides on the state MSE:Set AT
  reports before the card takes a try.

An organization card set up this way signs on the phone's antenna the
way the Mac's reader does: every operation opens its own PACE channel
with the PIN it spends, PIN 1 for an authentication, PIN 2 for a
qualified signature, with no VERIFY. A paired computer's operation does
the same on the warm field's plain channel; the certificates come from
the prime. PIN management is not offered for an organization card on
the phone.

## The activation screen

Activation is left only through the bar's back button. The system back
button is hidden, which also turns off the edge swipe: a swipe that
started as a scroll closed the screen in the middle of entering the codes.

## The PIN prompt

A paired computer's request that needs a PIN the phone does not hold
shows one system alert. Its title names the act and its one sentence
names the computer by its display name, as given:

- **Authentication.** Title "Authentication", "%@ asks you to
  authenticate.", a "PIN 1" field.
- **Signature.** Title "Signature", "%@ asks you to sign %@." with the
  document name, a "PIN 2" field. A batch says "%@ asks you to sign the
  documents %@." with its names as a list in signing order, and a request
  without a document name "%@ asks you to sign.".

The buttons are "Cancel" and "OK". When the card refused the PIN entered
last, the card's notice stands above the sentence. The time-sensitive
notification that comes with the prompt carries the same title and
sentence.

## A locked phone

A locked phone starts no credential action for a paired computer: no login
with the held PIN 1, no PIN prompt, no signature. The notification reads
"%@ asks you to authenticate with Basic PIN 1. Unlock your phone." or "%@
asks you to sign with Signature PIN 2. Unlock your phone.", and the computer shows "Unlock your phone, please.".
Unlocking continues the request. The rule and its limits are in
`Documentation/decisions.md` (2026-11-07).

## The NFC sheet

Every operation on the phone's own antenna draws one meter in the system
NFC sheet's message in two lines: the operation's name, then one ball per
step. A ball is blue once its step is reached, white while it waits, and
red for the step that broke. The sheet shows no other sentence while it
works.

| Operation | Name | Steps |
| --- | --- | --- |
| First setup | "Reading Identity Card" | card found, secure channel, certificate, stored, registered |
| Browser authentication for a computer | "Authenticating" | card found, secure channel, certificate, PIN, signature |
| Signature with PIN 2, local or for a computer | "Signing" | card found, secure channel, certificate, PIN, signature |
| Certificate read for a computer | "Reading Identity Card" | card found, secure channel, certificate |
| Retry counters and activation state | "Reading Identity Card" | card found, secure channel, certificate |
| Activation | "Activating Card" | card found, secure channel, PIN |
| PIN change | "Changing PIN 1", "Changing PIN 2" | card found, secure channel, PIN |
| PUK reset | "Resetting PIN 1", "Resetting PIN 2" | card found, secure channel, PIN |

- **Opening.** While the holder looks for the spot, every ball is white.
- **Errors.** The step that broke turns red; where the operation has an
  error sentence, the sentence then replaces both lines.
- **Warm field.** Between operations the sheet keeps the last operation's
  meter, every ball blue, or its error sentence. The next operation draws
  its own meter.
- **Security delay.** During a card's anti-tamper delay at setup, the
  seconds left follow the balls on the second line.

## A computer that withdraws or forgets the phone

A paired computer that a card in its own reader suspends, or that quits,
closes its session with `service_withdrawn` (RAPP v26.11.8 §4.5 items 8
and 9). The phone ends that session without a close of its own. The
session's operation ends with it, and its PIN prompt and its summons go.
The pairing stays, nothing stored changes, and no error is shown or
reported. The phone keeps serving every pairing, and the computer's next
dial opens a session as any other.

A computer whose holder turns remote use off forgets the phone (§4.6 item
6). An open session closes with `pairing_revoked`, and the phone forgets
the computer at once: it leaves "Paired computers". With no session open
the phone is told nothing and forgets the computer by idle expiry.

The phone shows no connection state for each computer: "Paired computers"
lists names only. The "Connected" badge on the "Remote Access" row, and
the green antenna on its screen, follow whether any session is open, so a
computer that withdraws stops counting there as its session ends.

## Idle expiry

A pairing that has had no established session for 30 days expires (RAPP
v26.11.8 §4.6 item 5). The phone records each session as it is
established and as it ends, and checks every pairing at launch and every
hour while the app runs; a computer with a session open never expires.
An expired computer leaves "Paired computers" silently: nothing is sent,
shown or reported. If that computer opens a session within the next 30
days, the phone tells it with `pairing_revoked`.

## Document signing

The signed file is offered for export after signing, named the way the
Mac names it: by the signature timestamp's generation time, as described
in [macos.md](macos.md#document-signing). The time-stamp authority
signatures ask is set in the Settings app, prefilled with the qualified
service the app ships with.

## Verify

The Verify screen reports a chosen signed document in cards: the
"Document" card, then one "Signature" card per signature. The verifier
implements the shared design in refineid-core
`doc/architecture/document-verification.md`.

- **Rows.** Every row has one shape: the label on the first line and the
  value, when there is one, under it, both leading-aligned and wrapping as
  needed. A row with a mark keeps it alone in a trailing column, level
  with the label's first line, so every mark sits at the same trailing
  edge.
- **Document.** The card shows one row, "Document", with the file name
  under it and no mark.
- **Signature.** The person row (the `person` symbol, "Person" and the
  signer's name under it), "Issuer" with the issuing CA's name as the
  signer certificate states it, then "Document intact", "Signature" and
  "Certificate chain", each with its mark. The signer's name appears in
  this row and nowhere else.
- **Timestamp.** One time per signature: the best signature time, the
  earliest anchored time (a document timestamp that proves the signature
  counts), with the mark. A claimed time alone shows "Unproven" after it,
  a failed token the failing mark, and no timestamp "None".
- **Archive timestamp.** Shown when the signature has one: an XAdES
  `ArchiveTimeStamp` whose input the verifier recomputed, or a PDF document
  timestamp over a revision whose document security store holds
  revocation values. The latest anchored time with the mark, a claimed
  time with "Unproven", or the failing mark.
- **Revocation.** The state without a time: the mark alone when good,
  "Revoked" with the failing mark, "Not checked" when no answer came, and
  a spinner in the mark column while the check runs.
- **No signature.** A document without a signature row, a PDF carrying
  only document timestamps among them, says "The document carries no
  signatures." A CMS SignedData file (`.p7m`, `.p7s`, `.p7c`, or a DER
  ContentInfo of type signedData) says "This signature format (CAdES)
  can't be verified here yet."
- **Unsupported.** A signature whose profile is not supported shows the
  person row's symbol and label, "The signature profile is not
  supported." under it and the failing mark.
- **Signature level.** The baseline level the document was verified to
  reach, "B-B", "B-T", "B-LT" or "B-LTA" (EN 319 142-1 and EN 319 132-1,
  clause 6), judged from what the document carries: B-T needs an anchored
  timestamp, B-LT revocation values in the XAdES `RevocationValues` or the
  PDF document security store that alone answer the whole path, B-LTA an
  anchored archive timestamp; a PDF document timestamp counts as one only
  when the revision it covers carries a store that alone answers the
  path. Revocation values elsewhere, inside a CMS among them, decide the
  verdict but raise no level. A live revocation answer does not raise it.
  A signature that does not verify over intact data shows no level.
- **Until when.** The archival level says the last day the document
  stays verifiable before it needs refreshing: "Verifiable until 2 Aug
  2034" ("Tarkastettavissa 2.8.2034 asti", "Kan granskas till 2 aug.
  2034") with the mark. The day is the UTC day one second before the
  end, since DSS counts the end instant itself as expired: an end of
  2035-01-01T00:00:00Z shows 31 Dec 2034, and DVV's "Maximum validity
  time: 2034-08-02 23:59:59 (UTC)" shows 2 Aug 2034. The end is that of
  the last anchored archive timestamp in document order that counts for
  the level (the last PAdES document-timestamp revision counted as
  archive, or the last XAdES `xadesv141:ArchiveTimeStamp`), whatever
  times the clocks name: the earliest of the notAfter of every
  certificate on its authority's verified chain, anchor included, and
  the day its signature algorithm and key size stop being acceptable
  under EU DSS 6.5.1's default validation policy (`CryptographicSuitability`
  in CardCore, transcribed from `policy/constraint.xml`
  `AlgoExpirationDate`; RSA from 1900 bits until 2027-01-01, from 3000
  bits until 2035-01-01, ECDSA from P-256 and SHA-256, SHA-384 and
  SHA-512 without end), the same date DSS and DVV's validator report.
  Once the end has passed it says "Needs a new archive timestamp"
  ("Vaatii uuden arkistointiaikaleiman", "Behöver en ny
  arkivtidsstämpel") without the mark. When a certificate's notAfter
  cannot be read or the chain is empty, no date is claimed: the row
  says "Validity period could not be determined" ("Voimassaoloa ei
  voitu selvittää", "Giltighetstiden kunde inte fastställas") without
  the mark.
- **Trusted lists.** Anchors come only from the EU trusted lists the
  app fetches and caches. A cached copy verifies at once, offline too,
  and is fetched again in the background when it is stale. With nothing
  cached the first verification fetches the lists; when the device is
  offline it says "No EU trusted lists are stored yet and this device is
  offline. Connect to the internet once to fetch them; after that,
  documents verify offline too." The fetching itself is not shown: the
  trusted-lists section, with its retry button, appears only when a
  fetch failed and no lists or only stale ones are stored.
