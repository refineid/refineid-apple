// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// What the app learned about one card while priming it, so a later
/// signature does not have to learn it again.
///
/// Except for the CAN described below, the material here is public and
/// unchanging: the certificate the card holds, the chain above it, and
/// the card's own serial. None of it can differ the next time the same
/// card is read, so re-reading it buys nothing -- and it is not free. On
/// the contactless path the read costs hundreds of milliseconds of
/// secure-messaged APDUs at exactly the moment the field is shortest:
/// `ctkd` owns the slot and ends the session about two seconds after the
/// token is minted, and that read was measured dying part way through. A
/// signature that spends its field time re-reading a certificate it
/// already has is a login lost for nothing.
///
/// The card access number is the one value here that is not public. It is
/// carried as digits rather than as a `CardAccessNumber` because this
/// record is written to and read from the keychain, and the domain type
/// is deliberately not `Codable`; the digits are validated through that
/// type on the way in and on the way out, and they appear in no log line,
/// no description, and no error message.
///
/// Provenance: `PrimedIdentity` in the donor
/// `platform/apple/RefineIDTokenExtension/PrimeStore.swift` and its
/// hand-kept mirror `PrimedIdentityRecord` in
/// `platform/apple/RefineID/Local/SafariIdentityPrime+PrimeStore.swift`.
/// The two copies had to be kept in sync by review; this one record lives
/// in the module the app and the extension both link.
public struct PrimedIdentity: Codable, Equatable, Sendable {
  /// Proof carried only by a prime whose live-card activation check passed.
  ///
  /// The single case makes unchecked and legacy records fail decoding
  /// instead of silently becoming eligible for token publication.
  public enum ActivationCheck: String, Codable, Equatable, Sendable {
    case passed = "passed"
  }

  /// Six digits from the front of the card.
  ///
  /// Never logged, never displayed, never included in an error.
  public let can: String

  /// The DER authentication certificate read from the card while priming.
  public let certDER: Data

  /// The DER issuing-CA certificate, when the prime read one.
  public let issuerDER: Data?

  /// The card's chip serial.
  public let chipSerial: ChipSerial

  /// Proof that no PIN awaiting activation blocked this prime.
  public let activationCheck: ActivationCheck

  /// The DER signature certificate read from the card, when cached.
  public let signatureCertDER: Data?

  /// Refuses anything that could not have come from a real prime.
  ///
  /// The card access number must be six digits and the certificate must
  /// carry bytes.
  /// This is the only way to construct the record, so every reader has
  /// evidence the check happened -- including the reader that decoded it
  /// from the keychain, which reconstructs it through this initializer
  /// rather than trusting what was stored.
  public init?(
    can: String,
    certificate: Data,
    issuer: Data?,
    chipSerial: ChipSerial,
    activationCheck: ActivationCheck,
    signatureCertificate: Data? = nil
  ) {
    guard CardAccessNumber(digits: can) != nil else { return nil }
    guard !certificate.isEmpty else { return nil }
    self.can = can
    self.certDER = certificate
    self.issuerDER = issuer
    self.chipSerial = chipSerial
    self.activationCheck = activationCheck
    self.signatureCertDER = signatureCertificate
  }
}
