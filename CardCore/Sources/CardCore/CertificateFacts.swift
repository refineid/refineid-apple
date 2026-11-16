// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import Foundation

/// The certificate fields chain-building and revocation need
/// (RFC 5280).
///
/// Read straight from the DER rather than through the platform's
/// certificate API, because what an OCSP responder compares is the
/// exact encoded issuer Name and the exact serialNumber octets, and a
/// re-encoding of either produces hashes that match nothing.
public struct CertificateFacts {
  /// The issuer Name, exactly as encoded in this certificate.
  public let issuerName: Data

  /// The subject Name, exactly as encoded.
  public let subjectName: Data

  /// The serialNumber value octets, without the tag or length.
  public let serialNumber: Data

  /// The subjectPublicKey bit string's bits, without the unused-bits
  /// octet - what an OCSP CertID hashes.
  public let publicKeyBits: Data

  /// The SubjectKeyIdentifier octets, when the certificate carries one
  /// valid non-critical SubjectKeyIdentifier extension (RFC 5280
  /// section 4.2.1.2).
  public let subjectKeyIdentifier: Data?

  /// Where the issuer's certificate can be fetched (AIA caIssuers).
  public let issuerCertificateUrls: [String]

  /// Where this certificate's status can be asked (AIA OCSP).
  public let ocspUrls: [String]

  /// Where a full certificate revocation list can be fetched.
  public let crlUrls: [String]

  /// Whether the certificate has one critical extended-key-usage
  /// extension containing only id-kp-timeStamping (RFC 3161 section
  /// 2.3).
  public let hasTimestampingExtendedKeyUsage: Bool

  /// The basic-constraints verdict used to keep timestamp signers from
  /// acting as certification authorities.
  internal let basicConstraints: BasicConstraints

  /// The KeyUsage verdict used for timestamp-signature authorization.
  internal let timestampingKeyUsage: TimestampingKeyUsage

  /// Whether issuer and subject names are identical.
  ///
  /// This is only a structural self-issued fact. A chain walker must still
  /// authenticate the self-signature and apply its explicit trust policy.
  public var isSelfIssued: Bool {
    issuerName == subjectName
  }

  /// Whether the certificate asserts it is an authority.
  ///
  /// The status window uses this to pass over the issuer published
  /// beside the card's own leaves when naming the holder.
  public var isCertificateAuthority: Bool {
    basicConstraints == .certificateAuthority
  }

  /// Whether this certificate has the non-trust profile required of an
  /// RFC 3161 signer.
  ///
  /// Anchor selection must not relax these leaf rules.
  internal var isPermittedTimestampSigner: Bool {
    self.hasTimestampingExtendedKeyUsage
      && self.basicConstraints.isPermittedTimestampSigner
      && self.timestampingKeyUsage.isPermittedTimestampSigner
  }

  /// Reads what is needed, or nil when the certificate does not parse
  /// as far as those fields.
  public init?(der: Data) {
    var outer = DerReader(der)
    guard
      let certificate = outer.next(),
      certificate.tag == DerValues.tagSequence
    else {
      return nil
    }
    var certificateReader = DerReader(der, within: certificate)
    guard let tbs = certificateReader.next() else { return nil }
    var reader = DerReader(der, within: tbs)
    guard var element = reader.next() else { return nil }
    if element.tag == DerValues.tagContext0Constructed {
      guard let following = reader.next() else { return nil }
      element = following
    }
    guard element.tag == DerValues.tagInteger else { return nil }
    self.serialNumber = reader.contentData(of: element)
    guard
      reader.next() != nil,
      let issuer = reader.next(),
      reader.next() != nil,
      let subject = reader.next(),
      let publicKeyInfo = reader.next()
    else {
      return nil
    }
    self.issuerName = reader.data(of: issuer)
    self.subjectName = reader.data(of: subject)
    guard let bits = Self.keyBits(of: publicKeyInfo, in: der) else {
      return nil
    }
    self.publicKeyBits = bits
    let extensions = Self.extensionFacts(in: der, reader: &reader)
    self.subjectKeyIdentifier = extensions.subjectKeyIdentifier.octets
    self.issuerCertificateUrls = extensions.issuers
    self.ocspUrls = extensions.responders
    self.crlUrls = extensions.revocationLists
    self.hasTimestampingExtendedKeyUsage = extensions.timestampingUsage == .valid
    self.basicConstraints = extensions.basicConstraints
    self.timestampingKeyUsage = extensions.timestampingKeyUsage
  }

  /// The subjectPublicKey bits, dropping the unused-bits count.
  private static func keyBits(
    of publicKeyInfo: DerReader.Element,
    in der: Data
  ) -> Data? {
    var reader = DerReader(der, within: publicKeyInfo)
    guard
      reader.next() != nil,
      let bitString = reader.next(),
      bitString.tag == DerValues.tagBitString
    else {
      return nil
    }
    let content = reader.contentData(of: bitString)
    guard !content.isEmpty else { return nil }
    return content.dropFirst()
  }
}
