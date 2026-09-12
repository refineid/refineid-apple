// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CCryptoki
import Foundation
import Security

/// Composes the CKA_LABEL for a token identity's objects.
///
/// One rule, every field verbatim: the base is "CN (card number)",
/// e.g. "SURNAME GIVENNAME 99999999A (AB1234567)", and the signing
/// profile appends the key name -- " - Signature (PIN 2)" -- so a
/// key picker states which key it is; the authentication profile
/// exposes a single key and needs no suffix. Surname-first CN scans
/// and sorts in long certificate lists and matches how the platform
/// itself presents certificates; parentheses consistently carry
/// supplementary data. The localized key name is passed through
/// unmodified, so renaming in the token extension propagates
/// everywhere; labels are display text, not stable identifiers, and
/// consumers select by CKA_ID.
internal enum KeyLabel {
  /// X.500 attribute OIDs used to compose the label.
  private static let commonNameOid = "2.5.4.3"

  /// The token-ID marker preceding the card number in RefineID token
  /// instance identifiers.
  private static let cardNumberMarker = "refineid-card-"

  /// The composed label; falls back to the certificate summary plus
  /// the key name when the subject or token lacks the needed fields.
  internal static func compose(
    keyName: String, certificate: SecCertificate, tokenID: String
  ) -> String {
    let commonName =
      subjectAttributes(certificate)[commonNameOid]
      ?? SecCertificateCopySubjectSummary(certificate) as String?
    guard let commonName, let cardNumber = cardNumber(tokenID: tokenID) else {
      guard let summary = SecCertificateCopySubjectSummary(certificate) as String?
      else { return keyName }
      return "\(summary) - \(keyName)"
    }
    let base = "\(commonName) (\(cardNumber))"
    return IdentityPolicy.isSigningProfile ? "\(base) - \(keyName)" : base
  }

  /// Subject RDN values keyed by attribute OID.
  private static func subjectAttributes(
    _ certificate: SecCertificate
  ) -> [String: String] {
    let wanted = [kSecOIDX509V1SubjectName] as CFArray
    guard
      let values = SecCertificateCopyValues(certificate, wanted, nil)
        as? [String: [String: Any]],
      let subject = values[kSecOIDX509V1SubjectName as String],
      let members = subject[kSecPropertyKeyValue as String] as? [[String: Any]]
    else { return [:] }
    var attributes: [String: String] = [:]
    for member in members {
      guard let oid = member[kSecPropertyKeyLabel as String] as? String,
        let value = member[kSecPropertyKeyValue as String] as? String
      else { continue }
      attributes[oid] = value
    }
    return attributes
  }

  /// The card number carried in a RefineID token instance identifier,
  /// uppercased as printed on the card; nil for other tokens.
  private static func cardNumber(tokenID: String) -> String? {
    guard let range = tokenID.range(of: cardNumberMarker) else { return nil }
    let number = tokenID[range.upperBound...]
    guard !number.isEmpty else { return nil }
    return number.uppercased()
  }
}
