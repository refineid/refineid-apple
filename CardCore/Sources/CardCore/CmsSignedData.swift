// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// One DER-encoded CMS ContentInfo carrying SignedData (RFC 5652 sections 3 and 5.1).
internal struct CmsSignedData {
  /// The structural fields of one SignerInfo carrying signed attributes
  /// (RFC 5652 section 5.3).
  internal struct SignerFields {
    /// The CMSVersion INTEGER element.
    internal let version: DerReader.Element

    /// The SignerIdentifier choice element.
    internal let identifier: DerReader.Element

    /// The DigestAlgorithmIdentifier SEQUENCE element.
    internal let digestAlgorithm: DerReader.Element

    /// The `[0] IMPLICIT SignedAttributes` element.
    internal let signedAttributes: DerReader.Element

    /// The SignatureAlgorithmIdentifier SEQUENCE element.
    internal let signatureAlgorithm: DerReader.Element

    /// The SignatureValue OCTET STRING content octets.
    internal let signatureValue: Data

    /// The optional `[1] IMPLICIT UnsignedAttributes` element.
    internal let unsignedAttributes: DerReader.Element?
  }

  /// The complete SignedData SEQUENCE element inside the `[0] EXPLICIT` wrapper.
  internal let element: DerReader.Element

  /// The CMSVersion INTEGER element.
  internal let version: DerReader.Element

  /// The DigestAlgorithmIdentifiers SET element.
  internal let digestAlgorithms: DerReader.Element

  /// The EncapsulatedContentInfo SEQUENCE element.
  internal let encapsulatedContentInfo: DerReader.Element

  /// The optional `[0] IMPLICIT CertificateSet` element.
  internal let certificates: DerReader.Element?

  /// The optional `[1] IMPLICIT RevocationInfoChoices` element.
  internal let revocationChoices: DerReader.Element?

  /// The SignerInfos SET element.
  internal let signerInfos: DerReader.Element

  /// Unwraps one complete `ContentInfo` naming `id-signedData` and parses
  /// its `SignedData` sequence, or nil when any level is malformed or has
  /// trailing bytes.
  internal init?(in encoded: Data) {
    guard let signedData = Self.signedDataElement(in: encoded) else {
      return nil
    }
    var reader = DerReader(encoded, within: signedData)
    guard
      let versionElement = reader.next(),
      versionElement.tag == DerValues.tagInteger,
      !versionElement.content.isEmpty,
      let algorithmSet = reader.next(),
      algorithmSet.tag == DerValues.tagSet,
      let encapsulated = reader.next(),
      encapsulated.tag == DerValues.tagSequence,
      var candidate = reader.next()
    else {
      return nil
    }
    let certificateSet: DerReader.Element?
    if candidate.tag == DerValues.tagContext0Constructed {
      certificateSet = candidate
      guard let following = reader.next() else { return nil }
      candidate = following
    } else {
      certificateSet = nil
    }
    let revocations: DerReader.Element?
    if candidate.tag == DerValues.tagContext1Constructed {
      revocations = candidate
      guard let following = reader.next() else { return nil }
      candidate = following
    } else {
      revocations = nil
    }
    guard candidate.tag == DerValues.tagSet, reader.isAtEnd else {
      return nil
    }
    self.element = signedData
    self.version = versionElement
    self.digestAlgorithms = algorithmSet
    self.encapsulatedContentInfo = encapsulated
    self.certificates = certificateSet
    self.revocationChoices = revocations
    self.signerInfos = candidate
  }

  /// Parses the fields of one SignerInfo requiring `[0] signedAttrs` and
  /// allowing optional `[1] unsignedAttrs` (RFC 5652 section 5.3).
  internal static func signerFields(
    of signerElement: DerReader.Element,
    in encoded: Data
  ) -> SignerFields? {
    var reader = DerReader(encoded, within: signerElement)
    guard
      let versionElement = reader.next(),
      versionElement.tag == DerValues.tagInteger,
      !versionElement.content.isEmpty,
      let identifierElement = reader.next(),
      let digestElement = reader.next(),
      digestElement.tag == DerValues.tagSequence,
      let signedElement = reader.next(),
      signedElement.tag == DerValues.tagContext0Constructed,
      let signatureAlgorithmElement = reader.next(),
      signatureAlgorithmElement.tag == DerValues.tagSequence,
      let signatureElement = reader.next(),
      signatureElement.tag == DerValues.tagOctetString
    else {
      return nil
    }
    let unsignedElement = reader.next()
    if let unsignedElement {
      guard unsignedElement.tag == DerValues.tagContext1Constructed else {
        return nil
      }
    }
    guard reader.isAtEnd else {
      return nil
    }
    return SignerFields(
      version: versionElement,
      identifier: identifierElement,
      digestAlgorithm: digestElement,
      signedAttributes: signedElement,
      signatureAlgorithm: signatureAlgorithmElement,
      signatureValue: reader.contentData(of: signatureElement),
      unsignedAttributes: unsignedElement
    )
  }

  /// Unwraps `ContentInfo { id-signedData, [0] EXPLICIT SignedData }`.
  private static func signedDataElement(in encoded: Data) -> DerReader.Element? {
    var outer = DerReader(encoded)
    guard
      let contentInfo = outer.next(),
      contentInfo.tag == DerValues.tagSequence,
      outer.isAtEnd
    else {
      return nil
    }
    var content = DerReader(encoded, within: contentInfo)
    guard
      let contentType = content.next(),
      contentType.tag == DerValues.tagObjectIdentifier,
      content.data(of: contentType) == DerEncoder.objectIdentifier(SignOids.signedData),
      let explicitWrapper = content.next(),
      explicitWrapper.tag == DerValues.tagContext0Constructed,
      content.isAtEnd
    else {
      return nil
    }
    var explicit = DerReader(encoded, within: explicitWrapper)
    guard
      let signedData = explicit.next(),
      signedData.tag == DerValues.tagSequence,
      explicit.isAtEnd
    else {
      return nil
    }
    return signedData
  }

  /// The inner OCTET STRING content of an attached `EncapsulatedContentInfo`
  /// naming `contentType`, or nil when detached, differently typed, or malformed.
  internal func attachedOctetString(
    contentType: String,
    in encoded: Data
  ) -> Data? {
    var contentInfo = DerReader(encoded, within: encapsulatedContentInfo)
    guard
      let type = contentInfo.next(),
      type.tag == DerValues.tagObjectIdentifier,
      contentInfo.data(of: type) == DerEncoder.objectIdentifier(contentType),
      let wrapper = contentInfo.next(),
      wrapper.tag == DerValues.tagContext0Constructed,
      contentInfo.isAtEnd
    else {
      return nil
    }
    var wrapped = DerReader(encoded, within: wrapper)
    guard
      let octets = wrapped.next(),
      octets.tag == DerValues.tagOctetString,
      wrapped.isAtEnd
    else {
      return nil
    }
    return wrapped.contentData(of: octets)
  }

  /// The sole SignerInfo SEQUENCE element when `signerInfos` contains
  /// exactly one signer, or nil when empty, repeated, or malformed.
  internal func soleSignerInfoElement(in encoded: Data) -> DerReader.Element? {
    var reader = DerReader(encoded, within: signerInfos)
    guard
      let signer = reader.next(),
      signer.tag == DerValues.tagSequence,
      reader.isAtEnd
    else {
      return nil
    }
    return signer
  }
}
