// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The CMS SignedData of one PAdES qualified signature (RFC 5652,
/// ETSI EN 319 142-1).
///
/// The PAdES profile is strict about what the signed attributes are:
/// content-type, message-digest and signing-certificate-v2, and
/// nothing else - a signing-time attribute downgrades the signature,
/// because the PDF `/M` entry owns that fact. The attributes are
/// signed in their SET form and carried retagged, and the only certificate
/// embedded is the signer's own: the chain travels in the document security
/// store, not here.
public enum QualifiedDocumentCms {
  /// The values shared by the certificate-carrying and compact encodings.
  private struct AssemblyInput {
    let signedAttributesSet: Data
    let signatureValue: Data
    let signerProfile: CardKeyProfile
    let signerCertificate: Data
    let timestampTokens: [Data]
  }

  /// The SignerInfo digest and signature algorithms of one signature.
  public struct SignerAlgorithms: Equatable, Sendable {
    /// Digests the byte ranges, the signer certificate and the signed
    /// attributes.
    public let digest: DocumentDigestAlgorithm

    /// Must fit both the digest and the signer's key.
    public let signature: DocumentSignatureAlgorithm

    /// The algorithms this suite signs with for one card key.
    internal static func signing(_ profile: CardKeyProfile) -> Self {
      Self(
        digest: QualifiedDocumentCms.signingDigestAlgorithm,
        signature: .signing(
          profile, digest: QualifiedDocumentCms.signingDigestAlgorithm
        )
      )
    }
  }

  /// A failure to assemble the structure.
  public enum AssemblyError: Error, Equatable {
    /// The certificate's public key does not match the selected card profile.
    case certificateProfileMismatch

    /// The signer certificate did not parse far enough to name its
    /// issuer and serial.
    case certificateUnparseable

    /// The signature value was empty or malformed.
    case signatureMalformed

    /// The signed attributes were not the exact canonical PAdES set.
    case signedAttributesMalformed
  }

  /// The digest algorithm this suite signs with.
  public static let signingDigestAlgorithm = DocumentDigestAlgorithm.sha384

  /// The signed attributes in their SET form: what the card digests
  /// and signs (SHA-384 of exactly these bytes).
  public static func signedAttributes(
    byteRangeDigest: Data,
    signerCertificate: Data
  ) -> Data {
    Self.signedAttributes(
      byteRangeDigest: byteRangeDigest,
      signerCertificate: signerCertificate,
      digestAlgorithm: Self.signingDigestAlgorithm
    )
  }

  /// The canonical three-attribute set for one digest algorithm.
  internal static func signedAttributes(
    byteRangeDigest: Data,
    signerCertificate: Data,
    digestAlgorithm: DocumentDigestAlgorithm
  ) -> Data {
    let contentType = attribute(
      SignOids.contentType,
      value: DerEncoder.objectIdentifier(SignOids.data)
    )
    let messageDigest = attribute(
      SignOids.messageDigest,
      value: DerEncoder.octetString(byteRangeDigest)
    )
    let essCertId = digestAlgorithm.essCertIdV2(certificate: signerCertificate)
    let signingCertificate = attribute(
      SignOids.signingCertificateV2,
      value: DerEncoder.sequence([DerEncoder.sequence([essCertId])])
    )
    return DerEncoder.setOf([contentType, messageDigest, signingCertificate])
  }

  /// The SHA-384 RFC 3161 message imprint this suite requests for a CMS
  /// signature-time-stamp attribute.
  public static func signatureTimestampDigest(
    signatureValue: Data
  ) throws -> Data {
    try Self.signatureTimestampDigest(
      signatureValue: signatureValue, digestAlgorithm: .sha384
    )
  }

  /// The RFC 3161 message imprint for a CMS signature-time-stamp attribute
  /// under one digest algorithm.
  ///
  /// The timestamp covers exactly the contents of SignerInfo.signature, not
  /// the OCTET STRING tag and length that carry those contents in CMS.
  internal static func signatureTimestampDigest(
    signatureValue: Data,
    digestAlgorithm: DocumentDigestAlgorithm
  ) throws -> Data {
    guard !signatureValue.isEmpty else {
      throw AssemblyError.signatureMalformed
    }
    return digestAlgorithm.hash(signatureValue)
  }

  /// The complete ContentInfo, ready for the document's hole.
  ///
  /// `signedAttributesSet` must be the exact bytes the card signed;
  /// they are retagged, never rebuilt. `signatureValue` is exactly the value
  /// that was locally verified and timestamped: an X9.62 DER pair for ECDSA,
  /// or the modulus-wide block for RSA. Timestamp tokens become one unsigned
  /// attribute instance each, sorted and deduplicated.
  public static func assemble(
    signedAttributesSet: Data,
    signatureValue: Data,
    signerProfile: CardKeyProfile,
    signerCertificate: Data,
    timestampTokens: [Data]
  ) throws -> Data {
    try Self.assemble(
      AssemblyInput(
        signedAttributesSet: signedAttributesSet,
        signatureValue: signatureValue,
        signerProfile: signerProfile,
        signerCertificate: signerCertificate,
        timestampTokens: timestampTokens
      ),
      carryingCertificate: true
    )
  }

  /// The same, with the signer's certificate left out.
  ///
  /// A verifier supplies it instead. The certificate is by far the
  /// largest part of a signature, and leaving it out is what lets one
  /// fit somewhere small - a printed code, a header beside a file.
  public static func assembleWithoutCertificates(
    signedAttributesSet: Data,
    signatureValue: Data,
    signerProfile: CardKeyProfile,
    signerCertificate: Data,
    timestampTokens: [Data]
  ) throws -> Data {
    try Self.assemble(
      AssemblyInput(
        signedAttributesSet: signedAttributesSet,
        signatureValue: signatureValue,
        signerProfile: signerProfile,
        signerCertificate: signerCertificate,
        timestampTokens: timestampTokens
      ),
      carryingCertificate: false
    )
  }

  /// Shared assembly for both shapes.
  private static func assemble(
    _ input: AssemblyInput,
    carryingCertificate: Bool
  ) throws -> Data {
    let signedAttributesSet = input.signedAttributesSet
    let signatureValue = input.signatureValue
    let signerProfile = input.signerProfile
    let signerCertificate = input.signerCertificate
    let timestampTokens = input.timestampTokens
    let identity = try issuerAndSerial(of: signerCertificate)
    let algorithms = SignerAlgorithms.signing(signerProfile)
    try Self.validate(
      signedAttributesSet: signedAttributesSet,
      signatureValue: signatureValue,
      signerProfile: signerProfile,
      signerCertificate: signerCertificate,
      algorithms: algorithms
    )
    var signerInfo: [Data] = [
      DerEncoder.integer(SignOids.signerInfoVersion),
      identity,
      algorithms.digest.algorithmIdentifier,
      DerEncoder.retagged(
        signedAttributesSet, to: DerValues.tagContext0Constructed
      ),
      algorithms.signature.algorithmIdentifier,
      DerEncoder.octetString(signatureValue),
    ]
    if let timestamps = Self.timestampAttributes(timestampTokens) {
      signerInfo.append(timestamps)
    }
    var parts: [Data] = [
      DerEncoder.integer(SignOids.cmsVersion),
      DerEncoder.tlv(DerValues.tagSet, algorithms.digest.algorithmIdentifier),
      DerEncoder.sequence([DerEncoder.objectIdentifier(SignOids.data)]),
    ]
    if carryingCertificate {
      parts.append(
        DerEncoder.retagged(
          DerEncoder.tlv(DerValues.tagSet, signerCertificate),
          to: DerValues.tagContext0Constructed
        )
      )
    }
    parts.append(
      DerEncoder.tlv(DerValues.tagSet, DerEncoder.sequence(signerInfo))
    )
    let signedData = DerEncoder.sequence(parts)
    return DerEncoder.sequence([
      DerEncoder.objectIdentifier(SignOids.signedData),
      DerEncoder.tlv(DerValues.tagContext0Constructed, signedData),
    ])
  }

  /// Sorted and deduplicated signature timestamps as unsigned attributes.
  private static func timestampAttributes(_ tokens: [Data]) -> Data? {
    guard !tokens.isEmpty else { return nil }
    let instances = tokens.map { token in
      attribute(SignOids.signatureTimestampToken, value: token)
    }
    let unique = Array(Set(instances)).sorted { left, right in
      left.lexicographicallyPrecedes(right)
    }
    return DerEncoder.retagged(
      DerEncoder.tlv(DerValues.tagSet, unique.reduce(Data(), +)),
      to: DerValues.tagContext1Constructed
    )
  }

  /// One attribute: its OID and one value in a SET.
  private static func attribute(_ oid: String, value: Data) -> Data {
    DerEncoder.sequence([
      DerEncoder.objectIdentifier(oid),
      DerEncoder.tlv(DerValues.tagSet, value),
    ])
  }

  /// IssuerAndSerialNumber from the certificate, byte-identical.
  ///
  /// The issuer Name is copied raw; the serial keeps its exact value
  /// octets. TBSCertificate is walked just far enough: an optional
  /// version, the serial INTEGER, the signature algorithm, the issuer
  /// (RFC 5280 §4.1).
  private static func issuerAndSerial(of certificate: Data) throws -> Data {
    var outer = DerReader(certificate)
    guard let certificateElement = outer.next() else {
      throw AssemblyError.certificateUnparseable
    }
    var certificateReader = DerReader(certificate, within: certificateElement)
    guard let tbs = certificateReader.next() else {
      throw AssemblyError.certificateUnparseable
    }
    var tbsReader = DerReader(certificate, within: tbs)
    guard var element = tbsReader.next() else {
      throw AssemblyError.certificateUnparseable
    }
    if element.tag == DerValues.tagContext0Constructed {
      guard let following = tbsReader.next() else {
        throw AssemblyError.certificateUnparseable
      }
      element = following
    }
    guard element.tag == DerValues.tagInteger else {
      throw AssemblyError.certificateUnparseable
    }
    let serial = tbsReader.data(of: element)
    guard tbsReader.next() != nil, let issuer = tbsReader.next() else {
      throw AssemblyError.certificateUnparseable
    }
    return DerEncoder.sequence([tbsReader.data(of: issuer), serial])
  }
}
