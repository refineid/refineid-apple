// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

extension QualifiedDocumentCms {
  /// One signature decomposed from an existing qualified CMS.
  public struct ReadSignature: Sendable {
    /// The signed attributes retagged to the SET the signature covers.
    public let signedAttributesSet: Data

    /// The SignerInfo's signature value contents.
    public let signatureValue: Data

    /// The SignerInfo digest algorithm, which digests the byte ranges,
    /// the signer certificate and the signed attributes.
    public let digestAlgorithm: DocumentDigestAlgorithm

    /// The embedded certificate the ESS signing-certificate attribute
    /// binds as the signer.
    public let signerCertificate: Data

    /// Every certificate embedded in the CMS, signer included.
    public let embeddedCertificates: [Data]

    /// The message-digest attribute's value: the byte-range digest the
    /// signer signed over.
    public let messageDigest: Data

    /// The RFC 3161 tokens in the signature-timestamp unsigned
    /// attribute, in encoding order.
    public let timestampTokens: [Data]
  }

  /// Why an existing CMS could not be decomposed.
  public enum ReadFailure: Error, Sendable {
    case notSignedData
    case malformedSignedData
    case malformedSignerInfo
    case missingMessageDigest
    case unsupportedDigestAlgorithm
    case signerCertificateUnbound
  }

  /// Decomposes one detached-signature ContentInfo.
  public static func read(_ contentInfo: Data) throws -> ReadSignature {
    var reader = DerReader(contentInfo)
    guard
      let outer = reader.next(),
      outer.tag == DerValues.tagSequence,
      reader.isAtEnd
    else {
      throw ReadFailure.notSignedData
    }
    var content = DerReader(contentInfo, within: outer)
    guard
      let type = content.next(),
      type.tag == DerValues.tagObjectIdentifier,
      content.data(of: type)
        == DerEncoder.objectIdentifier(SignOids.signedData),
      let wrapped = content.next(),
      wrapped.tag == DerValues.tagContext0Constructed,
      content.isAtEnd
    else {
      throw ReadFailure.notSignedData
    }
    var wrapper = DerReader(contentInfo, within: wrapped)
    guard
      let signedData = wrapper.next(),
      signedData.tag == DerValues.tagSequence,
      wrapper.isAtEnd
    else {
      throw ReadFailure.malformedSignedData
    }
    return try readSignedData(
      DerReader(contentInfo, within: signedData),
      encoded: contentInfo
    )
  }

  private static func readSignedData(
    _ signedData: consuming DerReader,
    encoded: Data
  ) throws -> ReadSignature {
    guard
      let version = signedData.next(),
      version.tag == DerValues.tagInteger,
      let digestAlgorithms = signedData.next(),
      digestAlgorithms.tag == DerValues.tagSet,
      let encapsulated = signedData.next(),
      encapsulated.tag == DerValues.tagSequence
    else {
      throw ReadFailure.malformedSignedData
    }
    var certificates: DerReader.Element?
    var element = signedData.next()
    if element?.tag == DerValues.tagContext0Constructed {
      certificates = element
      element = signedData.next()
    }
    if element?.tag == DerValues.tagContext1Constructed {
      element = signedData.next()
    }
    guard
      let signerInfos = element,
      signerInfos.tag == DerValues.tagSet,
      signedData.isAtEnd
    else {
      throw ReadFailure.malformedSignedData
    }
    let embedded = CmsCertificates.inside(encoded)
    guard certificates != nil, !embedded.isEmpty else {
      throw ReadFailure.signerCertificateUnbound
    }
    var infos = DerReader(encoded, within: signerInfos)
    guard
      let signerInfo = infos.next(),
      signerInfo.tag == DerValues.tagSequence,
      infos.isAtEnd
    else {
      throw ReadFailure.malformedSignerInfo
    }
    return try readSignerInfo(
      DerReader(encoded, within: signerInfo),
      encoded: encoded,
      embedded: embedded
    )
  }

  private static func readSignerInfo(
    _ signerInfo: consuming DerReader,
    encoded: Data,
    embedded: [Data]
  ) throws -> ReadSignature {
    guard
      let version = signerInfo.next(),
      version.tag == DerValues.tagInteger,
      signerInfo.next() != nil,
      let digestAlgorithm = signerInfo.next(),
      digestAlgorithm.tag == DerValues.tagSequence,
      let signedAttributes = signerInfo.next(),
      signedAttributes.tag == DerValues.tagContext0Constructed,
      let signatureAlgorithm = signerInfo.next(),
      signatureAlgorithm.tag == DerValues.tagSequence,
      let signature = signerInfo.next(),
      signature.tag == DerValues.tagOctetString
    else {
      throw ReadFailure.malformedSignerInfo
    }
    var timestampTokens: [Data] = []
    if let unsigned = signerInfo.next(),
      unsigned.tag == DerValues.tagContext1Constructed
    {
      timestampTokens = tokens(
        inUnsignedAttributes: unsigned,
        encoded: encoded
      )
    }
    let algorithm = try Self.supported(digestAlgorithm, encoded: encoded)
    let attributesRaw = encoded.subdata(in: signedAttributes.raw)
    var retagged = attributesRaw
    retagged[retagged.startIndex] = DerValues.tagSet
    guard
      let digest = attributeValue(
        SignOids.messageDigest,
        inAttributes: signedAttributes,
        encoded: encoded
      )
    else {
      throw ReadFailure.missingMessageDigest
    }
    let signer = try boundSigner(inToken: encoded, among: embedded)
    return ReadSignature(
      signedAttributesSet: retagged,
      signatureValue: DerReader(encoded).contentData(of: signature),
      digestAlgorithm: algorithm,
      signerCertificate: signer,
      embeddedCertificates: embedded,
      messageDigest: digest,
      timestampTokens: timestampTokens
    )
  }

  /// The SignerInfo digest algorithm, refused unless SHA-256 or SHA-384.
  private static func supported(
    _ digestAlgorithm: DerReader.Element,
    encoded: Data
  ) throws -> DocumentDigestAlgorithm {
    guard
      let algorithm = DocumentDigestAlgorithm(
        algorithmIdentifier: encoded.subdata(in: digestAlgorithm.raw)
      )
    else {
      throw ReadFailure.unsupportedDigestAlgorithm
    }
    return algorithm
  }

  /// The embedded certificate the ESS attribute binds as the signer.
  private static func boundSigner(
    inToken encoded: Data,
    among embedded: [Data]
  ) throws -> Data {
    let signer = embedded.first { candidate in
      (try? CmsSigningCertificate.verify(
        token: encoded,
        certificate: candidate
      )) != nil
    }
    guard let signer else { throw ReadFailure.signerCertificateUnbound }
    return signer
  }

  /// The single OCTET STRING value of one attribute, nil when the
  /// attribute is absent or not that shape.
  private static func attributeValue(
    _ oid: String,
    inAttributes attributes: DerReader.Element,
    encoded: Data
  ) -> Data? {
    let identifier = DerEncoder.objectIdentifier(oid)
    var reader = DerReader(encoded, within: attributes)
    while let attribute = reader.next() {
      guard attribute.tag == DerValues.tagSequence else { return nil }
      var inner = DerReader(encoded, within: attribute)
      guard
        let type = inner.next(),
        type.tag == DerValues.tagObjectIdentifier,
        let values = inner.next(),
        values.tag == DerValues.tagSet
      else {
        return nil
      }
      guard DerReader(encoded).data(of: type) == identifier else { continue }
      var set = DerReader(encoded, within: values)
      guard
        let value = set.next(),
        value.tag == DerValues.tagOctetString,
        set.isAtEnd
      else {
        return nil
      }
      return DerReader(encoded).contentData(of: value)
    }
    return nil
  }

  /// Every signature-timestamp token among the unsigned attributes.
  private static func tokens(
    inUnsignedAttributes attributes: DerReader.Element,
    encoded: Data
  ) -> [Data] {
    let identifier = DerEncoder.objectIdentifier(
      SignOids.signatureTimestampToken)
    var found: [Data] = []
    var reader = DerReader(encoded, within: attributes)
    while let attribute = reader.next() {
      guard attribute.tag == DerValues.tagSequence else { return found }
      var inner = DerReader(encoded, within: attribute)
      guard
        let type = inner.next(),
        type.tag == DerValues.tagObjectIdentifier,
        let values = inner.next(),
        values.tag == DerValues.tagSet,
        DerReader(encoded).data(of: type) == identifier
      else {
        continue
      }
      var set = DerReader(encoded, within: values)
      while let token = set.next() {
        found.append(encoded.subdata(in: token.raw))
      }
    }
    return found
  }
}
