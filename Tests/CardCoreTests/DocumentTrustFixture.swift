// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CryptoKit
  import Foundation
  import Security
  import Testing

  @testable import CardCore

  /// A synthetic three-level hierarchy, root, issuing CA and signer,
  /// and PAdES documents signed under it.
  internal struct DocumentTrustFixture {
    /// What one signed fixture document carries.
    internal struct Contents {
      /// Certificates in the CMS besides the signer's own.
      internal var cmsCertificates: [Data] = []

      /// CRLs in the CMS RevocationInfoChoices.
      internal var cmsRevocationLists: [Data] = []

      /// Certificates in the document security store.
      internal var storeCertificates: [Data] = []

      /// CRLs in the document security store.
      internal var storeRevocationLists: [Data] = []

      /// OCSP responses in the document security store.
      internal var storeOcspResponses: [Data] = []

      /// Signature timestamp generation times, minted by `authority`.
      internal var timestampTimes: [String] = []

      /// Whether the ESS signing-certificate attribute is left out.
      internal var omitsSigningCertificate = false

      /// Whether a signing-time attribute is signed.
      internal var carriesSigningTime = false

      /// A subfilter name, as long as the one the signer writes, written
      /// in its place.
      internal var subFilter: String?

      /// A certificate the ESS signing-certificate attribute names in
      /// place of the signer.
      internal var boundCertificate: Data?

      /// A serial the SignerIdentifier names in place of the signer's.
      internal var identifierSerial: Data?

      /// Whether the content-type attribute carries id-data twice.
      internal var duplicatesContentTypeValue = false

      /// Whether the EncapsulatedContentInfo carries eContent.
      internal var encapsulatesContent = false
    }

    /// The fields of one hierarchy certificate.
    private struct CertificateFields {
      let commonName: String
      let issuer: Data
      let serial: Data
      let authority: Bool
    }

    /// The subfilter the incremental signer writes.
    internal static let writtenSubFilter = "/ETSI.CAdES.detached"

    /// The common name of the synthetic root.
    private static let rootCommonName = "RefineID Verifier Test Root"

    /// The common name of the synthetic signer.
    internal static let signerCommonName = "RefineID Verifier Test Signer"

    /// The common name of the synthetic root.
    internal static var rootName: String { rootCommonName }

    /// The serial of the root certificate.
    private static let rootSerial = Data("r".utf8)

    /// The serial of the issuing CA certificate.
    internal static let issuingSerial = Data("i".utf8)

    /// Content a detached signature never encapsulates.
    internal static let encapsulatedContent = Data("encapsulated".utf8)

    /// The signing time a signing-time attribute states.
    internal static let signingTime = "20260515000000Z"

    /// The self-signed root.
    internal let root: Data

    /// The issuing CA, issued by the root.
    internal let issuing: Data

    /// The signer, issued by the issuing CA.
    internal let signer: QualifiedDocumentCmsTests.Identity

    /// The issuing CA's key, which signs CRLs and OCSP responses over
    /// the signer.
    internal let issuingKey: SecKey

    /// The root's key, which signs CRLs over the issuing CA.
    internal let rootKey: SecKey

    /// The signer certificate's serial.
    internal let signerSerial: Data

    /// The key and signature kind every certificate of the hierarchy uses.
    internal let kind: CertificateRevocationListFixtures.SignatureKind

    /// The time-stamp authority every timestamp is minted by.
    internal let authority: SyntheticTimestampAuthority

    /// Creates a fresh P-256 hierarchy and authority.
    internal init() throws {
      try self.init(
        kind: .ecdsaSha256, signerKey: nil,
        signerSerial: CertificateRevocationListFixtures.targetSerial)
    }

    /// Creates a fresh P-256 hierarchy whose signer has `signerSerial`.
    internal init(signerSerial: Data) throws {
      try self.init(kind: .ecdsaSha256, signerKey: nil, signerSerial: signerSerial)
    }

    /// Creates a fresh RSA hierarchy whose signer key has `signerBits`.
    internal init(rsaSignerBits signerBits: Int) throws {
      let attributes: [CFString: Any] = [
        kSecAttrKeyType: kSecAttrKeyTypeRSA,
        kSecAttrKeySizeInBits: signerBits,
      ]
      var error: Unmanaged<CFError>?
      let key = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
      try self.init(
        kind: .rsaSha256, signerKey: key,
        signerSerial: CertificateRevocationListFixtures.targetSerial)
    }

    /// Creates a fresh hierarchy of `kind`, with `signerKey` when given.
    private init(
      kind: CertificateRevocationListFixtures.SignatureKind,
      signerKey givenSignerKey: SecKey?,
      signerSerial: Data
    ) throws {
      let rootSigningKey = try CertificateRevocationListFixtures.makeKey(for: kind)
      let caKey = try CertificateRevocationListFixtures.makeKey(for: kind)
      let signingKey = try givenSignerKey ?? CertificateRevocationListFixtures.makeKey(for: kind)
      let rootIssuerName = CertificateRevocationListFixtures.name(Self.rootCommonName)
      root = try Self.certificate(
        CertificateFields(
          commonName: Self.rootCommonName, issuer: rootIssuerName, serial: Self.rootSerial,
          authority: true),
        key: rootSigningKey, signer: rootSigningKey, kind: kind)
      issuing = try Self.certificate(
        CertificateFields(
          commonName: CertificateRevocationListFixtures.issuerCommonName, issuer: rootIssuerName,
          serial: Self.issuingSerial, authority: true),
        key: caKey, signer: rootSigningKey, kind: kind)
      let signerCertificate = try Self.certificate(
        CertificateFields(
          commonName: Self.signerCommonName,
          issuer: CertificateRevocationListFixtures.name(
            CertificateRevocationListFixtures.issuerCommonName),
          serial: signerSerial, authority: false),
        key: signingKey, signer: caKey, kind: kind)
      signer = QualifiedDocumentCmsTests.Identity(
        certificate: signerCertificate,
        privateKey: signingKey,
        profile: kind == .rsaSha256 ? .rsa2048 : .ecdsaP256
      )
      issuingKey = caKey
      rootKey = rootSigningKey
      self.signerSerial = signerSerial
      self.kind = kind
      authority = try SyntheticTimestampAuthority()
    }

    /// One certificate of the hierarchy.
    private static func certificate(
      _ issue: CertificateFields,
      key: SecKey,
      signer: SecKey,
      kind: CertificateRevocationListFixtures.SignatureKind
    ) throws -> Data {
      try CertificateRevocationListFixtures.certificate(
        description: .init(
          allowsCrlSigning: issue.authority,
          includesKeyUsage: true,
          malformedKeyUsage: false,
          commonName: issue.commonName,
          isCertificateAuthority: issue.authority,
          issuerName: issue.issuer,
          serial: issue.serial
        ),
        publicKey: key, signer: signer, kind: kind
      )
    }

    /// The instant one GeneralizedTime names.
    internal static func instant(_ generalizedTime: String) throws -> Date {
      try #require(SyntheticTimestampAuthority.instant(generalizedTime))
    }

    /// The one judged report of `document`.
    internal static func report(
      _ document: Data,
      anchors: TrustAnchors,
      now: Date
    ) throws -> DocumentVerification.SignatureReport {
      let report = try DocumentVerification.verify(
        document: document, anchors: anchors, now: now
      )
      try #require(report.signatures.count == 1)
      guard case .judged(let signature) = report.signatures[0] else {
        Issue.record("The signature was not judged")
        throw CertificateRevocationListFixtures.FixtureFailure.signatureCreation
      }
      return signature
    }

    /// Anchors naming the root, and the authority when `anchorsAuthority`.
    internal func anchors(anchorsAuthority: Bool) -> TrustAnchors {
      TrustAnchors(
        certificateIssuing: [root],
        timeStamping: anchorsAuthority ? [authority.certificate] : []
      )
    }

    /// The minimal PDF signed by the signer, carrying `contents`.
    internal func document(_ contents: Contents) throws -> Data {
      var placeholder = try QualifiedDocumentCmsTests.placeholder()
      if let subFilter = contents.subFilter {
        placeholder = try Self.replacingSubFilter(in: placeholder, with: subFilter, after: 0)
      }
      let signed = try placeholder.filled(with: try self.cms(over: placeholder, contents))
      let material = PdfValidationStore.Material(
        certificates: contents.storeCertificates,
        ocspResponses: contents.storeOcspResponses,
        revocationLists: contents.storeRevocationLists
      )
      return try PdfValidationStore.appended(to: signed, material: material)
    }

  }

#endif
