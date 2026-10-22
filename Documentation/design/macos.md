# The Mac app

The Mac app is one window. It says whose card can log in and signs
documents with it. There is no Settings window and no Help menu. The app
menu holds About, which links the site. The View menu holds Demo Mode.

## The window

The status window (`StatusView`) is sized to its content. From the top:

1. The identity line.
2. The document drop area, while an identity is available or documents
   are waiting.
3. The signing controls and the outcome of the last action.

A card waiting to be taken into use replaces these with the activation
form. A contactless card that needs its access number replaces them with
the six-box access number entry.

## The identity line

`IdentityLine.derive` picks the line from the requester's facts
(`RequesterFacts`). `IdentityStateView` draws it.

| State | Line | Control |
|---|---|---|
| No card here, no phone paired | "Avaa puhelimesta RefineID etäkäyttö ja syötä yhdistämiskoodi:" and the six-box code entry | |
| Empty reader here, no phone paired | "Syötä kortti lukijaan." | |
| The phone forgot this computer | "*phone* unohti tämän tietokoneen" above the pairing prompt | |
| Card in this Mac's reader | *HOLDER NAME* | key |
| Card in this Mac's reader, not ready after a while | the re-insert warning | key |
| Paired phone out of sight | "Yhdistetty puhelin: *phone*" | minus |
| Paired phone, card on its way | "Yhdistetään… (yhdistetty puhelin: *phone*)" | minus |
| Paired phone with its card | "*HOLDER NAME* (yhdistetty puhelin: *phone*)" | minus |
| Paired phone without a card | "Aseta kortti puhelimeen." or "Syötä kortti puhelimen kortinlukijaan.", then "(yhdistetty puhelin: *phone*)" | minus |
| Paired phone, empty reader here | "Syötä kortti lukijaan. (yhdistetty puhelin: *phone*)" | minus |

A card in this Mac's reader shows nothing while it settles, which takes
well under a second.

The phone part of a line is in the secondary text color. The phone's
reader decides which instruction a phone without a card gets (RAPP
v26.10.22 §8.4 item 6). The controls sit at the right end of the line,
vertically centered. Each is a button with a VoiceOver label and a tooltip.

- **Minus** (`person.badge.minus`, "Poista puhelimen yhdistäminen"). It
  forgets the paired phone at once, with no confirmation. The line drops
  the phone, and the pairing prompt returns. The pairing ends as RAPP
  v26.10.22 §4.6 says. An open session closes with `pairing_revoked`.
  Without a session, the record stays forgotten until the next session
  delivers that close. A same-account record that would pair the phone
  again is removed too.
- **Key** (`key`, "PIN-koodit"). It opens the PIN codes window.

A Mac pairs one phone. The pairing prompt shows only while no phone is
paired, and there is no "forget all".

## The PIN codes window

`PinCodesWindow` holds `CardManagementView` for the card in this Mac's
reader: the attempts left, and changing or resetting PIN 1 and PIN 2. Only
the key opens it. It has no Window menu item, never opens at launch, and is
not restored. It closes when the card leaves the reader.

## A local card overrides the phone

While a card is in this Mac's own reader, the Mac neither holds nor dials
its session with the paired phone:

- `CardPresence` reports the card to `PersistentTokenRegistry`. The
  registry withdraws the phone's published identity, closes the session and
  stops browsing for the phone.
- `RequesterTransportPolicy` leaves nothing to dial, so no dial, redial or
  Bluetooth scan starts.
- An operation the token extension hands over is refused.
- Document signing uses the local card.
- The identity line shows only the local card.

When the card leaves the reader, browsing and dialing resume, and the phone
line returns. The pairing is kept throughout.

## Running without the window

Closing the window leaves the app running in the Dock. The app holds the
one Bluetooth link to the phone, which the remote card's token extension
uses. Clicking the Dock icon or opening the app again brings the window
back. Only quitting ends the app.

The first launch of a copy in an Applications folder registers the app as
a login item. macOS lists it under General > Login Items, where the holder
can remove it, and a removal stands. A login launch opens no window.

## Document signing

Documents are dropped on the drop area or picked with its file dialog.
Several can wait together. A PDF is signed in place (PAdES). Anything else,
or a mix, is signed into one ASiC-E container. Several PDFs are each signed
into a chosen folder. PIN 2 for a local card is typed in the window. PIN 2
for a paired phone's card is asked on the phone and never reaches the Mac.

## Development builds

Every failure path reports to `DevErrorLog`. The Errors window is a
floating panel. It opens by itself when an error arrives, without taking
focus, and the Window menu opens it too. The Diagnostics window exists only
in development builds as well. TestFlight and Release builds have neither.
