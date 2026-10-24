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
closes its session with `service_withdrawn` (RAPP v26.10.22 §4.5 items 8
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
v26.10.22 §4.6 item 5). The phone records each session as it is
established and as it ends, and checks every pairing at launch and every
hour while the app runs; a computer with a session open never expires.
An expired computer leaves "Paired computers" silently: nothing is sent,
shown or reported. If that computer opens a session within the next 30
days, the phone tells it with `pairing_revoked`.
