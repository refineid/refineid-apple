// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// Reading the SignedData and the one SignerInfo it carries.
extension CmsSignerVerification {
  /// The signed attributes of one SignerInfo, as consulted.
  internal struct SignedAttributes {
    /// The attributes retagged to the SET the signature covers.
    internal let signedSet: Data

    /// How many content-type attributes there are.
    internal let contentTypeCount: Int

    /// Whether the one content-type attribute names id-data.
    internal let contentTypeIsData: Bool

    /// Whether an ESS signing-certificate attribute of either version
    /// is present.
    internal let hasSigningCertificate: Bool

    /// Whether a signing-time attribute is present.
    internal let hasSigningTime: Bool

    /// Every message-digest attribute value, as written.
    private let messageDigests: [Data]

    /// Reads the attributes within `element` of `cms`.
    internal init(_ cms: Data, element: DerReader.Element) {
      var retagged = cms.subdata(in: element.raw)
      retagged[retagged.startIndex] = DerValues.tagSet
      signedSet = retagged
      var contentTypes: [Data] = []
      var digests: [Data] = []
      var signingCertificate = false
      var signingTime = false
      var reader = DerReader(cms, within: element)
      while let attribute = reader.next() {
        var parts = DerReader(cms, within: attribute)
        guard
          attribute.tag == DerValues.tagSequence,
          let type = parts.next(),
          let values = parts.next(),
          values.tag == DerValues.tagSet
        else { continue }
        var set = DerReader(cms, within: values)
        let value = set.next()
        switch parts.data(of: type) {
        case DerEncoder.objectIdentifier(SignOids.contentType):
          // A content-type attribute carries exactly one value
          // (RFC 5652 section 11.1).
          contentTypes.append(set.isAtEnd ? value.map { set.data(of: $0) } ?? Data() : Data())

        case DerEncoder.objectIdentifier(SignOids.messageDigest):
          if let value, value.tag == DerValues.tagOctetString, set.isAtEnd {
            digests.append(set.contentData(of: value))
          } else {
            digests.append(Data())
          }

        case DerEncoder.objectIdentifier(SignOids.signingCertificate),
          DerEncoder.objectIdentifier(SignOids.signingCertificateV2):
          signingCertificate = true

        case DerEncoder.objectIdentifier(SignOids.signingTime):
          signingTime = true

        default:
          continue
        }
      }
      contentTypeCount = contentTypes.count
      contentTypeIsData =
        contentTypes == [DerEncoder.objectIdentifier(SignOids.data)]
      messageDigests = digests
      hasSigningCertificate = signingCertificate
      hasSigningTime = signingTime
    }

    /// The one message-digest value of `byteCount` octets, nil when
    /// absent, repeated or of another length.
    internal func messageDigest(byteCount: Int) -> Data? {
      guard messageDigests.count == 1, let only = messageDigests.first,
        only.count == byteCount
      else {
        return nil
      }
      return only
    }

    /// Every signature-time-stamp token among `unsigned`.
    internal func timestampTokens(in cms: Data, unsigned: DerReader.Element?) -> [Data] {
      guard let unsigned else { return [] }
      var found: [Data] = []
      var reader = DerReader(cms, within: unsigned)
      while let attribute = reader.next() {
        var parts = DerReader(cms, within: attribute)
        guard
          attribute.tag == DerValues.tagSequence,
          let type = parts.next(),
          type.tag == DerValues.tagObjectIdentifier,
          let values = parts.next(),
          values.tag == DerValues.tagSet,
          parts.isAtEnd,
          parts.data(of: type)
            == DerEncoder.objectIdentifier(SignOids.signatureTimestampToken)
        else { continue }
        var set = DerReader(cms, within: values)
        while let token = set.next() {
          guard token.tag == DerValues.tagSequence else { continue }
          found.append(cms.subdata(in: token.raw))
        }
      }
      return found
    }
  }

  /// The fields of the one SignerInfo of `cms`, nil when the structure
  /// is not a SignedData with exactly one SignerInfo carrying signed
  /// attributes.
  internal static func signerFields(in cms: Data) -> SignerFields? {
    guard let signerInfos = Self.signerInfos(in: cms) else { return nil }
    var infos = DerReader(cms, within: signerInfos)
    guard
      let signerInfo = infos.next(),
      signerInfo.tag == DerValues.tagSequence,
      infos.isAtEnd
    else {
      return nil
    }
    var fields = DerReader(cms, within: signerInfo)
    guard
      let version = fields.next(), version.tag == DerValues.tagInteger,
      let identifier = fields.next(),
      let digest = fields.next(), digest.tag == DerValues.tagSequence,
      let signed = fields.next(), signed.tag == DerValues.tagContext0Constructed,
      let algorithm = fields.next(), algorithm.tag == DerValues.tagSequence,
      let signature = fields.next(), signature.tag == DerValues.tagOctetString
    else {
      return nil
    }
    var unsigned: DerReader.Element?
    if let trailing = fields.next() {
      guard trailing.tag == DerValues.tagContext1Constructed, fields.isAtEnd else {
        return nil
      }
      unsigned = trailing
    }
    guard
      let signerIdentifier = Self.signerIdentifier(identifier, in: cms),
      let digestAlgorithm = Digest(algorithmIdentifier: fields.data(of: digest)),
      let scheme = SignatureScheme(identifier: fields.data(of: algorithm), digest: digestAlgorithm)
    else {
      return nil
    }
    return SignerFields(
      identifier: signerIdentifier,
      digest: digestAlgorithm,
      scheme: scheme,
      signedAttributes: signed,
      signatureValue: fields.contentData(of: signature),
      unsignedAttributes: unsigned
    )
  }

  /// The SignerIdentifier `element` encodes, nil for another shape.
  private static func signerIdentifier(
    _ element: DerReader.Element,
    in cms: Data
  ) -> SignerIdentifier? {
    switch element.tag {
    case DerValues.tagSequence:
      var reader = DerReader(cms, within: element)
      guard
        let issuer = reader.next(), issuer.tag == DerValues.tagSequence,
        let serial = reader.next(), serial.tag == DerValues.tagInteger,
        reader.isAtEnd,
        let magnitude = try? CertificateRevocationList.unsignedIntegerContent(
          reader.contentData(of: serial))
      else {
        return nil
      }
      return .issuerAndSerialNumber(issuer: reader.data(of: issuer), serial: magnitude)

    case DerValues.tagContext0Primitive:
      return .subjectKeyIdentifier(DerReader(cms).contentData(of: element))

    default:
      return nil
    }
  }

  /// Whether an EncapsulatedContentInfo names id-data and carries no
  /// eContent, as a detached signature does (RFC 5652 section 5.2).
  private static func isDetachedData(_ element: DerReader.Element, in cms: Data) -> Bool {
    var reader = DerReader(cms, within: element)
    guard let type = reader.next(), reader.isAtEnd else { return false }
    return reader.data(of: type) == DerEncoder.objectIdentifier(SignOids.data)
  }

  /// The SignerInfos SET of the SignedData in `cms`.
  private static func signerInfos(in cms: Data) -> DerReader.Element? {
    var outer = DerReader(cms)
    guard let contentInfo = outer.next(), contentInfo.tag == DerValues.tagSequence,
      outer.isAtEnd
    else { return nil }
    var info = DerReader(cms, within: contentInfo)
    guard
      let type = info.next(),
      info.data(of: type) == DerEncoder.objectIdentifier(SignOids.signedData),
      let wrapped = info.next(), wrapped.tag == DerValues.tagContext0Constructed,
      info.isAtEnd
    else { return nil }
    var wrapper = DerReader(cms, within: wrapped)
    guard let signedData = wrapper.next(), signedData.tag == DerValues.tagSequence,
      wrapper.isAtEnd
    else { return nil }
    var reader = DerReader(cms, within: signedData)
    guard
      let version = reader.next(), version.tag == DerValues.tagInteger,
      let digests = reader.next(), digests.tag == DerValues.tagSet,
      let encapsulated = reader.next(), encapsulated.tag == DerValues.tagSequence,
      Self.isDetachedData(encapsulated, in: cms),
      var element = reader.next()
    else { return nil }
    if element.tag == DerValues.tagContext0Constructed {
      guard let following = reader.next() else { return nil }
      element = following
    }
    if element.tag == DerValues.tagContext1Constructed {
      guard let following = reader.next() else { return nil }
      element = following
    }
    guard element.tag == DerValues.tagSet, reader.isAtEnd else { return nil }
    return element
  }
}
