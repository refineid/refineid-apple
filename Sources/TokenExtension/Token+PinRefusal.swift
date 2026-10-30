// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore

/// What a refused or blocked PIN ends: the PINs this token holds, and
/// nothing else.
extension Token {
  /// Forgets a PIN the card refused, and keeps the token.
  ///
  /// The refused value is remembered so it is never sent again, and every
  /// held PIN of this token goes; the token itself stays live, so the
  /// system's next prompt reaches a card that can still answer, and the
  /// retry floor decides from the counter whether an attempt may be sent
  /// at all. The stored identity stays, because a PIN is never stored and
  /// the card has not left (RAPP v26.10.29 section 8.4 item 1, section 11
  /// item 2). Transport loss, PACE failure, malformed signatures and TLS
  /// errors do not come here; only the card's VERIFY response does.
  internal func forgetPinAfterRefusal(fingerprint: PinFingerprint) {
    CredentialMemory.rejectedPins.recordRejection(fingerprint)
    Pin1Memory.shared.clear(serial: chipSerial)
  }
}
