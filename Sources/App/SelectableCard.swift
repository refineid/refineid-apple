// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// One card identity the window lists: who holds it and where it is.
internal struct SelectableCard: Equatable, Sendable {
  /// The token identifier CryptoTokenKit publishes the card under, unique
  /// to the card, so a different card in the same slot is a different row.
  internal let tokenID: String

  /// The reader slot the token was minted for.
  internal let slotName: String

  /// The holder line the identity line shows.
  internal let holderLine: String
}
