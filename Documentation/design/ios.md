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
