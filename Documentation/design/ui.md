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
  prose above it does not. That never leaves a state blank: a row value
  states its state in explicit words ("None", "Unproven"), never a
  blank or a dash.
- **No confirmation dialogs.** A chosen action happens. "Are you sure?" is
  not asked. The one exception is the save panel after signing on the
  Mac, whose Cancel asks keep-or-throw-away (macos.md).
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
  `readsUserAssignedDeviceName` in `RappLocalName` (CardCore) turns on and the
  name the owner gave the device is sent instead. The name is sent again
  on every session, so a renamed device reaches its peer with its next
  session, and a name over 256 bytes is shortened at a character
  boundary.
- **Finnish vocabulary.** Pairing is *yhdistäminen*, and its code is the
  *yhdistämiskoodi*. *Paritus*, *pariliitos* and *laitepari* are not used.
  Revocation-list evidence is labelled *sulkulista*; a revoked state is
  *mitätöity* and its time the *mitätöintiaika*.
  Verifying a document is *tarkastaa* ("Tarkasta…", "Tarkastetaan",
  *tarkastus*); *todentaa* is kept for authentication. The trusted lists
  take the eIDAS term (Regulation (EU) No 910/2014 Article 22):
  *EU:n luotetut luettelot*, in Swedish *EU:s förteckningar över
  betrodda tjänsteleverantörer*, in English *EU trusted lists*.
- **PIN names.** The codes take DVV's names: the basic PIN is PIN 1
  and the signature PIN is PIN 2. Every user-facing name of a PIN, in
  a field label, a heading, a button or a message, is the full name
  with its number and no parentheses, in one vocabulary across every
  RefineID app: "Basic PIN 1" and "Signature PIN 2", so "Current Basic
  PIN 1", "New Basic PIN 1", "Basic PIN 1 again", "Change Basic PIN 1",
  "Reset Signature PIN 2", "Enter Basic PIN 1". The number is always
  written with a space. Finnish takes DVV's own words (dvv.fi,
  PIN-tunnuslukujen hallinta), *perustunnusluku 1* and
  *allekirjoitustunnusluku 2*, capitalised only at the start of a
  label: "Nykyinen perustunnusluku 1", "Uusi perustunnusluku 1",
  "Perustunnusluku 1 uudelleen", "Vaihda perustunnusluku 1", "Syötä
  perustunnusluku 1". Swedish takes *grund PIN 1*, the preferred term
  of the Finnish public-sector Certification vocabulary
  (sanastot.suomi.fi, concept "basic PIN"), and DVV's *signaturkod 2*
  (dvv.fi/sv, hantering av PIN-koder): "Nuvarande grund PIN 1", "Ny
  grund PIN 1", "Grund PIN 1 igen", "Byt grund PIN 1", "Ange grund
  PIN 1". The reasons: they are the issuer's own words; Kielitoimisto
  needs no compound hyphen when the full word is written out, so the
  number simply follows the name; and a number in parentheses reads
  badly in a field label. Not used: "PIN 1 (basic)", "Basic PIN
  (PIN 1)", "Signing PIN", "Perus-PIN", "grundkod", "grundläggande
  kod", "Bas-PIN", a bare "PIN 1" or "PIN 2" in prose of any language,
  and any number in parentheses. The full name goes into every sentence
  a holder reads too: status lines ("Basic PIN 1 changed."), attempt
  counters, confirmations ("Confirm Basic PIN 1 change?"), refusals and
  help text, declined in Finnish as the sentence needs
  ("perustunnusluvun 1 vaihto", "allekirjoitustunnuslukua 2 ei asetettu").
  The PUK is "PUK" in every language.
  The activation form, titled "Identity card activation" ("Organisation
  card activation" for an organization card), has three
  groups, headed "Activation PIN", "Basic PIN 1" and "Signature PIN 2"
  (Finnish "Perustunnusluku 1"), so a filled field still says what
  it holds. "Basic PIN 1" (Finnish "Perustunnusluku 1", Swedish "Grund PIN 1")
  and "Signature PIN 2" ("Allekirjoitustunnusluku 2", "Signaturkod 2") are
  also the credential names the PIN prompts take and the token label
  Safari and the system show, without parentheses, as refineid-core's
  PKCS#11 module writes them.
- **Activation PIN.** The credential in DVV's activation letter takes
  DVV's official name from the letters: "Activation PIN", Finnish
  *aktivointitunnusluku*, Swedish *aktiveringskod* (definite
  *aktiveringskoden*). The one name covers both activation schemes,
  the one where the letter's code is the PUK and the one where both
  PINs ship preset to it; "activation code" is not used.
- **Both PINs blocked.** When PIN 1 and PIN 2 are both blocked and the
  PUK is not at one or two tries, card management offers one form in place
  of "Reset Basic PIN 1" and "Reset Signature PIN 2": groups headed
  "PUK", "Basic PIN 1" and "Signature PIN 2", laid out as the
  activation form, and a "Reset" button. It resets PIN 1, then PIN 2 only if PIN 1 was reset, with the
  one PUK entry, on any card that does not await activation.
- **At no tries left the command goes to the card.** One rule holds for
  PIN 1, PIN 2, the PUK and the activation PIN: a command that could
  spend a try is refused at two or one tries left and at an unreadable
  counter, and a PUK reported verified reads as unreadable. A reading of
  none left or blocked goes through: the card answers for itself and
  spends nothing, and the software cannot know which code the holder has
  in hand, so it must not close a recovery the card would allow. The
  card's answer reaches the holder as blocked, with the PUK as the way
  back. The counter row may read a credential as blocked before any
  prompt, as information, since that reading sends no credential; no
  button is disabled by it. A button that is off while every entry is valid
  says why beside it, in the words the refusal itself uses.
- **Development builds show errors.** Every failure path reports to
  `DevErrorLog`: the Errors window on the Mac, the error pill and the
  Diagnostics screen on iPhone and iPad. TestFlight and Release builds
  compile none of it (AGENTS.md, Rule #5).
