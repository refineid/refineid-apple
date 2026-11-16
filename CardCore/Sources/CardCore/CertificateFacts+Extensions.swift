// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// X.509 extension parsing used by `CertificateFacts`.
extension CertificateFacts {
  /// The extension facts collected in one pass.
  internal struct ExtensionFacts {
    internal var issuers: [String] = []
    internal var revocationLists: [String] = []
    internal var responders: [String] = []
    internal var subjectKeyIdentifier = SubjectKeyIdentifier.absent
    internal var timestampingUsage = TimestampingUsage.absent
    internal var basicConstraints = BasicConstraints.absent
    internal var timestampingKeyUsage = TimestampingKeyUsage.absent
  }

  /// What one extension says about the timestamping EKU.
  internal enum TimestampingUsage: Equatable {
    case absent
    case different
    case invalid
    case valid
  }

  /// The certificate's BasicConstraints status for a timestamp signer.
  internal enum BasicConstraints: Equatable {
    /// No BasicConstraints extension is present, which is valid for an
    /// end-entity certificate.
    case absent

    /// An explicit end-entity constraint is present.
    case endEntity

    /// The certificate asserts `cA = TRUE`.
    case certificateAuthority

    /// The extension is malformed or duplicated.
    case invalid

    /// A timestamp signer cannot be a CA.
    ///
    /// Malformed profile fields fail closed; an omitted BasicConstraints
    /// extension denotes an end entity.
    internal var isPermittedTimestampSigner: Bool {
      self == .absent || self == .endEntity
    }
  }

  /// The KeyUsage status relevant to signing an RFC 3161 token.
  internal enum TimestampingKeyUsage: Equatable {
    /// KeyUsage is optional for an RFC 3161 end-entity certificate.
    case absent

    /// The usage permits signing but not CA or CRL signing.
    case compatible

    /// The usage lacks signing permission or asserts a CA/CRL role.
    case incompatible

    /// The extension is malformed or duplicated.
    case invalid

    /// An omitted KeyUsage does not itself restrict signing; when present,
    /// it must authorize a leaf signature and not a CA function.
    internal var isPermittedTimestampSigner: Bool {
      self == .absent || self == .compatible
    }
  }

  /// Result of identifying one profile-relevant extension.
  private enum ExtensionPayload {
    case malformed
    case value(Data)
  }

  /// The high two KeyUsage positions authorize a normal leaf signature.
  private static let digitalSignatureKeyUsageBit =
    UInt8(1) << (UInt8.bitWidth - 1)
  private static let contentCommitmentKeyUsageBit =
    Self.digitalSignatureKeyUsageBit >> UInt8(1)

  /// The CA and CRL-signing KeyUsage positions are unsuitable for a TSA leaf.
  private static let crlSigningKeyUsageBit = UInt8(1) << UInt8(1)
  private static let certificateSigningKeyUsageBit =
    Self.crlSigningKeyUsageBit << UInt8(1)

  private static let timestampSigningUsageMask =
    Self.digitalSignatureKeyUsageBit | Self.contentCommitmentKeyUsageBit
  private static let certificateAuthorityUsageMask =
    Self.certificateSigningKeyUsageBit | Self.crlSigningKeyUsageBit

  /// The AIA, CRL, SubjectKeyIdentifier, and timestamp-profile facts,
  /// collected in one pass.
  internal static func extensionFacts(
    in der: Data,
    reader: inout DerReader
  ) -> ExtensionFacts {
    var facts = ExtensionFacts()
    var sawExtensionsBlock = false
    while let element = reader.next() {
      guard element.tag == DerValues.tagContext3Constructed else { continue }
      if sawExtensionsBlock {
        facts.subjectKeyIdentifier = .invalid
      }
      sawExtensionsBlock = true
      Self.readExtensionsBlock(element, der: der, into: &facts)
    }
    if !reader.isAtEnd {
      facts.subjectKeyIdentifier = .invalid
    }
    return facts
  }

  /// Reads one explicit `[3]` extensions wrapper into `facts`.
  private static func readExtensionsBlock(
    _ element: DerReader.Element,
    der: Data,
    into facts: inout ExtensionFacts
  ) {
    var wrapper = DerReader(der, within: element)
    guard
      let extensions = wrapper.next(),
      extensions.tag == DerValues.tagSequence,
      wrapper.isAtEnd
    else {
      facts.subjectKeyIdentifier = .invalid
      return
    }
    var list = DerReader(der, within: extensions)
    while let entry = list.next() {
      Self.addAccessFacts(from: entry, der: der, to: &facts)
      Self.addTimestampingProfileFacts(from: entry, der: der, to: &facts)
      Self.addSubjectKeyIdentifier(from: entry, der: der, to: &facts)
      Self.addTimestampingUsage(from: entry, der: der, to: &facts)
    }
    if !list.isAtEnd {
      facts.subjectKeyIdentifier = .invalid
    }
  }

  /// Records one extension entry's timestamping-EKU verdict.
  private static func addTimestampingUsage(
    from entry: DerReader.Element,
    der: Data,
    to facts: inout ExtensionFacts
  ) {
    switch Self.timestampingUsage(of: entry, in: der) {
    case .different, .absent:
      break

    case .valid where facts.timestampingUsage == .absent:
      facts.timestampingUsage = .valid

    case .invalid, .valid:
      facts.timestampingUsage = .invalid
    }
  }

  /// Adds BasicConstraints and KeyUsage facts that exclusive anchors might
  /// otherwise be allowed to bypass during platform trust evaluation.
  private static func addTimestampingProfileFacts(
    from entry: DerReader.Element,
    der: Data,
    to facts: inout ExtensionFacts
  ) {
    if let basicConstraints = Self.basicConstraints(of: entry, in: der) {
      if facts.basicConstraints == .absent {
        facts.basicConstraints = basicConstraints
      } else {
        facts.basicConstraints = .invalid
      }
    }
    if let keyUsage = Self.timestampingKeyUsage(of: entry, in: der) {
      if facts.timestampingKeyUsage == .absent {
        facts.timestampingKeyUsage = keyUsage
      } else {
        facts.timestampingKeyUsage = .invalid
      }
    }
  }

  /// Adds URLs found in one AIA or CRL-distribution-points extension.
  private static func addAccessFacts(
    from entry: DerReader.Element,
    der: Data,
    to facts: inout ExtensionFacts
  ) {
    if let value = Self.extensionValue(
      entry,
      identifier: SignOids.authorityInfoAccess,
      in: der
    ) {
      let found = Self.urls(in: value, der: der)
      facts.issuers.append(contentsOf: found.issuers)
      facts.responders.append(contentsOf: found.ocsp)
    }
    if let value = Self.extensionValue(
      entry,
      identifier: SignOids.crlDistributionPoints,
      in: der
    ) {
      facts.revocationLists.append(
        contentsOf: Self.distributionPointUrls(in: value, der: der)
      )
    }
  }

  /// The RFC 3161 extended-key-usage verdict for one extension.
  private static func timestampingUsage(
    of entry: DerReader.Element,
    in der: Data
  ) -> TimestampingUsage {
    var reader = DerReader(der, within: entry)
    guard let oid = reader.next() else { return .invalid }
    guard
      reader.data(of: oid)
        == DerEncoder.objectIdentifier(SignOids.extendedKeyUsage)
    else {
      return .different
    }
    guard var value = reader.next() else { return .invalid }
    var critical = false
    if value.tag == DerValues.tagBoolean {
      critical = reader.contentData(of: value) == Data([DerValues.booleanTrue])
      guard let following = reader.next() else { return .invalid }
      value = following
    }
    guard
      critical,
      value.tag == DerValues.tagOctetString,
      reader.isAtEnd
    else {
      return .invalid
    }
    var wrapped = DerReader(der, within: value)
    guard
      let purposes = wrapped.next(),
      purposes.tag == DerValues.tagSequence,
      wrapped.isAtEnd
    else {
      return .invalid
    }
    var list = DerReader(der, within: purposes)
    guard
      let purpose = list.next(),
      list.data(of: purpose)
        == DerEncoder.objectIdentifier(SignOids.timestampingKeyPurpose),
      list.isAtEnd
    else {
      return .invalid
    }
    return .valid
  }

  /// BasicConstraints in one extension, or nil when it is another OID.
  private static func basicConstraints(
    of entry: DerReader.Element,
    in der: Data
  ) -> BasicConstraints? {
    guard
      let value = Self.extensionPayload(
        entry, identifier: SignOids.basicConstraints, in: der
      )
    else { return nil }
    guard case .value(let encoded) = value else { return .invalid }
    var wrapped = DerReader(encoded)
    guard
      let fields = wrapped.next(),
      fields.tag == DerValues.tagSequence,
      wrapped.isAtEnd
    else { return .invalid }
    var reader = DerReader(encoded, within: fields)
    guard let authority = reader.next() else {
      return .endEntity
    }
    guard
      authority.tag == DerValues.tagBoolean,
      reader.contentData(of: authority) == Data([DerValues.booleanTrue])
    else { return .invalid }
    if let pathLength = reader.next() {
      guard
        pathLength.tag == DerValues.tagInteger,
        !reader.contentData(of: pathLength).isEmpty
      else { return .invalid }
    }
    return reader.isAtEnd ? .certificateAuthority : .invalid
  }

  /// KeyUsage in one extension, or nil when it is another OID.
  private static func timestampingKeyUsage(
    of entry: DerReader.Element,
    in der: Data
  ) -> TimestampingKeyUsage? {
    guard
      let value = Self.extensionPayload(
        entry, identifier: SignOids.keyUsage, in: der
      )
    else { return nil }
    guard case .value(let encoded) = value else { return .invalid }
    var wrapped = DerReader(encoded)
    guard
      let bits = wrapped.next(),
      bits.tag == DerValues.tagBitString,
      wrapped.isAtEnd
    else { return .invalid }
    let content = wrapped.contentData(of: bits)
    guard
      let unusedBits = content.first,
      unusedBits < UInt8.bitWidth,
      let usages = content.dropFirst().first,
      let lastUsageByte = content.last
    else { return .invalid }
    let unusedMask = UInt8.max >> (UInt8.bitWidth - Int(unusedBits))
    guard lastUsageByte & unusedMask == 0 else { return .invalid }
    let permitsSignature = usages & Self.timestampSigningUsageMask != 0
    let assertsCaRole = usages & Self.certificateAuthorityUsageMask != 0
    return permitsSignature && !assertsCaRole ? .compatible : .incompatible
  }

  /// Parses one named certificate extension while preserving malformed
  /// encodings as an explicit profile failure.
  private static func extensionPayload(
    _ entry: DerReader.Element,
    identifier: String,
    in der: Data
  ) -> ExtensionPayload? {
    var reader = DerReader(der, within: entry)
    guard let oid = reader.next() else { return .malformed }
    guard reader.data(of: oid) == DerEncoder.objectIdentifier(identifier)
    else { return nil }
    guard var value = reader.next() else { return .malformed }
    if value.tag == DerValues.tagBoolean {
      guard
        reader.contentData(of: value) == Data([DerValues.booleanTrue]),
        let following = reader.next()
      else { return .malformed }
      value = following
    }
    guard value.tag == DerValues.tagOctetString, reader.isAtEnd else {
      return .malformed
    }
    return .value(reader.contentData(of: value))
  }

  /// The OCTET STRING extnValue of one named extension.
  private static func extensionValue(
    _ entry: DerReader.Element,
    identifier: String,
    in der: Data
  ) -> DerReader.Element? {
    var reader = DerReader(der, within: entry)
    guard
      let oid = reader.next(),
      reader.data(of: oid) == DerEncoder.objectIdentifier(identifier),
      var value = reader.next()
    else {
      return nil
    }
    if value.tag == DerValues.tagBoolean {
      guard let following = reader.next() else { return nil }
      value = following
    }
    guard value.tag == DerValues.tagOctetString, reader.isAtEnd else {
      return nil
    }
    return value
  }
}
