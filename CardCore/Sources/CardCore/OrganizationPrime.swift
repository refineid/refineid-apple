// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What the token driver read from an organization card in a contact
/// slot, kept so the card can publish its identity on a reader's antenna.
///
/// An organization card on the contactless interface answers nothing but
/// EF.CardAccess until PACE has run, and its PACE password is PIN 1 or
/// PIN 2: no certificate can be read there before the holder types a PIN.
/// The same card read in a contact slot answers in the clear, so the
/// driver keeps what it read there -- the certificates and the chip
/// serial, all public and unchanging -- and the antenna mint publishes
/// the identity from this record with no card I/O and no PIN. The PIN
/// is asked when a signature needs it, and the PACE it opens is checked
/// against ``chipSerial`` before anything is signed.
///
/// Nothing here is secret, and nothing here logs.
public struct OrganizationPrime: Codable, Equatable, Sendable {
  /// The DER authentication certificate.
  public let certificateDER: Data

  /// The DER issuing-CA certificate, when the card offered one.
  public let issuerDER: Data?

  /// The DER qualified-signature certificate, when the card has one.
  public let signatureCertificateDER: Data?

  /// The card's chip serial.
  public let chipSerial: ChipSerial

  /// Refuses a record without an authentication certificate.
  public init?(
    certificate: Data,
    issuer: Data?,
    signatureCertificate: Data?,
    chipSerial: ChipSerial
  ) {
    guard !certificate.isEmpty else { return nil }
    self.certificateDER = certificate
    self.issuerDER = issuer
    self.signatureCertificateDER = signatureCertificate
    self.chipSerial = chipSerial
  }
}
