// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Strict validation at the public qualified-CMS assembly boundary.
extension QualifiedDocumentCms {
  /// Refuses malformed values and certificate/profile mismatches.
  ///
  /// `digestAlgorithm` is the SignerInfo digest algorithm: it digests the
  /// byte ranges, the signer certificate and the signed attributes.
  internal static func validate(
    signedAttributesSet: Data,
    signatureValue: Data,
    signerProfile: CardKeyProfile,
    signerCertificate: Data,
    digestAlgorithm: DocumentDigestAlgorithm
  ) throws {
    try Self.validateSignedAttributes(
      signedAttributesSet,
      signerCertificate: signerCertificate,
      digestAlgorithm: digestAlgorithm
    )
    guard Self.hasValidShape(signatureValue, profile: signerProfile) else {
      throw AssemblyError.signatureMalformed
    }
    guard
      let certificate = SecCertificateCreateWithData(
        nil, signerCertificate as CFData
      )
    else {
      throw AssemblyError.certificateUnparseable
    }
    guard CardKeyProfile.resolve(fromCertificate: certificate) == signerProfile
    else {
      throw AssemblyError.certificateProfileMismatch
    }
    try Self.verify(
      signatureValue,
      over: signedAttributesSet,
      with: certificate,
      profile: signerProfile,
      digestAlgorithm: digestAlgorithm
    )
  }

  /// Requires the exact canonical three-attribute PAdES form.
  private static func validateSignedAttributes(
    _ attributes: Data,
    signerCertificate: Data,
    digestAlgorithm: DocumentDigestAlgorithm
  ) throws {
    guard
      let byteRangeDigest = Self.byteRangeDigest(
        fromSignedAttributes: attributes,
        digestAlgorithm: digestAlgorithm
      ),
      attributes
        == Self.signedAttributes(
          byteRangeDigest: byteRangeDigest,
          signerCertificate: signerCertificate,
          digestAlgorithm: digestAlgorithm
        )
    else {
      throw AssemblyError.signedAttributesMalformed
    }
  }

  /// Extracts the one PDF digest from a complete message-digest.
  ///
  /// The digest must have the length of `digestAlgorithm`.
  /// The caller rebuilds all three attributes and compares the complete SET,
  /// so only the canonical PAdES form survives.
  private static func byteRangeDigest(
    fromSignedAttributes attributes: Data,
    digestAlgorithm: DocumentDigestAlgorithm
  ) -> Data? {
    var outer = DerReader(attributes)
    guard
      let set = outer.next(), set.tag == DerValues.tagSet, outer.isAtEnd
    else {
      return nil
    }
    var setReader = DerReader(attributes, within: set)
    var digest: Data?
    while let attribute = setReader.next() {
      guard attribute.tag == DerValues.tagSequence else { return nil }
      guard
        let candidate = Self.messageDigest(
          in: attribute,
          encodedAttributes: attributes,
          digestAlgorithm: digestAlgorithm
        )
      else {
        continue
      }
      guard digest == nil else { return nil }
      digest = candidate
    }
    guard setReader.isAtEnd else { return nil }
    return digest
  }

  /// The digest carried by one message-digest attribute, if this is one.
  private static func messageDigest(
    in attribute: DerReader.Element,
    encodedAttributes: Data,
    digestAlgorithm: DocumentDigestAlgorithm
  ) -> Data? {
    var parts = DerReader(encodedAttributes, within: attribute)
    guard
      let identifier = parts.next(),
      identifier.tag == DerValues.tagObjectIdentifier,
      let values = parts.next(), values.tag == DerValues.tagSet,
      parts.isAtEnd,
      parts.data(of: identifier)
        == DerEncoder.objectIdentifier(SignOids.messageDigest)
    else {
      return nil
    }
    var valueReader = DerReader(encodedAttributes, within: values)
    guard
      let value = valueReader.next(),
      value.tag == DerValues.tagOctetString,
      valueReader.isAtEnd
    else {
      return nil
    }
    let digest = valueReader.contentData(of: value)
    return digest.count == digestAlgorithm.byteCount ? digest : nil
  }

  /// Whether the signature has the exact profile-required wire shape.
  private static func hasValidShape(
    _ signature: Data,
    profile: CardKeyProfile
  ) -> Bool {
    switch profile {
    case .ecdsaP256, .ecdsaP384:
      Self.isEcdsaSignatureValue(signature)

    case .rsa2048, .rsa3072:
      signature.count == profile.rawSignatureLength
    }
  }

  /// Whether a value is exactly one canonical X9.62 ECDSA `(r, s)` pair.
  private static func isEcdsaSignatureValue(_ signature: Data) -> Bool {
    var outer = DerReader(signature)
    guard
      let sequence = outer.next(),
      sequence.tag == DerValues.tagSequence,
      outer.isAtEnd
    else {
      return false
    }
    var components = DerReader(signature, within: sequence)
    guard
      let first = components.next(), first.tag == DerValues.tagInteger,
      let second = components.next(), second.tag == DerValues.tagInteger,
      components.isAtEnd
    else {
      return false
    }
    let firstValue = components.contentData(of: first)
    let secondValue = components.contentData(of: second)
    guard
      Self.isCanonicalPositiveInteger(firstValue),
      Self.isCanonicalPositiveInteger(secondValue)
    else {
      return false
    }
    return signature
      == DerEncoder.sequence([
        DerEncoder.unsignedInteger(firstValue),
        DerEncoder.unsignedInteger(secondValue),
      ])
  }

  /// Whether bytes are one minimal, positive, nonzero DER INTEGER value.
  private static func isCanonicalPositiveInteger(_ bytes: Data) -> Bool {
    guard let first = bytes.first, bytes.contains(where: { $0 != 0 }) else {
      return false
    }
    guard first & DerValues.signBitMask == 0 else { return false }
    guard bytes.count > 1, first == 0 else { return true }
    let second = bytes[bytes.index(after: bytes.startIndex)]
    return second & DerValues.signBitMask != 0
  }

  /// Verifies the exact stored value over the exact signed attributes.
  private static func verify(
    _ signature: Data,
    over attributes: Data,
    with certificate: SecCertificate,
    profile: CardKeyProfile,
    digestAlgorithm: DocumentDigestAlgorithm
  ) throws {
    guard let publicKey = SecCertificateCopyKey(certificate) else {
      throw AssemblyError.certificateUnparseable
    }
    let algorithm = digestAlgorithm.verificationAlgorithm(for: profile)
    let digest = digestAlgorithm.hash(attributes)
    var error: Unmanaged<CFError>?
    guard
      SecKeyVerifySignature(
        publicKey,
        algorithm,
        digest as CFData,
        signature as CFData,
        &error
      )
    else {
      throw AssemblyError.signatureMalformed
    }
  }
}
