// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CardCore
import Foundation

/// The certificate material read from a card for publication: the
/// authentication leaf (required) and the issuing-CA certificate
/// (best-effort - absent on cards that do not carry EF.4336).
internal struct PublishedIdentity {
  /// DER of the authentication leaf certificate.
  internal let leafDER: Data

  /// DER of the issuing-CA certificate, when the card provides it.
  internal let issuerDER: Data?

  /// DER of the qualified-signature leaf (EF.4332), when present.
  ///
  /// Read when the card provides the slot and the mint had room to
  /// read it. Contactless primes carry none: the qualified identity is
  /// published from live reader mints only.
  internal let signLeafDER: Data?

  /// Chip serial read from the same card session.
  ///
  /// The public token identifier is derived from its printed form; the
  /// complete value remains the card-bound security identity.
  internal let chipSerial: ChipSerial
}
