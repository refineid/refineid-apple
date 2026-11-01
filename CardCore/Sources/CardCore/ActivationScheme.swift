// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// How a card is activated (FINEID S4-1 §4.6).
///
/// Under §4.6.1 the card ships with its PINs blocked; the eight-digit
/// activation code in the issuance letter is the PUK, and activation
/// is RESET RETRY COUNTER against each PIN. Under §4.6.2 the card
/// ships with both PINs set to one seven-digit activation PIN, and
/// activation is CHANGE REFERENCE DATA against each. The scheme decides
/// which digit count and which command the card takes - the wrong one
/// burns a retry - so a card without a scheme is not activated.
///
/// ``ActivationClassification`` decides the scheme for a card: the
/// organization numbering means §4.6.1, and a citizen card's
/// authentication certificate validity start chooses between the two.
/// Neither the chip generation nor the certificate key family tells
/// the schemes apart.
public enum ActivationScheme: CaseIterable, Hashable, Sendable {
  /// §4.6.1: PINs ship blocked, the activation code is the PUK.
  case activationCodeIsPuk

  /// §4.6.2: PINs ship set to the activation PIN.
  case presetActivationPin

  /// Digits in the §4.6.1 activation code from the issuance letter.
  public static let activationCodeDigitCount: Int = 8

  /// Digits in the §4.6.2 preset activation PIN.
  public static let presetActivationPinDigitCount: Int = 7

  /// The cutover DVV publishes, as the UTC epoch instant of its
  /// midnight.
  ///
  /// 13 January 2026. X.509 validity is expressed in UTC, so the
  /// comparison is calendar-exact.
  private static let cutoverEpochSeconds: TimeInterval = 1_768_262_400

  /// The exact digit count the card accepts for the activation entry.
  ///
  /// The card enforces the length itself and a wrong-length entry
  /// burns a retry, which is why the scheme is decided before the
  /// form opens.
  public var activationEntryDigitCount: Int {
    switch self {
    case .activationCodeIsPuk:
      Self.activationCodeDigitCount

    case .presetActivationPin:
      Self.presetActivationPinDigitCount
    }
  }

  /// The citizen scheme for an authentication certificate valid from
  /// `notBefore`: §4.6.2 from 13 January 2026, §4.6.1 before it.
  public static func classify(issuedOn notBefore: Date) -> Self {
    notBefore.timeIntervalSince1970 >= Self.cutoverEpochSeconds
      ? .presetActivationPin
      : .activationCodeIsPuk
  }

  /// The citizen scheme from the authentication certificate's validity
  /// start; nil when the certificate or its validity cannot be read.
  internal static func classify(authenticationCertificateDER der: Data) -> Self? {
    guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
      return nil
    }
    return CertificateValidity.window(of: certificate)
      .map { Self.classify(issuedOn: $0.notBefore) }
  }
}
