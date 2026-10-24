# The Mac app

UI text is quoted in its English source form; the translations are in
`Sources/App/Localizable.xcstrings`.

The Mac app is one window. It says whose card can log in and signs
documents with it. There is no Settings window and no Help menu. The app
menu holds About, which links the site. The View menu holds Demo Mode.

## The window

The status window (`StatusView`) is sized to its content. Its toolbar,
in the title bar, holds one control: the remote-use switch at the right
end, where it takes no room from the content. From the top, the window
shows:

1. The identity line.
2. The document drop area, while an identity is available or documents
   are waiting.
3. The signing controls and the outcome of the last action.

A card waiting to be taken into use replaces these with the activation
form. A contactless card that needs its access number replaces them with
the six-box access number entry.

## Remote use

One toolbar button is the switch for all remote use: Bluetooth and
local-network discovery, sessions with the phone, and the phone's identity
(`RemoteUseSwitch`, `RemoteUseButton`; hierarchy specification §5.2). The
switch is the pairing: it is on while the Mac holds an active pairing, and
turning it off forgets the phone. A click turns it on or off. VoiceOver
reads it as a toggle.

- **Off.** Nothing remote runs, for any reason: no Bonjour browse, no
  Bluetooth scan, no dial, and no phone identity. The app asks macOS for no
  local-network or Bluetooth permission. An operation that the token
  extension hands over is refused. The identity line speaks of this Mac's
  reader only.
- **Turning on.** Turning on is when macOS asks for the permissions. A
  Bluetooth manager asks for Bluetooth. A Bonjour browse asks for the
  local network and runs until macOS allows it. With no phone paired, the
  pairing prompt shows, beside a card reader or not, and the Mac browses
  for phones in pairing mode only while a code is tried. With a pairing,
  the phone's line returns.
- **Turning off.** The click forgets every pairing (RAPP v26.10.22 §4.6
  item 6). The Mac stores the click first, with the pairings it holds
  (`RemoteUseForgetting`). An open session closes with `pairing_revoked`,
  and the Mac waits at most 1 second for that close to leave; then those
  pairings are destroyed with their keys, each name goes once its key is
  gone, and the same-account records of exactly those pairings' phones
  leave the account's directory: a phone paired only with another
  computer stays. What the keychain or the directory does not let go
  stays under the stored click, which turning on again and the next
  launch finish first; while they cannot, remote use stays off. A second
  click off while the first is still forgetting runs after it, and a
  quit waits for both. A connection still being made closes without a
  notice. A phone with no session open is told nothing and forgets this
  computer by its own idle expiry. The phone's identity is withdrawn at
  once, without its grace, and scanning stops. The click asks for no
  confirmation. Turning remote use on again asks for a new pairing code.
- **The last pairing ends.** When the phone forgets this computer
  (`pairing_revoked`) or the pairing expires after 30 days without a
  session, remote use turns off.
- **Quitting.** Quitting while remote use is on withdraws
  (`QuitWithdrawal`): the session closes with `service_withdrawn` and the
  pairing is kept. The app exits once the close has left, written to the
  stream or acknowledged over Bluetooth, or after 1 second, whichever
  comes first. A quit while a click off is still forgetting waits until
  its pairings are destroyed. Quitting with remote use off and nothing
  being forgotten exits at once.
- **Launch.** Every launch, a start at login included, first finishes a
  click off that did not finish, then expires the pairings that had no
  session for 30 days, then restores remote use on while an active
  pairing remains and off otherwise. It decides once the readers are
  looked at, or after 3 seconds without an answer from them, as if no
  card were in one: a card in this Mac's reader starts remote use
  suspended, and a card seen later suspends it then.
  A launch that restores it on asks for no permission. Sleep leaves
  remote use as it was.

A card in this Mac's own reader suspends remote use while it is there
(see below).

The button's symbol shows the state:

| State | Symbol | Color |
|---|---|---|
| Off | `key.radiowaves.forward.slash` | secondary |
| On, no session with the phone | `key.radiowaves.forward` | secondary |
| On, a session with the phone open | `key.radiowaves.forward` | green |
| On, blocked: this Mac's Bluetooth is off or not allowed, or the local network is not allowed | `key.radiowaves.forward` | orange |
| A card in this Mac's reader | `key.2.on.ring`, one key for each PIN | secondary |

While a card is in this Mac's reader the button opens the PIN codes window
instead, under the name "PIN Codes", and the two keys tell the holder
the card is here. When the card leaves, the button is the switch again,
as it was before the card came.

An open session shows as connected even while something else is blocked.
The tooltip and the VoiceOver label say "Remote Access". The tooltip and the
accessibility value name the state: "Off", "On", "Phone connected",
or "Blocked:" followed by the cause. Words name each state,
so no state rests on color alone. The identity line also says whether the
phone serves the card. The slash means off, so the symbol changes only
when the switch is turned on or off, with the Magic Replace transition;
every other change is a change of colour.

## The identity line

`IdentityLine.derive` picks the line from the requester's facts
(`RequesterFacts`). `IdentityStateView` draws it.

| State | Line |
|---|---|
| Remote use off, no reader here | "Connect a card reader." |
| Remote use off, empty reader here | "Insert the card into the reader." |
| Remote use on, no card here, no phone paired | "Open RefineID remote access on your phone and enter the pairing code:" and the six-box code entry |
| Remote use turned on again after the phone forgot this computer | "*phone* forgot this computer" above the pairing prompt |
| Card in this Mac's reader, name not read yet | "Reading information…" |
| Card in this Mac's reader | *HOLDER NAME* |
| Card in this Mac's reader, not ready after a while | the re-insert warning |
| Paired phone, no identity from it yet | "Connecting to the phone…" |
| Paired phone, its identity offered | "*HOLDER NAME* (via phone)" |
| Paired phone, its card reader empty | "Insert the card into the phone's card reader." |
| Remote use on, macOS denies the local network, no phone paired or none offering an identity | "macOS is blocking RefineID from the local network. Allow it in System Settings › Privacy & Security › Local Network." in red, with an "Open Settings" button |

The local-network denial shows as soon as the switch's browse or one dial
to a phone is refused, not after a search times out. "Open Settings" opens
System Settings at Privacy & Security; when the app is active again it
asks afresh and redials, so the line clears itself with no retry control.

A card inserted into this Mac's reader shows "Reading information…" in the
secondary text color until its token is published and the holder's name
is read, which takes a second or two.

A paired phone's line takes the first of these that holds:

1. The phone reports no card in the card reader attached to it (RAPP
   v26.10.22 §8.4 item 6): "Insert the card into the phone's card
   reader.", even while its identity is still offered in its grace.
2. The phone's identity is offered: the holder's line. A phone without a
   card reader reporting no card leaves it standing.
3. Otherwise: "Connecting to the phone…".

An empty reader on this Mac leaves a paired phone's line as it is. Until
the holder's name is read, the holder's line says "Connecting to the
phone…". Only the holder's name is in the primary text color; the rest
of a paired phone's line is secondary.

A paired phone's line names no phone. In "*phone* forgot this
computer" and in the paired list, the phone is named by the
`display_name` its pairing hello sent.

A paired phone's line carries no control: the remote-use switch is the
only control that forgets the phone.

A Mac pairs one phone. The pairing prompt shows only while remote use is
on and no phone is paired. The phone rows of the table above need remote
use on.

## The PIN codes window

`PinCodesWindow` holds `CardManagementView` for the card in this Mac's
reader: the attempts left, and changing or resetting PIN 1 and PIN 2. Only
the toolbar button opens it, while it shows the two keys. It has no
Window menu item, never opens at launch, and is not restored. It closes when the card leaves the reader.

The "Attempts left:" row along the foot of the window lists only the
counters below full. While PIN 1, PIN 2 and the PUK are all full, the
row is not shown.

## A local card suspends remote use

A card in this Mac's own reader suspends remote use while it is there, so
the Mac neither holds nor dials its session with the paired phone
(hierarchy specification §5.2):

- `CardPresence` reports the card to `PersistentTokenRegistry`. The
  registry withdraws (RAPP v26.10.22 §4.5 item 8): it closes the session
  with `service_withdrawn`, withdraws the phone's published identity, and
  stops browsing for the phone.
- `RequesterTransportPolicy` leaves nothing to dial, so no dial, redial or
  Bluetooth scan starts.
- A pairing search under way ends, and the typed code is dropped.
- An operation the token extension hands over is refused.
- Document signing uses the local card.
- The identity line shows only the local card.

The switch and the pairing stay as they are; the switch's Bluetooth and
local-network watches stop while the card is there. A launch with a card
in the reader starts this way. When the card leaves, remote use resumes
as it was: with a pairing, the Mac finds and dials the phone again
without a code; with none, the pairing prompt returns.

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
