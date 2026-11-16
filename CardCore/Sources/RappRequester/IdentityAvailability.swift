// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

/// What the login identity layer knows about the card it can offer.
///
/// The token listing is the source: a card arriving or leaving moves it
/// without polling or anyone pressing refresh.
public enum IdentityAvailability: Equatable, Sendable {
  /// A card is in the reader but no identity is offered from it - the state
  /// after a driver update, until the card is seen again.
  case cardWithoutIdentity

  /// No card in any reader.
  case noCard

  /// An identity is published and can be offered.
  case ready
}
