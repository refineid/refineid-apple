// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security

/// Portable authentication of the CMS envelope around one RFC 3161 TSTInfo.
///
/// CryptoTokenKit's historical `CMSDecoder` is not available on iOS. This
/// verifier deliberately walks the small CMS subset used by timestamp tokens
/// and hands only the final public-key operation to Security. The signed
/// attributes are verified in their exact DER SET encoding, never rebuilt.
internal enum TimestampCmsVerifier {
  // MARK: Nested Types

  /// The CMS state needed by the timestamp certificate-policy verifier.
  internal struct Authenticated {
    internal let signerCertificate: Data
    internal let embeddedCertificates: [Data]
    internal let trust: SecTrust
  }

  /// Authenticates the sole signer and exact encapsulated content.
  ///
  /// `additionalCertificates` join the token's own as path candidates.
  internal static func authenticate(
    token: Data,
    expectedContent: Data,
    additionalCertificates: [Data]
  ) throws -> Authenticated {
    let layout = try Self.layout(in: token)
    guard layout.content == expectedContent else {
      throw TimestampTokenVerifier.Failure.malformed
    }
    let signer = try Self.signer(in: token, element: layout.signerInfo)
    guard layout.digest == signer.digest else {
      throw TimestampTokenVerifier.Failure.malformed
    }
    try Self.verifySignedAttributes(
      in: token,
      element: signer.signedAttributes,
      digest: signer.digest,
      content: expectedContent
    )

    let embedded = CmsCertificates.inside(token)
    guard !embedded.isEmpty else {
      throw TimestampTokenVerifier.Failure.signerCertificateMissing
    }
    let (signerData, signerCertificate) = try Self.resolveSigner(
      signer.identifier, in: token, embedded: embedded
    )
    try Self.verifySignature(signer, in: token, with: signerCertificate)
    return try Self.trust(
      signerData: signerData,
      embedded: embedded,
      additional: additionalCertificates
    )
  }

  /// Finds the embedded certificate the signer identifier names.
  private static func resolveSigner(
    _ identifier: DerReader.Element,
    in token: Data,
    embedded: [Data]
  ) throws -> (signerData: Data, signerCertificate: SecCertificate) {
    guard
      let signerData = embedded.first(where: { candidate in
        Self.identifier(identifier, in: token, matches: candidate)
      }),
      let signerCertificate = SecCertificateCreateWithData(
        nil, signerData as CFData
      )
    else {
      throw TimestampTokenVerifier.Failure.signerCertificateMissing
    }
    return (signerData, signerCertificate)
  }

  /// Verifies the signature over the DER SET-encoded signed attributes.
  private static func verifySignature(
    _ signer: Signer, in token: Data, with signerCertificate: SecCertificate
  ) throws {
    let attributes = DerEncoder.retagged(
      Self.data(of: signer.signedAttributes, in: token),
      to: DerValues.tagSet
    )
    guard
      CertificateRevocationList.signatureIsValid(
        signer.signature,
        over: attributes,
        with: signerCertificate,
        algorithm: signer.signatureAlgorithm
      )
    else {
      throw TimestampTokenVerifier.Failure.invalidSignature
    }
  }

  /// Builds the timestamp policy trust with the signer first.
  private static func trust(
    signerData: Data, embedded: [Data], additional: [Data]
  ) throws -> Authenticated {
    let certificates = [signerData] + embedded.filter { $0 != signerData }
    let parsed = certificates.compactMap { certificate in
      SecCertificateCreateWithData(nil, certificate as CFData)
    }
    // Additional candidates the platform does not parse are left out.
    let candidates = additional.filter { candidate in !certificates.contains(candidate) }
      .compactMap { candidate in SecCertificateCreateWithData(nil, candidate as CFData) }
    guard
      parsed.count == certificates.count,
      let policy = SecPolicyCreateWithProperties(
        kSecPolicyAppleTimeStamping, nil
      )
    else {
      throw TimestampTokenVerifier.Failure.malformed
    }
    var created: SecTrust?
    guard
      SecTrustCreateWithCertificates(
        (parsed + candidates) as CFArray, policy, &created
      ) == errSecSuccess,
      let trust = created
    else {
      throw TimestampTokenVerifier.Failure.signerCertificateMissing
    }
    return Authenticated(
      signerCertificate: signerData,
      embeddedCertificates: embedded,
      trust: trust
    )
  }

  /// Requires content-type and message-digest exactly once in canonical DER.
  private static func verifySignedAttributes(
    in token: Data,
    element: DerReader.Element,
    digest: Digest,
    content: Data
  ) throws {
    var reader = DerReader(token, within: element)
    var previous: Data?
    var contentTypeCount = 0
    var messageDigestCount = 0
    while let attribute = reader.next() {
      guard attribute.tag == DerValues.tagSequence else {
        throw TimestampTokenVerifier.Failure.malformed
      }
      let raw = reader.data(of: attribute)
      if let previous, !previous.lexicographicallyPrecedes(raw) {
        throw TimestampTokenVerifier.Failure.malformed
      }
      previous = raw
      var fields = DerReader(token, within: attribute)
      guard
        let oid = fields.next(), oid.tag == DerValues.tagObjectIdentifier,
        let values = fields.next(), values.tag == DerValues.tagSet,
        fields.isAtEnd
      else { throw TimestampTokenVerifier.Failure.malformed }
      let identifier = fields.data(of: oid)
      if identifier == DerEncoder.objectIdentifier(SignOids.contentType) {
        contentTypeCount += 1
        var value = DerReader(token, within: values)
        guard
          let type = value.next(),
          value.data(of: type) == DerEncoder.objectIdentifier(SignOids.tstInfo),
          value.isAtEnd
        else { throw TimestampTokenVerifier.Failure.malformed }
      } else if identifier == DerEncoder.objectIdentifier(SignOids.messageDigest) {
        messageDigestCount += 1
        var value = DerReader(token, within: values)
        guard
          let octets = value.next(), octets.tag == DerValues.tagOctetString,
          value.isAtEnd,
          ConstantTimeComparison.equal(
            value.contentData(of: octets), digest.hash(content)
          )
        else { throw TimestampTokenVerifier.Failure.invalidSignature }
      }
    }
    guard
      reader.isAtEnd,
      contentTypeCount == 1,
      messageDigestCount == 1
    else { throw TimestampTokenVerifier.Failure.malformed }
  }

  internal static func data(
    of element: DerReader.Element,
    in encoded: Data
  ) -> Data {
    let reader = DerReader(encoded)
    return reader.data(of: element)
  }

}
