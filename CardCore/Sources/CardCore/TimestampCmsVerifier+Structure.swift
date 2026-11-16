// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

extension TimestampCmsVerifier {
  // MARK: Nested Types

  /// One parsed signer and the exact values its signature covers.
  internal struct Signer {
    internal let identifier: DerReader.Element
    internal let digest: Digest
    internal let signedAttributes: DerReader.Element
    internal let signatureAlgorithm: SecKeyAlgorithm
    internal let signature: Data
  }

  /// The SignedData fields used by one timestamp token.
  internal struct Layout {
    internal let digest: Digest
    internal let content: Data
    internal let signerInfo: DerReader.Element
  }

  // MARK: Static Functions

  /// Parses the complete ContentInfo and requires one digest and one signer.
  internal static func layout(in token: Data) throws -> Layout {
    guard let signedData = CmsSignedData(in: token) else {
      throw TimestampTokenVerifier.Failure.malformed
    }
    let digest = try Self.soleDigest(in: token, set: signedData.digestAlgorithms)
    guard
      let content = signedData.attachedOctetString(
        contentType: SignOids.tstInfo,
        in: token
      ),
      let signer = signedData.soleSignerInfoElement(in: token)
    else {
      throw TimestampTokenVerifier.Failure.malformed
    }
    return Layout(digest: digest, content: content, signerInfo: signer)
  }

  /// Parses one complete SignerInfo and rejects trailing fields.
  internal static func signer(
    in token: Data,
    element: DerReader.Element
  ) throws -> Signer {
    guard let fields = CmsSignedData.signerFields(of: element, in: token) else {
      throw TimestampTokenVerifier.Failure.malformed
    }
    let digest = try Self.digest(in: token, identifier: fields.digestAlgorithm)
    let signatureAlgorithm = try Self.signatureAlgorithm(
      in: token,
      identifier: fields.signatureAlgorithm,
      digest: digest
    )
    return Signer(
      identifier: fields.identifier,
      digest: digest,
      signedAttributes: fields.signedAttributes,
      signatureAlgorithm: signatureAlgorithm,
      signature: fields.signatureValue
    )
  }

  /// Requires exactly one SignedData digest identifier.
  private static func soleDigest(
    in token: Data,
    set: DerReader.Element
  ) throws -> Digest {
    var reader = DerReader(token, within: set)
    guard let identifier = reader.next(), reader.isAtEnd else {
      throw TimestampTokenVerifier.Failure.malformed
    }
    return try Self.digest(in: token, identifier: identifier)
  }

  /// Parses a SHA-2 AlgorithmIdentifier with absent or NULL parameters.
  internal static func digest(
    in encoded: Data,
    identifier: DerReader.Element
  ) throws -> Digest {
    guard identifier.tag == DerValues.tagSequence else {
      throw TimestampTokenVerifier.Failure.malformed
    }
    var reader = DerReader(encoded, within: identifier)
    guard let oid = reader.next(), oid.tag == DerValues.tagObjectIdentifier else {
      throw TimestampTokenVerifier.Failure.malformed
    }
    if let parameters = reader.next() {
      guard
        parameters.tag == DerValues.tagNull,
        parameters.content.isEmpty
      else { throw TimestampTokenVerifier.Failure.invalidSignature }
    }
    guard reader.isAtEnd else {
      throw TimestampTokenVerifier.Failure.malformed
    }
    switch reader.data(of: oid) {
    case DerEncoder.objectIdentifier(SignOids.sha256):
      return .sha256

    case DerEncoder.objectIdentifier(SignOids.sha384):
      return .sha384

    case DerEncoder.objectIdentifier(SignOids.sha512):
      return .sha512

    default:
      throw TimestampTokenVerifier.Failure.invalidSignature
    }
  }
}
