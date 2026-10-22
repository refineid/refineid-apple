# UI principles

The rules every RefineID screen follows, on the Mac, iPhone and iPad.

- **Result and errors only.** The happy path shows the result, such as the
  holder's name or a signed document, and the errors. It shows no transient
  status on the way.
- **No explainer text.** No caption restates what is already visible: a name
  stands without a "Henkilö" caption before it. Controls carry no standards
  acronyms. A control's accessibility label names it for VoiceOver; a line of
  prose above it does not.
- **No confirmation dialogs.** A chosen action happens. "Are you sure?" is
  not asked.
- **No recovery buttons.** No "paused" state waits for a "resume". Back-offs
  stay silent and clear themselves.
- **Six-box code entry.** A pairing code and a card access number are typed
  into the six-box field (`CodeBoxesField`), never into a plain text field.
  The field has a VoiceOver label.
- **Finnish vocabulary.** Pairing is *yhdistäminen*, and its code is the
  *yhdistämiskoodi*. *Paritus*, *pariliitos* and *laitepari* are not used.
- **Development builds show errors.** Every failure path reports to
  `DevErrorLog`: the Errors window on the Mac, the error pill and the
  Diagnostics screen on iPhone and iPad. TestFlight and Release builds
  compile none of it (AGENTS.md, Rule #5).
