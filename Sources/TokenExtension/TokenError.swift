// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoTokenKit
import Foundation

/// Typed failures inside the token extension, each mapped to the
/// CryptoTokenKit error the system expects.
internal enum TokenError: Error {
  /// No usable PIN yet (none entered, no valid cache): the system must
  /// present the PIN sheet and retry.
  case activationRequired
  case authenticationRequired

  /// The leaf certificate DER did not construct a `SecCertificate`.
  case certificateUnreadable

  /// The system rejected construction of a keychain item.
  case keychainItemConstructionFailed

  /// The entered PIN was already rejected by this card; not resent.
  case pinAlreadyRejected

  /// The collected PIN is not a valid PIN1 (length or characters).
  case pinFormatInvalid

  /// The card rejected the PIN during VERIFY.
  case pinRejected

  /// This card has no primed identity, so a contactless token cannot be
  /// minted: the contactless interface seals the card until PACE has run,
  /// and the app has not yet stored what PACE needs.
  case primeMissing

  /// The card's raw signature could not be re-encoded.
  case signatureMalformed

  /// Signing was refused: the retry floor, a blocked PIN, unreadable
  /// state, or a rejected signing command. Surfaces as an authentication
  /// failure, so the system asks again; the returning sheet is the
  /// holder's sign that nothing was accepted.
  case signRefused

  /// The stored number was just refused by this card; not retrying yet.
  case unsealAlreadyRefused

  /// The leaf's key is not one of the supported profiles.
  case unsupportedKeyProfile

  /// The system error to surface to CryptoTokenKit.
  internal var asTKError: TKError {
    switch self {
    case .authenticationRequired:
      TKError(.authenticationNeeded)

    case .keychainItemConstructionFailed:
      TKError(.corruptedData)

    case .certificateUnreadable, .signatureMalformed:
      TKError(.corruptedData)

    case .pinAlreadyRejected, .pinFormatInvalid, .pinRejected, .signRefused:
      TKError(.authenticationFailed)

    case .activationRequired, .primeMissing, .unsealAlreadyRefused,
      .unsupportedKeyProfile:
      // Not this driver's card. Refusal is safe: the system treats the
      // card as unhandled rather than as broken.
      TKError(.tokenNotFound)
    }
  }
}
