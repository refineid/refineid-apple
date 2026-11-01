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
form, and the window has no toolbar button while it does: activation is
the one thing to do with the card, in this window only. A contactless card that needs its access number replaces them with
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
- **Turning off.** The click forgets every pairing (RAPP v26.10.29 §4.6
  item 6). The Mac stores the click first, with the pairings it holds
  (`RemoteUseForgetting`). An open session closes with `pairing_revoked`,
  and the Mac waits at most 1 second for that close to leave; then those
  pairings are destroyed with their keys, and each name goes once its key
  is gone. What the keychain does not let go stays under the stored
  click, which turning on again and the next launch finish first; while
  they cannot, remote use stays off. A second click off while the first
  is still forgetting runs after it, and a quit waits for both. A
  connection still being made closes without a notice. A phone with no
  session open is told nothing and forgets this computer by its own idle
  expiry. The phone's identity is withdrawn at once, without its grace,
  and scanning stops. The click asks for no confirmation. Turning remote
  use on again asks for a new pairing code.
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
| Card in this Mac's reader, no token for it after a while | "Remove the card from the reader for a moment." in orange |
| Paired phone, no identity from it yet | "Connecting to the phone…" |
| Paired phone, its identity offered | "*HOLDER NAME* (via phone)" |
| Paired phone, its card reader empty | "Insert the card into the phone's card reader." |
| Remote use on, macOS denies the local network, no phone paired or none offering an identity | "macOS is blocking RefineID from the local network. Allow it in System Settings › Privacy & Security › Local Network." in red, with an "Open Settings" button |
| Pairing found a phone and could not reach it for another reason | "Could not connect to the phone. Check that the phone and this Mac are on the same network and that RefineID is allowed to use the local network." in red, with an "Open Settings" button |

The local-network denial shows as soon as the switch's browse, one dial
to a phone, or the address check beside a dial is refused, not after a
search times out. A dial to a phone's published service does not report
the denial itself, so the dialer also resolves the service and checks its
addresses. "Open Settings" opens
System Settings at Privacy & Security; when the app is active again it
asks afresh and redials, so the line clears itself with no retry control.

A card inserted into this Mac's reader shows "Reading information…" in the
secondary text color until its token is published and the holder's name
is read, which takes a second or two.

A paired phone's line takes the first of these that holds:

1. The phone reports no card in the card reader attached to it (RAPP
   v26.10.29 §8.4 item 6): "Insert the card into the phone's card
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
reader: the attempts left, and changing or resetting PIN 1 and PIN 2. The
toolbar button opens it, while it shows the two keys, and it opens by
itself, once per insertion, when the card's reading says a code is below
the retry floor; a card already in the reader at launch counts as inserted
then. It has no Window menu item, opens at launch only for such a card,
and is not restored. It closes when the card leaves the reader, and
when the card turns out to await activation.

While a code is below the floor, the two keys in the toolbar are red and
the window's top section says why the card cannot be used and the way
back: "RefineID does not use PIN 1 with fewer than 3 attempts left." and
"Reset PIN 1 with the PUK, or use other software." (the same for PIN
2). A PUK below the floor keeps the "use other software" text, since the
PUK cannot be reset here. At four or three tries left nothing is coloured
and nothing opens: the footer row shows the count.

The "Attempts left:" row along the foot of the window lists only the
counters below full. While PIN 1, PIN 2 and the PUK are all full, the
row is not shown.

## The PIN sheet after a refusal

The system's PIN sheet is the only place a Safari login talks to the
holder, so every refusal by the token extension is reported to the system
as a failed authentication, and the sheet comes back: a wrong PIN, a PIN
the card refused before, the retry floor at two tries left, and a blocked
PIN alike. The returning sheet is the holder's sign that nothing was
accepted. A refusal is never reported as a cancellation, which would end
the login quietly as if the holder had pressed Cancel.

A refused PIN forgets the PINs the token holds and nothing else: the token
stays live, so the returning sheet reaches a card that can still answer.
CryptoTokenKit mints a reader card once per insertion, so a token ended on
a refusal would leave the card in the reader with nothing to sign until it
was pulled out and put back. Only a PACE failure, which proves the stored
card access number cannot open the card, ends the token.

## A local card suspends remote use

A card in this Mac's own reader suspends remote use while it is there, so
the Mac neither holds nor dials its session with the paired phone
(hierarchy specification §5.2):

- `CardPresence` reports the card to `PersistentTokenRegistry`. The
  registry withdraws (RAPP v26.10.29 §4.5 item 8): it closes the session
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

Signing comes first and the save panel after. The holder presses Sign,
the card or the phone signs, and the signed file is built in memory; only
then does the save panel open, as a sheet on the window, with the prompt
Save and the final name in the field. A pile of PDFs asks for its folder
once, after every document is signed.

The signed file stays in memory until it is written or the holder forgets
it. Cancelling the panel raises one alert, "The signed file has not been
saved." ("The signed files have not been saved." for a pile), with no
message: "Save the file" ("Save the files") is the default and opens the
panel again with the name last typed, and "Forget the signature" ("Forget
the signatures") drops it. Dismissing the alert without an answer counts
as the default. A place that is one of the originals, matched through
symbolic links and in either letter case, shows "The signed document
cannot replace the original." and the panel opens again; so does a write
that fails, with its error. In a pile, a file already in the chosen folder
is never overwritten: that document is reported as not saved and the
rest are written.

A signed file is named by its best signature time
(ETSI EN 319 102-1 clause 5.5): the generation time of
the signature timestamp taken while signing, never a document timestamp
taken later. A signature with no timestamp, such as the virtual card's,
is named by the clock. The name is the original's stem, or "portfolio"
for a container over several files, then " - ", the word "signed" in the
app's language, a space, and that instant in UTC with colons replaced by
hyphens. A container name the holder types keeps the suffix when it is
still there and gets it appended when typing replaced it.

## Web signing (SCS)

The Signature Creation Service is a loopback HTTPS server that web pages
sign through. It is planned and stays in the code behind `FEATURE_SCS`,
which no build configuration sets until it ships. It is not dead code:
cleanups keep the server, its card backend, its transaction manager, its
opt-in and their tests.

When it ships it is a setting the holder turns on. The server starts only
after that opt-in, so the certificate trust prompt it needs appears when
the holder first turns it on. A launch with the opt-in stored starts the
server again.

It implements the DVV specification
[`dvv_scs_v1_3`](../references.md#dvv_scs_v1_3). Chapter 2 is normative;
chapter 3 is advice.

| Section | Requirement | The server |
| --- | --- | --- |
| §2.1 | A certificate selection dialog on every signature request; the holder is shown the request's Origin. | Shows a PIN prompt on every request that reaches signing, naming the Origin and the digest. It has no certificate selection step: the request's purpose picks the certificate. |
| §3.5 | Never sign silently. | Every request that reaches signing asks for the PIN; one the card's retry floor refuses ends without a prompt. A remembered PIN 1 is never used. |
| §3.7 | Show the signed content where possible; signing unseen content is allowed. | Shows the digest, never the content. |
| §3.10 | Any local application can send requests; an authorization token with a cookie is suggested, not required. | Serves one request at a time, so one prompt is on screen. No authorization token. |

## Development builds

Every failure path reports to `DevErrorLog`. The Errors window is a
floating panel. It opens by itself when an error arrives, without taking
focus, and the Window menu opens it too. The Diagnostics window exists only
in development builds as well. TestFlight and Release builds have neither.
