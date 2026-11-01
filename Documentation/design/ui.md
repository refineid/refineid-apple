# UI principles

The rules every RefineID screen follows, on the Mac, iPhone and iPad.

- **Result and errors only.** The happy path shows the result, such as the
  holder's name or a signed document, and the errors. It shows no transient
  status on the way.
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
- **Six-box code entry.** A pairing code and a card access number are typed
  into the six-box field (`CodeBoxesField`), never into a plain text field.
  The field has a VoiceOver label.
- **Finnish vocabulary.** Pairing is *yhdistäminen*, and its code is the
  *yhdistämiskoodi*. *Paritus*, *pariliitos* and *laitepari* are not used.
- **PIN names.** The codes take DVV's names: the basic PIN (*perus*,
  *grund*) is PIN 1 and the signature PIN (*allekirjoitus*, *signatur*)
  is PIN 2. The number is always written with a space, "PIN 1". In every
  form, the field for a new code names it in full, "New basic PIN 1",
  and the field that repeats it is "Repeat PIN 1". Where the language's
  word is not "PIN", the number follows in brackets: "Uusi
  perustunnusluku (PIN 1)", "Ny grundkod (PIN 1)".
  The activation form has three groups, headed "Activation PIN",
  "PIN 1" and "PIN 2", so a filled field still says what it holds.
- **Development builds show errors.** Every failure path reports to
  `DevErrorLog`: the Errors window on the Mac, the error pill and the
  Diagnostics screen on iPhone and iPad. TestFlight and Release builds
  compile none of it (AGENTS.md, Rule #5).
