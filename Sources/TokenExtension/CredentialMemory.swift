// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore

/// Process-lifetime credential memory shared across token sessions.
///
/// A PIN the card rejected must not be resent for the extension's
/// lifetime, and token sessions come and go across card reinserts, so
/// this state lives at process scope (release plan section 4.3). It
/// holds only non-reversible fingerprints, never a PIN, each bound to the
/// card's ``ChipSerial``. PIN 1 itself is held in ``Pin1Memory``.
internal enum CredentialMemory {
  internal static let rejectedPins = RejectedPinMemory()
}
