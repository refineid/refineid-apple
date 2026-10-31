// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation
import Security

/// Verifies the one SignerInfo of a detached CMS SignedData found in a
/// PDF, whoever made it (RFC 5652 section 5; EN 319 142-1 clause 6.3;
/// EN 319 142-2 clause 4.2.3).
///
/// Digests are SHA-256, SHA-384 or SHA-512; MD5, SHA-1 and any other
/// digest make the signature unsupported. RSASSA-PKCS1-v1_5 with an
/// RSA key of at least 2048 bits and ECDSA over P-256 or P-384 are
/// verified; a signature algorithm whose hash differs from the digest
/// algorithm is unsupported, and one that does not fit the key is not
/// valid.
internal enum CmsSignerVerification {
  /// The facts of one verified SignerInfo.
  internal struct Outcome {
    /// The signer certificate.
    internal let signerCertificate: Data

    /// Every certificate the SignedData carries.
    internal let embeddedCertificates: [Data]

    /// Whether the message-digest attribute equals the digest of the
    /// signed octets.
    internal let documentIntact: Bool

    /// Whether the signed attributes are well formed for the profile
    /// and the signature verifies over them under the signer's key.
    internal let signatureValid: Bool

    /// The SignerInfo's signature value contents.
    internal let signatureValue: Data

    /// The signature-time-stamp tokens among the unsigned attributes.
    internal let timestampTokens: [Data]
  }

  /// What the subfilter requires of the signed attributes.
  internal struct Profile {
    /// Whether an ESS signing-certificate attribute must bind the
    /// signer (`ETSI.CAdES.detached`).
    internal let requiresSigningCertificate: Bool

    /// Whether a signing-time attribute makes the signature not valid
    /// (`ETSI.CAdES.detached`, EN 319 142-1 clause 6.3).
    internal let forbidsSigningTime: Bool
  }

  /// The SignerInfo fields, each parsed once (RFC 5652 section 5.3).
  internal struct SignerFields {
    internal let identifier: SignerIdentifier
    internal let digest: Digest
    internal let scheme: SignatureScheme
    internal let signedAttributes: DerReader.Element
    internal let signatureValue: Data
    internal let unsignedAttributes: DerReader.Element?
  }

  /// The SignerIdentifier choice (RFC 5652 section 5.3).
  internal enum SignerIdentifier {
    /// The issuer Name and the serial magnitude.
    case issuerAndSerialNumber(issuer: Data, serial: Data)

    /// The subjectKeyIdentifier value.
    case subjectKeyIdentifier(Data)

    /// Whether `certificate` is the one this identifier names: equal
    /// issuer and serial, or an equal subjectKeyIdentifier.
    internal func names(_ certificate: Data) -> Bool {
      switch self {
      case .issuerAndSerialNumber(let issuer, let serial):
        guard
          let facts = CertificateFacts(der: certificate),
          let magnitude = try? CertificateRevocationList.unsignedIntegerContent(
            facts.serialNumber)
        else {
          return false
        }
        return facts.issuerName == issuer && magnitude == serial

      case .subjectKeyIdentifier(let identifier):
        return TimestampCmsVerifier.subjectKeyIdentifier(in: certificate) == identifier
      }
    }
  }

  /// The smallest RSA modulus accepted, in bits.
  internal static let minimumRsaKeyBits = 2_048

  /// The P-256 key size, in bits.
  internal static let p256KeyBits = 256

  /// The P-384 key size, in bits.
  internal static let p384KeyBits = 384

  /// The EC key sizes accepted.
  internal static let acceptedEcKeyBits: Set<Int> = [p256KeyBits, p384KeyBits]

  /// The SignerInfo of `cms` verified over `signedOctets`, or nil when
  /// the verifier cannot judge it: a structure it does not read, an
  /// unsupported digest or signature algorithm, a key outside the
  /// accepted ones, no content-type attribute, or no carried signer.
  internal static func verify(
    cms: Data,
    signedOctets: Data,
    profile: Profile
  ) -> Outcome? {
    guard let signer = Self.signerFields(in: cms) else { return nil }
    let digest = signer.digest
    let scheme = signer.scheme
    let attributes = SignedAttributes(cms, element: signer.signedAttributes)
    guard attributes.contentTypeCount > 0 else { return nil }
    let embedded = CmsCertificates.inside(cms)
    guard
      let signerCertificate = Self.signerCertificate(
        among: embedded, cms: cms, identifier: signer.identifier, attributes: attributes),
      let certificate = SecCertificateCreateWithData(nil, signerCertificate as CFData),
      let key = SecCertificateCopyKey(certificate),
      let family = KeyFamily(key)
    else {
      return nil
    }
    let messageDigest = attributes.messageDigest(byteCount: digest.byteCount)
    let attributesWellFormed =
      messageDigest != nil
      && attributes.contentTypeIsData
      && (attributes.hasSigningCertificate || !profile.requiresSigningCertificate)
      && !(attributes.hasSigningTime && profile.forbidsSigningTime)
    let signatureVerifies =
      scheme.family == family
      && Self.verifies(
        signer.signatureValue,
        over: attributes.signedSet,
        key: key,
        algorithm: scheme.algorithm
      )
    return Outcome(
      signerCertificate: signerCertificate,
      embeddedCertificates: embedded,
      documentIntact: messageDigest == digest.hash(signedOctets),
      signatureValid: attributesWellFormed && signatureVerifies,
      signatureValue: signer.signatureValue,
      timestampTokens: attributes.timestampTokens(
        in: cms, unsigned: signer.unsignedAttributes)
    )
  }

  /// The signer: the carried certificate the SignerIdentifier names,
  /// and, when an ESS signing-certificate attribute is present, the one
  /// it binds as well; nil when no carried certificate is both.
  private static func signerCertificate(
    among embedded: [Data],
    cms: Data,
    identifier: SignerIdentifier,
    attributes: SignedAttributes
  ) -> Data? {
    embedded.first { candidate in
      identifier.names(candidate)
        && (!attributes.hasSigningCertificate
          || (try? CmsSigningCertificate.verify(token: cms, certificate: candidate)) != nil)
    }
  }

  /// Whether `signature` verifies over the digest of `signedSet`.
  private static func verifies(
    _ signature: Data,
    over signedSet: Data,
    key: SecKey,
    algorithm: SecKeyAlgorithm
  ) -> Bool {
    var error: Unmanaged<CFError>?
    let verified = SecKeyVerifySignature(
      key, algorithm, signedSet as CFData, signature as CFData, &error
    )
    _ = error?.takeRetainedValue()
    return verified
  }
}
