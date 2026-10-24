// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore

/// A PIN 1 resolved before the field opens, with its origin.
///
/// The origin decides what a non-pristine counter means once the card
/// answers the probe: a reused value is dropped and the holder asked, a
/// typed one is tested against the card under the retry floor.
internal struct AuthorizedPin1: ~Copyable {
  /// Where a PIN 1 about to be spent in the field came from.
  internal enum Origin: Sendable {
    /// Reused from the memory of a PIN this card accepted earlier.
    case acceptedMemory

    /// Typed by the holder and staged before the field opened.
    case candidate

    /// Typed by the holder for this very signature.
    case prompt
  }

  internal let pin1: Pin1
  internal let origin: Origin

  internal init(pin1: consuming Pin1, origin: Origin) {
    self.pin1 = pin1
    self.origin = origin
  }
}
