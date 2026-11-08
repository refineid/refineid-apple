// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CryptoKit
  import Foundation
  import Testing

  @testable import CardCore

  /// The baseline level the verifier reports, from what it established
  /// (EN 319 142-1 and EN 319 132-1, clause 6).
  @Suite
  internal struct SignatureLevelTests {
    /// What one ASiC-E container under the fixture hierarchy carries.
    private struct AsicContents {
      var timestamped = true
      var validationData = true
      var archive = Archive.taken
    }

    /// The archive timestamp of an ASiC-E container.
    private enum Archive {
      /// None is taken.
      case absent

      /// One is taken over the archive input.
      case taken

      /// One is taken over other input.
      case unrelated
    }

    /// Inside every certificate's and CRL's validity.
    private static let currentTime = "20260601000000Z"

    /// The signature timestamp's generation time.
    internal static let signatureStampTime = "20260515000000Z"

    /// The archive or document timestamp's generation time, after it.
    private static let archiveStampTime = "20260520000000Z"

    /// A SHA-384 imprint over input that is not the archive input.
    private static let unrelatedImprint = Data(
      SHA384.hash(data: Data("input that is not the archive input".utf8)))

    /// The RSA key size of the ASiC-E signer, a size the XML-form
    /// helper signs with.
    private static let asicSignerBits = 2_048

    /// The unsigned signature properties' end tag, before which an
    /// archive timestamp is placed.
    private static let unsignedSignaturePropertiesClose = "</xades:UnsignedSignatureProperties>"

    internal static func now() throws -> Date {
      try DocumentTrustFixture.instant(Self.currentTime)
    }

    /// The CRLs that answer the fixture's whole path.
    internal static func pathRevocationLists(_ fixture: DocumentTrustFixture) throws -> [Data] {
      [
        try fixture.revocationList(revoking: false),
        try fixture.rootRevocationList(revoking: false),
      ]
    }

    /// The fixture's PDF, with a signature timestamp when `timestamped`
    /// and the path's CRLs in the document security store when `stored`.
    private static func pdf(
      _ fixture: DocumentTrustFixture,
      timestamped: Bool,
      stored: Bool
    ) throws -> Data {
      try fixture.document(
        .init(
          cmsCertificates: [fixture.issuing],
          storeCertificates: stored ? [fixture.authority.certificate] : [],
          storeRevocationLists: stored ? Self.pathRevocationLists(fixture) : [],
          timestampTimes: timestamped ? [Self.signatureStampTime] : []
        ))
    }

    /// `document` with an anchored document timestamp revision.
    internal static func documentStamped(
      _ document: Data,
      _ fixture: DocumentTrustFixture
    ) throws -> Data {
      let revision = try PdfIncrementalSigner.prepare(document, revision: .documentTimestamp)
      let token = try fixture.authority.token(
        imprint: revision.digest(.sha384), generalizedTime: Self.archiveStampTime)
      return try revision.filled(with: token)
    }

    /// An ASiC-E container our writer produces under the fixture's
    /// signer, carrying `contents`.
    private static func container(
      _ fixture: DocumentTrustFixture,
      _ contents: AsicContents
    ) throws -> Data {
      let identity = fixture.signer
      let objects = AsicVerificationTests.sampleObjects()
      let plan = try #require(
        XadesSignature.plan(
          objects: objects,
          certificate: identity.certificate,
          profile: identity.profile,
          signedAt: AsicVerificationTests.signedAt
        ))
      let signature = try AsicVerificationTests.xmlSignature(
        over: plan.signedInfo, identity: identity, profile: identity.profile)
      let tokens =
        contents.timestamped
        ? [
          try fixture.authority.token(
            imprint: XadesSignature.timestampDigest(signature),
            generalizedTime: Self.signatureStampTime)
        ] : []
      let material = PdfValidationStore.Material(
        certificates: contents.validationData
          ? [fixture.issuing, fixture.authority.certificate] : [],
        ocspResponses: [],
        revocationLists: contents.validationData ? try Self.pathRevocationLists(fixture) : []
      )
      let archiveToken: Data?
      switch contents.archive {
      case .absent:
        archiveToken = nil

      case .taken:
        archiveToken = try fixture.authority.token(
          imprint: plan.archiveTimestampDigest(
            xmlSignature: signature, timestampTokens: tokens, material: material),
          generalizedTime: Self.archiveStampTime)

      case .unrelated:
        archiveToken = try fixture.authority.token(
          imprint: Self.unrelatedImprint, generalizedTime: Self.archiveStampTime)
      }
      let document = plan.document(
        xmlSignature: signature,
        timestampTokens: tokens,
        material: material,
        archiveTimestampToken: archiveToken
      )
      return try #require(AsicContainer.container(objects: objects, signatureXml: document))
    }

    /// The one report of `document` under the fixture's root and
    /// authority.
    internal static func anchoredReport(
      _ document: Data,
      _ fixture: DocumentTrustFixture
    ) throws -> DocumentVerification.SignatureReport {
      try Self.report(document, fixture)
    }

    private static func report(
      _ document: Data,
      _ fixture: DocumentTrustFixture,
      anchorsAuthority: Bool = true
    ) throws -> DocumentVerification.SignatureReport {
      try DocumentTrustFixture.report(
        document, anchors: fixture.anchors(anchorsAuthority: anchorsAuthority), now: Self.now())
    }

    /// A PDF climbs one level with each piece of evidence: a signature
    /// timestamp, the path's revocation values in the store, and a
    /// document timestamp over that store.
    @Test
    internal func pdfLevelsFollowTheEvidence() throws {
      let fixture = try DocumentTrustFixture()
      let basic = try Self.pdf(fixture, timestamped: false, stored: false)
      let timestamped = try Self.pdf(fixture, timestamped: true, stored: false)
      let longTerm = try Self.pdf(fixture, timestamped: true, stored: true)
      let archival = try Self.documentStamped(longTerm, fixture)

      #expect(try Self.report(basic, fixture).level == .basic)
      #expect(try Self.report(timestamped, fixture).level == .timestamped)
      #expect(try Self.report(longTerm, fixture).level == .longTerm)
      let report = try Self.report(archival, fixture)
      #expect(report.level == .longTermArchival)
      #expect(
        report.archiveTimestamps == [
          .anchored(try DocumentTrustFixture.instant(Self.archiveStampTime))
        ])
      #expect(report.isValid)
    }

    /// A document timestamp over a revision without stored revocation
    /// values proves existence but archives nothing.
    @Test
    internal func documentTimestampWithoutStoreIsNoArchive() throws {
      let fixture = try DocumentTrustFixture()
      let stamped = try Self.documentStamped(
        Self.pdf(fixture, timestamped: false, stored: false), fixture)

      let report = try Self.report(stamped, fixture)
      #expect(report.archiveTimestamps.isEmpty)
      #expect(report.level == .timestamped)
    }

    /// Revocation values carried only inside the CMS answer the path
    /// but are not the store B-LT keeps them in.
    @Test
    internal func revocationInsideTheCmsIsNotLongTerm() throws {
      let fixture = try DocumentTrustFixture()
      let document = try fixture.document(
        .init(
          cmsCertificates: [fixture.issuing],
          cmsRevocationLists: Self.pathRevocationLists(fixture),
          timestampTimes: [Self.signatureStampTime]
        ))

      let report = try Self.report(document, fixture)
      guard case .good = report.revocation else {
        Issue.record("The path was not answered")
        return
      }
      #expect(report.level == .timestamped)
    }

    /// A timestamp whose authority is not anchored proves nothing, so
    /// the signature stays at B-B.
    @Test
    internal func unanchoredTimestampLeavesBasic() throws {
      let fixture = try DocumentTrustFixture()
      let document = try Self.documentStamped(
        Self.pdf(fixture, timestamped: true, stored: true), fixture)

      let report = try Self.report(document, fixture, anchorsAuthority: false)
      #expect(report.level == .basic)
    }

    /// Our own B-LTA container is verified to B-LTA: the archive
    /// timestamp's input is recomputed from the signature file.
    @Test
    internal func asicArchiveTimestampIsRecomputed() throws {
      let fixture = try DocumentTrustFixture(rsaSignerBits: Self.asicSignerBits)
      let report = try Self.report(Self.container(fixture, AsicContents()), fixture)

      #expect(report.isValid)
      #expect(
        report.archiveTimestamps == [
          .anchored(try DocumentTrustFixture.instant(Self.archiveStampTime))
        ])
      #expect(report.level == .longTermArchival)
      #expect(
        report.proofOfExistence == (try DocumentTrustFixture.instant(Self.signatureStampTime)))
    }

    /// Each missing piece of evidence leaves the container one level
    /// lower.
    @Test
    internal func asicLevelsFollowTheEvidence() throws {
      let fixture = try DocumentTrustFixture(rsaSignerBits: Self.asicSignerBits)
      let longTerm = try Self.report(
        Self.container(fixture, AsicContents(archive: .absent)), fixture)
      let timestamped = try Self.report(
        Self.container(fixture, AsicContents(validationData: false, archive: .absent)), fixture)
      let basic = try Self.report(
        Self.container(
          fixture, AsicContents(timestamped: false, validationData: false, archive: .absent)),
        fixture)

      #expect(longTerm.level == .longTerm)
      #expect(timestamped.level == .timestamped)
      #expect(basic.level == .basic)
    }

    /// An archive timestamp over other input is invalid and archives
    /// nothing.
    @Test
    internal func asicArchiveOverOtherInputIsInvalid() throws {
      let fixture = try DocumentTrustFixture(rsaSignerBits: Self.asicSignerBits)
      let report = try Self.report(
        Self.container(fixture, AsicContents(archive: .unrelated)), fixture)

      #expect(report.archiveTimestamps == [.invalid])
      #expect(report.level == .longTerm)
      #expect(report.isValid)
    }

    /// An archive timestamp added after the one that was taken changes
    /// the input of neither: the first still verifies, and a second
    /// over other input is invalid.
    @Test
    internal func asicSecondArchiveTimestampIsJudgedOnItsOwn() throws {
      let fixture = try DocumentTrustFixture(rsaSignerBits: Self.asicSignerBits)
      let container = try Self.container(fixture, AsicContents())
      let entries = try ZipReader.open(container).entries
      let file = try #require(entries[AsicVerificationTests.signatureFileName])
      let text = try #require(String(data: file, encoding: .utf8))
      let token = try fixture.authority.token(
        imprint: Self.unrelatedImprint, generalizedTime: Self.archiveStampTime)
      let extra =
        XadesSignature.archiveTimeStampElement(token)
        .replacingOccurrences(
          of: "Id=\"\(XadesSignature.archiveTimestampId)\"",
          with: "Id=\"\(XadesSignature.archiveTimestampId)-second\"") + "\n"
      let range = try #require(text.range(of: Self.unsignedSignaturePropertiesClose))
      var edited = text
      edited.insert(contentsOf: extra, at: range.lowerBound)

      let report = try Self.report(
        AsicVerificationTests.container(document: edited), fixture)
      #expect(
        report.archiveTimestamps == [
          .anchored(try DocumentTrustFixture.instant(Self.archiveStampTime)), .invalid,
        ])
      #expect(report.level == .longTermArchival)
    }
  }

#endif
