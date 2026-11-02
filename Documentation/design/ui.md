# UI principles

The rules every RefineID screen follows, on the Mac, iPhone and iPad.

- **Result and errors only.** The happy path shows the result, such as the
  holder's name or a signed document, and the errors. It shows no transient
  status on the way.
- **Decide before drawing.** A view that depends on what the card is (its
  kind, activation scheme or counters) appears only once that is known. It
  never draws a default and corrects itself afterwards; until the answer is
  in, the screen keeps the state it was already showing.
- **No explainer text.** No caption restates what is already visible: a name
  stands without a "Person" caption before it. Controls carry no standards
  acronyms. A control's accessibility label names it for VoiceOver; a line of
  prose above it does not.
- **No confirmation dialogs.** A chosen action happens. "Are you sure?" is
  not asked.
- **No recovery buttons.** No "paused" state waits for a "resume". Back-offs
  stay silent and clear themselves.
- **Red and orange mean errors.** Only an error takes red or orange. Normal
  states, off among them, never do: they take the secondary text color, or
  green for a working connection. Color never carries meaning that the
  screen does not also state in text or shape, such as a line of text, a
  tooltip, an accessibility value or a different symbol. On iPhone and
  iPad, a removal button takes the platform's destructive red, as iOS
  lists do: it is a control, not a state.
- **The eye shows the state.** A secret field's eye is closed while the
  digits are hidden, which is how every field starts, and open while they
  show. Clicking it opens or closes it.
- **Sentences end with a period.** An instruction or message shown as a
  full sentence ends with a period in every language, for example "Take
  the card off the reader.". Buttons, menu items, titles, headers, field
  labels, row values and accessibility labels do not.
- **Six-box code entry.** A pairing code, and on the Mac a personal
  card's card access number, are typed into the six-box field
  (`CodeBoxesField`), never into a plain text field. The field has a
  VoiceOver label.
- **The iPhone's card access number entry.** The setup entry "Card
  Access Number (CAN)" is one hidden field of four to twelve digits with
  the eye, then the camera. The card on the antenna decides on the tap
  what the digits are: a personal card's access number, which must be
  six digits, or an organization card's PIN 1. Until then the value is a
  secret; an organization card's never becomes a card access number and
  is never stored or shown as one.
- **Device names.** A device introduces itself in a pairing by the name
  every peer then shows. A computer names its system and its host name,
  "macOS - Mac mini". A phone or a tablet names only itself, "iPhone 15
  Pro Max", since the device already says which system it runs. Until
  Apple grants the user-assigned device name entitlement, iOS reports
  every phone as "iPhone", so an iPhone or iPad sends its model name from
  the table `Scripts/generate-device-models.sh` writes, or "iPhone" or
  "iPad" for a model the table lacks. Once the entitlement is in
  `Config/RefineID-iOS.entitlements`, the one switch
  `readsUserAssignedDeviceName` in `RappPairingModel` turns on and the
  name the owner gave the device is sent instead.
- **Finnish vocabulary.** Pairing is *yhdistäminen*, and its code is the
  *yhdistämiskoodi*. *Paritus*, *pariliitos* and *laitepari* are not used.
- **PIN names.** The codes take DVV's names: the basic PIN (*perus*,
  *grund*) is PIN 1 and the signature PIN (*allekirjoitus*, *signatur*)
  is PIN 2. The number is always written with a space, "PIN 1". In every
  form, the field for a new code names it in full, "New basic PIN 1",
  and the field that repeats it is "Repeat PIN 1". Where the language's
  word is not "PIN", the number follows in brackets: "Uusi
  perustunnusluku (PIN 1)", "Ny grundkod (PIN 1)".
  The activation form, titled "Identity card activation" ("Organisation
  card activation" for an organization card), has three
  groups, headed "Activation PIN", "Basic PIN 1" and "Signature PIN 2"
  (Finnish "Perustunnusluku (PIN 1)"), so a filled field still says what
  it holds.
- **Activation PIN.** The credential in DVV's activation letter takes
  DVV's official name from the letters: "Activation PIN", Finnish
  *aktivointitunnusluku*, Swedish *aktiveringskod* (definite
  *aktiveringskoden*). The one name covers both activation schemes,
  the one where the letter's code is the PUK and the one where both
  PINs ship preset to it; "activation code" is not used.
- **Both PINs blocked.** When PIN 1 and PIN 2 are both blocked and the
  PUK is above the retry floor, card management offers one form in place
  of "Reset PIN 1" and "Reset PIN 2": groups headed "PUK", "Basic PIN 1"
  and "Signature PIN 2", laid out as the activation form, and a "Reset"
  button. It resets PIN 1, then PIN 2 only if PIN 1 was reset, with the
  one PUK entry, on any card that does not await activation.
- **Development builds show errors.** Every failure path reports to
  `DevErrorLog`: the Errors window on the Mac, the error pill and the
  Diagnostics screen on iPhone and iPad. TestFlight and Release builds
  compile none of it (AGENTS.md, Rule #5).
