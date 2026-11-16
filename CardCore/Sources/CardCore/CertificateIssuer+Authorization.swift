// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Names, validity, BasicConstraints, KeyUsage, and critical extensions.
extension CertificateIssuer {
  /// One certificate extension's identifier and opaque extnValue.
  private struct CertificateExtension {
    /// Whether the extension is marked critical.
    let critical: Bool

    /// The extension object identifier.
    let identifier: Data

    /// The DER value wrapped by extnValue's OCTET STRING.
    let value: Data
  }

  /// Parsed BasicConstraints semantics needed by a direct relationship.
  private enum BasicConstraintsVerdict {
    /// cA is TRUE and an optional pathLenConstraint is well formed.
    case certificateAuthority

    /// cA is FALSE and no pathLenConstraint is present.
    case endEntity

    /// The extension does not carry unambiguous supported semantics.
    case invalid
  }

  /// Internal parser failure, always mapped to a closed relationship.
  private enum ExtensionFailure: Error {
    case malformed
  }

  /// Fixed SEQUENCE fields from signature through SubjectPublicKeyInfo.
  private static let certificateSequencesAfterSerial = 5

  /// KeyUsage bits that authorize a leaf document signature (RFC 5280 §4.2.1.3; EN 319 412-2 §4.3.2).
  private static let documentSigningKeyUsageMask =
    DerValues.keyUsageDigitalSignatureBit | DerValues.keyUsageContentCommitmentBit

  /// ExtendedKeyUsage OIDs compatible with document signing when EKU is present (RFC 5280 §4.2.1.12; RFC 9336).
  private static let documentSigningPurposes: Set<Data> = [
    DerEncoder.objectIdentifier(SignOids.anyExtendedKeyUsage),
    DerEncoder.objectIdentifier(SignOids.emailProtection),
    DerEncoder.objectIdentifier(SignOids.documentSigning),
    DerEncoder.objectIdentifier(SignOids.adobePdfSigning),
    DerEncoder.objectIdentifier(SignOids.microsoftDocumentSigning),
  ]

  /// Whether normalized X.509 names link the certificate to the issuer.
  internal static func namesMatch(subject: Parsed, issuer: Parsed) -> Bool {
    let subjectIssuer =
      SecCertificateCopyNormalizedIssuerSequence(subject.certificate) as Data?
    let authoritySubject =
      SecCertificateCopyNormalizedSubjectSequence(issuer.certificate) as Data?
    return subjectIssuer != nil && subjectIssuer == authoritySubject
  }

  /// Whether the certificate covers the requested relationship date.
  internal static func isValid(_ certificate: Parsed, at date: Date) -> Bool {
    guard let validity = CertificateValidity.window(of: certificate.certificate) else {
      return false
    }
    return validity.notBefore <= date && date <= validity.notAfter
  }

  /// Whether the revoked subject has unambiguous end-entity semantics.
  internal static func isPermittedEndEntity(_ subject: Parsed) -> Bool {
    Self.satisfiesEndEntityProfile(subject, requireDocumentSigning: false)
  }

  /// Whether `subject` satisfies document-signer BasicConstraints, KeyUsage, and ExtendedKeyUsage rules.
  internal static func isPermittedDocumentSigner(_ subject: Parsed) -> Bool {
    Self.satisfiesEndEntityProfile(subject, requireDocumentSigning: true)
  }

  /// Whether a subordinate CA certificate's ExtendedKeyUsage, when present, permits document signing.
  internal static func permitsDocumentSigningIssuance(_ certificate: Data) -> Bool {
    guard
      let parsed = Self.parsed(certificate),
      let extensions = try? Self.certificateExtensions(parsed)
    else {
      return false
    }
    let ekuIdentifier = DerEncoder.objectIdentifier(SignOids.extendedKeyUsage)
    for extensionValue in extensions where extensionValue.identifier == ekuIdentifier {
      let purposes = Self.extendedKeyUsagePurposes(extensionValue.value)
      guard !purposes.isEmpty, !purposes.isDisjoint(with: Self.documentSigningPurposes) else {
        return false
      }
    }
    return true
  }

  /// Whether BasicConstraints and KeyUsage authorize certificate signing.
  internal static func canIssueCertificates(_ issuer: Parsed) -> Bool {
    guard let extensions = try? Self.certificateExtensions(issuer) else { return false }
    var basicConstraintsSeen = false
    var isCertificateAuthority = false
    var keyUsageAllowsSigning = true
    var keyUsageSeen = false
    for extensionValue in extensions {
      switch extensionValue.identifier {
      case DerEncoder.objectIdentifier(SignOids.basicConstraints):
        guard !basicConstraintsSeen else { return false }
        basicConstraintsSeen = true
        isCertificateAuthority =
          extensionValue.critical
          && Self.basicConstraints(extensionValue.value) == .certificateAuthority

      case DerEncoder.objectIdentifier(SignOids.keyUsage):
        guard !keyUsageSeen else { return false }
        keyUsageSeen = true
        keyUsageAllowsSigning = Self.keyUsageAllowsCertificateSigning(extensionValue.value)

      default:
        if extensionValue.critical { return false }
      }
    }
    return basicConstraintsSeen && isCertificateAuthority && keyUsageAllowsSigning
  }

  /// Evaluates end-entity extensions, optionally requiring document-signing KeyUsage and EKU compatibility.
  private static func satisfiesEndEntityProfile(
    _ subject: Parsed,
    requireDocumentSigning: Bool
  ) -> Bool {
    guard let extensions = try? Self.certificateExtensions(subject) else { return false }
    var basicConstraintsSeen = false
    var extendedKeyUsageSeen = false
    var keyUsageSeen = false
    for extensionValue in extensions {
      switch extensionValue.identifier {
      case DerEncoder.objectIdentifier(SignOids.basicConstraints):
        guard !basicConstraintsSeen, Self.basicConstraints(extensionValue.value) == .endEntity
        else { return false }
        basicConstraintsSeen = true

      case DerEncoder.objectIdentifier(SignOids.extendedKeyUsage):
        let purposes = Self.extendedKeyUsagePurposes(extensionValue.value)
        guard
          !extendedKeyUsageSeen,
          !purposes.isEmpty,
          !requireDocumentSigning || !purposes.isDisjoint(with: Self.documentSigningPurposes)
        else { return false }
        extendedKeyUsageSeen = true

      case DerEncoder.objectIdentifier(SignOids.keyUsage):
        guard
          !keyUsageSeen,
          Self.isAcceptableEndEntityKeyUsage(
            extensionValue.value, requireSigningBit: requireDocumentSigning)
        else { return false }
        keyUsageSeen = true

      default:
        if extensionValue.critical { return false }
      }
    }
    return !requireDocumentSigning || keyUsageSeen
  }

  /// Checks non-CA `KeyUsage` bits, optionally requiring `digitalSignature` or `contentCommitment`.
  private static func isAcceptableEndEntityKeyUsage(
    _ encoded: Data,
    requireSigningBit: Bool
  ) -> Bool {
    guard
      let firstUsageByte = Self.keyUsageBits(encoded),
      firstUsageByte & DerValues.keyUsageCertificateSigningBit == 0,
      firstUsageByte & DerValues.keyUsageCrlSigningBit == 0
    else { return false }
    return !requireSigningBit || (firstUsageByte & Self.documentSigningKeyUsageMask != 0)
  }

  /// Walks from TBSCertificate's fixed fields to its extensions block.
  private static func certificateExtensions(_ certificate: Parsed) throws -> [CertificateExtension]
  {
    var reader = DerReader(certificate.encoded, within: certificate.tbs)
    guard var serial = Self.nextElement(from: &reader, in: certificate.encoded) else {
      throw ExtensionFailure.malformed
    }
    if serial.tag == DerValues.tagContext0Constructed {
      guard let following = Self.nextElement(from: &reader, in: certificate.encoded) else {
        throw ExtensionFailure.malformed
      }
      serial = following
    }
    guard serial.tag == DerValues.tagInteger else { throw ExtensionFailure.malformed }
    for _ in 0..<Self.certificateSequencesAfterSerial {
      guard
        Self.nextElement(from: &reader, in: certificate.encoded, tag: DerValues.tagSequence) != nil
      else { throw ExtensionFailure.malformed }
    }
    return try Self.trailingExtensions(certificate.encoded, reader: &reader)
  }

  /// Parses optional unique identifiers and one extensions wrapper.
  private static func trailingExtensions(
    _ encoded: Data,
    reader: inout DerReader
  ) throws -> [CertificateExtension] {
    var extensions: [CertificateExtension] = []
    var foundExtensions = false
    while let trailing = Self.nextElement(from: &reader, in: encoded) {
      switch trailing.tag {
      case DerValues.tagContext1Primitive, DerValues.tagContext2Primitive:
        continue

      case DerValues.tagContext3Constructed where !foundExtensions:
        extensions = try Self.extensions(in: encoded, wrapper: trailing)
        foundExtensions = true

      default:
        throw ExtensionFailure.malformed
      }
    }
    guard reader.isAtEnd else { throw ExtensionFailure.malformed }
    return extensions
  }

  /// Parses unique RFC 5280 Extension values.
  private static func extensions(
    in encoded: Data,
    wrapper: DerReader.Element
  ) throws -> [CertificateExtension] {
    var wrapperReader = DerReader(encoded, within: wrapper)
    guard
      let sequence = Self.nextElement(
        from: &wrapperReader, in: encoded, tag: DerValues.tagSequence),
      wrapperReader.isAtEnd
    else { throw ExtensionFailure.malformed }
    var reader = DerReader(encoded, within: sequence)
    var result: [CertificateExtension] = []
    var identifiers: Set<Data> = []
    while let entry = Self.nextElement(from: &reader, in: encoded) {
      guard entry.tag == DerValues.tagSequence else { throw ExtensionFailure.malformed }
      let parsed = try Self.extensionValue(in: encoded, entry: entry)
      guard identifiers.insert(parsed.identifier).inserted else { throw ExtensionFailure.malformed }
      result.append(parsed)
    }
    guard reader.isAtEnd, !result.isEmpty else { throw ExtensionFailure.malformed }
    return result
  }

  /// Parses one Extension, retaining criticality for known constraints.
  private static func extensionValue(
    in encoded: Data,
    entry: DerReader.Element
  ) throws -> CertificateExtension {
    var reader = DerReader(encoded, within: entry)
    guard
      let identifier = Self.nextElement(
        from: &reader, in: encoded, tag: DerValues.tagObjectIdentifier),
      var value = Self.nextElement(from: &reader, in: encoded)
    else { throw ExtensionFailure.malformed }
    var critical = false
    if value.tag == DerValues.tagBoolean {
      guard
        reader.contentData(of: value) == Data([DerValues.booleanTrue]),
        let following = Self.nextElement(from: &reader, in: encoded)
      else { throw ExtensionFailure.malformed }
      critical = true
      value = following
    }
    guard value.tag == DerValues.tagOctetString, reader.isAtEnd else {
      throw ExtensionFailure.malformed
    }
    return CertificateExtension(
      critical: critical,
      identifier: reader.data(of: identifier),
      value: reader.contentData(of: value)
    )
  }

  /// Reads BasicConstraints and validates any nonnegative path length.
  private static func basicConstraints(_ encoded: Data) -> BasicConstraintsVerdict {
    guard let sequence = Self.onlyElement(in: encoded, tag: DerValues.tagSequence) else {
      return .invalid
    }
    var reader = DerReader(encoded, within: sequence)
    guard let first = Self.nextElement(from: &reader, in: encoded) else {
      return reader.isAtEnd ? .endEntity : .invalid
    }
    guard first.tag == DerValues.tagBoolean else { return .invalid }
    let authority = reader.contentData(of: first)
    if authority == Data([DerValues.booleanFalse]) {
      // Narrow compatibility exception: G4R signers encode this DEFAULT.
      return reader.isAtEnd ? .endEntity : .invalid
    }
    guard authority == Data([DerValues.booleanTrue]) else { return .invalid }
    if let pathLength = Self.nextElement(from: &reader, in: encoded) {
      guard
        pathLength.tag == DerValues.tagInteger,
        (try? CertificateRevocationList.unsignedIntegerContent(reader.contentData(of: pathLength)))
          != nil
      else { return .invalid }
    }
    return reader.isAtEnd ? .certificateAuthority : .invalid
  }

  /// Parses a nonempty sequence of unique extended-key-usage OIDs, or returns empty when invalid.
  private static func extendedKeyUsagePurposes(_ encoded: Data) -> Set<Data> {
    guard let sequence = Self.onlyElement(in: encoded, tag: DerValues.tagSequence) else {
      return []
    }
    var reader = DerReader(encoded, within: sequence)
    var purposes: Set<Data> = []
    while let purpose = Self.nextElement(from: &reader, in: encoded) {
      guard
        purpose.tag == DerValues.tagObjectIdentifier,
        purposes.insert(reader.data(of: purpose)).inserted
      else { return [] }
    }
    return reader.isAtEnd ? purposes : []
  }

  /// Validates a KeyUsage BIT STRING and returns its first payload octet.
  private static func keyUsageBits(_ encoded: Data) -> UInt8? {
    guard
      let bits = Self.onlyElement(in: encoded, tag: DerValues.tagBitString)
    else {
      return nil
    }
    let content = DerReader(encoded).contentData(of: bits)
    guard
      let unusedBits = content.first,
      unusedBits < UInt8.bitWidth,
      let firstUsageByte = content.dropFirst().first,
      let lastUsageByte = content.last
    else {
      return nil
    }
    let unusedMask = UInt8.max >> (UInt8.bitWidth - Int(unusedBits))
    let finalUsedBit = UInt8(1) << unusedBits
    guard
      lastUsageByte & unusedMask == 0,
      lastUsageByte & finalUsedBit != 0
    else {
      return nil
    }
    return firstUsageByte
  }

  /// Reads keyCertSign when a KeyUsage extension is present.
  private static func keyUsageAllowsCertificateSigning(
    _ encoded: Data
  ) -> Bool {
    guard let firstUsageByte = Self.keyUsageBits(encoded) else { return false }
    return firstUsageByte & DerValues.keyUsageCertificateSigningBit != 0
  }
}
