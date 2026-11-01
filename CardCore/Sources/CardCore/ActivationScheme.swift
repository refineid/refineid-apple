// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// How a card is activated, decided by its issuance date
/// (FINEID S4-1 §4.6).
///
/// Cards issued before 13 January 2026 ship with their PINs blocked;
/// the eight-digit activation code in the issuance letter is the PUK,
/// and activation is RESET RETRY COUNTER against each PIN (§4.6.1).
/// Cards issued from that date ship with both PINs set to a
/// single-use seven-digit activation PIN, and activation is CHANGE
/// REFERENCE DATA against each (§4.6.2). The scheme decides which
/// digit count the card accepts - the wrong one burns a retry - so an
/// unclassifiable card refuses activation rather than guessing.
///
/// Neither the chip generation nor the certificate key family tells
/// the schemes apart: a card on the activation-code scheme can be a
/// fifth-generation chip carrying ECC certificates.
public enum ActivationScheme: Equatable, Sendable {
  /// §4.6.1, issued before 13 January 2026: PINs ship blocked, the
  /// activation code is the PUK.
  case activationCodeIsPuk

  /// §4.6.2, issued from 13 January 2026: PINs ship set to the
  /// single-use activation PIN.
  case presetActivationPin

  /// The cutover DVV publishes, as the UTC epoch instant of its
  /// midnight.
  ///
  /// 13 January 2026. X.509 validity is expressed in UTC, so the
  /// comparison is calendar-exact.
  private static let cutoverEpochSeconds: TimeInterval = 1_768_262_400

  /// Common-name marker of DVV's organisational issuing CAs
  /// ("DVV Organisational Certificates - G4R").
  ///
  /// Refused outright: S4-1 §4.6 covers citizen cards alone, and an
  /// organization card's activation is its issuer's own process.
  private static let organisationalIssuerMarker = "Organisational"

  /// The exact digit count the card accepts for the activation entry.
  ///
  /// Eight for an activation code, seven for a preset activation PIN.
  /// The card enforces the length itself and a wrong-length entry
  /// burns a retry, which is why the classification exists at all.
  public var activationEntryDigitCount: Int {
    switch self {
    case .activationCodeIsPuk:
      Puk.maximumDigitCount

    case .presetActivationPin:
      Puk.minimumDigitCount
    }
  }

  /// Classifies by the authentication certificate's notBefore date.
  ///
  /// The authoritative classifier: DVV names the cutover date itself,
  /// so this survives CA renaming. The issuance date is also printed
  /// on the card surface for human verification.
  public static func classify(issuedOn notBefore: Date) -> Self {
    notBefore.timeIntervalSince1970 >= Self.cutoverEpochSeconds
      ? .presetActivationPin
      : .activationCodeIsPuk
  }

  /// Classifies a citizen card from its authentication certificate.
  ///
  /// The validity start is the only generation boundary DVV publishes.
  /// An organizational issuer, or a certificate whose validity start
  /// cannot be read, answers nil and the caller refuses activation.
  public static func classify(authenticationCertificateDER der: Data) -> Self? {
    guard
      let certificate = SecCertificateCreateWithData(nil, der as CFData),
      let facts = CertificateFacts(der: der)
    else {
      return nil
    }
    let issuer = DistinguishedName.commonName(inName: facts.issuerName)
    if issuer?.contains(Self.organisationalIssuerMarker) == true {
      return nil
    }
    return CertificateValidity.window(of: certificate)
      .map { Self.classify(issuedOn: $0.notBefore) }
  }
}
