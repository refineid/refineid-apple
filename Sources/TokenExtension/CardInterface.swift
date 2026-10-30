// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// How the card this token was made from is reached.
///
/// Two of these are contactless, and the difference between them decides
/// how a signature may be taken. A card on a reader's antenna sits in a
/// field the reader holds for as long as it likes, so a signature there
/// can afford everything the contact path does: read the serial, read
/// the counters, and reuse a card-bound PIN. A card held against a phone
/// does not have that: the system owns the slot, ends it about two
/// seconds after the mint, and every read spends field the signature
/// still needs -- so that path asks for the PIN before touching the card
/// and reads nothing it was not given.
///
/// Telling them apart by slot name was tried and is wrong: a reader
/// names its interfaces by a trailing index and never says which is the
/// antenna. This is recorded at the mint instead, by the code that
/// already knows which of the two ways it made the token.
internal enum CardInterface: Sendable {
  /// In a contact slot, speaking in the clear.
  case contact

  /// Held against the phone's own antenna, on the system's clock.
  case fieldWithDeadline

  /// On a reader's antenna, in a field that is not going anywhere.
  case steadyField

  /// Whether PIN 1 held for the card outlives the token.
  ///
  /// The phone's field ends seconds after each mint and the system mints
  /// a new token for the next field, so the held value stays with the
  /// card. A reader keeps its token while the card stays, so the value
  /// leaves with the token.
  internal var keepsPin1BeyondToken: Bool {
    self == .fieldWithDeadline
  }
}
