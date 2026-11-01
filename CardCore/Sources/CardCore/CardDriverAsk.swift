// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// What the token driver learnt a card on the antenna needs before it
/// can be read.
public enum CardDriverAsk: String, Sendable {
  /// The card refused the application until PACE with its card access
  /// number: a personal card.
  case cardAccessNumber = "can"

  /// The card selected the application but refused every read: an
  /// organisation card, whose contactless channel opens only with a PIN
  /// that is not offered here. It is read in the reader's card slot.
  case cardSlot = "slot"
}
