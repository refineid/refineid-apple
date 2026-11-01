// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore

/// What opens the card behind a token before it answers.
///
/// A contact card answers in the clear. A citizen card on an antenna
/// opens with PACE and the card access number; an organization card on
/// an antenna opens with PACE and the PIN the operation spends, PIN 1 for
/// an authentication and PIN 2 for a qualified signature (FINEID S1 v4.0,
/// organizational cards, section 2.1), so its channel cannot be opened
/// before the PIN is in hand and is opened anew for each signature.
internal enum CardUnsealing: Sendable {
  /// PACE with this card access number.
  case cardAccessNumber(CardAccessNumber)

  /// PACE with the PIN the operation spends.
  case organizationPin

  /// Spoken to directly, in the clear.
  case plain

  /// The card access number, when that is what opens the card.
  internal var accessNumber: CardAccessNumber? {
    guard case .cardAccessNumber(let number) = self else { return nil }
    return number
  }
}
