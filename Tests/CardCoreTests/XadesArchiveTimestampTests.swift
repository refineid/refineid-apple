// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CryptoKit
  import Foundation
  import Testing

  @testable import CardCore

  /// The archive timestamp that makes a container XAdES-B-LTA
  /// (EN 319 132-1 V1.3.1 clause 5.5.2).
  ///
  /// The imprint is recomputed here from the written document, element
  /// by element, without the writer's own input builder: a writer that
  /// digests one thing and writes another is caught only that way.
  @Suite
  internal struct XadesArchiveTimestampTests {
    /// One finished B-LTA container and the document inside it.
    private struct Archived {
      let container: Data
      let document: String
    }

    /// Generation time of the signature timestamp.
    private static let signatureStampTime = "20260805100000Z"

    /// Generation time of the archive timestamp, after it.
    private static let archiveStampTime = "20260805100500Z"

    /// Names the file a run writes its sample container to; unset, a
    /// run writes nothing.
    private static let sampleOutputVariable = "REFINEID_LTA_SAMPLE_OUT"

    private static let archiveTimeStampName = "xadesv141:ArchiveTimeStamp"
    private static let signatureTimeStampName = "xades:SignatureTimeStamp"
    private static let certificateValuesName = "xades:CertificateValues"
    private static let revocationValuesName = "xades:RevocationValues"
    private static let unsignedSignaturePropertiesName = "xades:UnsignedSignatureProperties"
    private static let encapsulatedTimeStampName = "xades:EncapsulatedTimeStamp"
    private static let elementSeparator = "\n"
    private static let referenceUriPattern = ##"<ds:Reference [^>]*URI="([^"#][^"]*)""##

    /// The container our writer produces at B-LTA, with a real
    /// signature, a synthetic authority's two tokens, and a real CRL.
    private static func archived() throws -> Archived {
      let profile = CardKeyProfile.ecdsaP384
      let objects = AsicVerificationTests.sampleObjects()
      let identity = try QualifiedDocumentCmsTests.identity(profile)
      let plan = try #require(
        XadesSignature.plan(
          objects: objects,
          certificate: identity.certificate,
          profile: profile,
          signedAt: AsicVerificationTests.signedAt
        )
      )
      let signature = try AsicVerificationTests.xmlSignature(
        over: plan.signedInfo, identity: identity, profile: profile)
      let authority = try SyntheticTimestampAuthority()
      let signatureToken = try authority.token(
        imprint: XadesSignature.timestampDigest(signature),
        generalizedTime: Self.signatureStampTime)
      let revocation = try CertificateRevocationListFixtures.make(
        kind: .ecdsaSha256,
        options: .standard,
        targetSignedByWrongKey: false,
        issuerKeyUsage: .crlSigning
      )
      let material = PdfValidationStore.Material(
        certificates: [authority.certificate, revocation.issuerCertificate],
        ocspResponses: [],
        revocationLists: [revocation.crl]
      )
      let archiveToken = try authority.token(
        imprint: plan.archiveTimestampDigest(
          xmlSignature: signature, timestampTokens: [signatureToken], material: material),
        generalizedTime: Self.archiveStampTime)
      let document = plan.document(
        xmlSignature: signature,
        timestampTokens: [signatureToken],
        material: material,
        archiveTimestampToken: archiveToken
      )
      let container = try #require(
        AsicContainer.container(objects: objects, signatureXml: document))
      return Archived(
        container: container,
        document: try #require(String(data: document, encoding: .utf8))
      )
    }

    /// The first element `name` in `text`, from its start tag through
    /// its end tag.
    private static func element(_ name: String, in text: String) throws -> Substring {
      let start = try #require(
        text.range(of: "<\(name) ") ?? text.range(of: "<\(name)>"))
      let end = try #require(
        text.range(of: "</\(name)>", range: start.lowerBound..<text.endIndex))
      return text[start.lowerBound..<end.upperBound]
    }

    /// How often `needle` occurs in `text`.
    private static func occurrences(of needle: String, in text: String) -> Int {
      text.components(separatedBy: needle).count - 1
    }

    /// The SHA-384 imprint inside an RFC 3161 token.
    private static func imprint(of token: Data) throws -> Data {
      try RfcTimestamp.binding(in: RfcTimestamp.contents(in: token).tstInfo).digest
    }

    /// The archive timestamp input, rebuilt from the container alone
    /// (EN 319 132-1 V1.3.1 clause 5.5.2.3 steps 3 to 6).
    private static func recomputedInput(_ archived: Archived) throws -> Data {
      let text = archived.document
      let signedInfo = try Self.element("ds:SignedInfo", in: text)
      let entries = try ZipReader.open(archived.container).entries
      let pattern = try Regex(Self.referenceUriPattern)
      var input = Data()
      for match in signedInfo.matches(of: pattern) {
        let name = try #require(match.output[1].substring)
        input.append(try #require(entries[String(name)]))
      }
      for name in [
        "xades:SignedProperties", "ds:SignedInfo", "ds:SignatureValue", "ds:KeyInfo",
        Self.signatureTimeStampName, Self.certificateValuesName, Self.revocationValuesName,
      ] {
        input.append(Data(try Self.element(name, in: text).utf8))
      }
      return input
    }

    @Test
    internal func theArchiveTimestampIsLastAndImprintsEveryPrecedingInput() throws {
      let archived = try Self.archived()
      let text = archived.document
      #expect(Self.occurrences(of: "<\(Self.archiveTimeStampName) ", in: text) == 1)
      #expect(!text.contains("<xades:ArchiveTimeStamp"), "1.3.2 archive timestamps are forbidden")

      let archive = try Self.element(Self.archiveTimeStampName, in: text)
      let properties = try Self.element(Self.unsignedSignaturePropertiesName, in: text)
      let precedingProperties = [
        try Self.element(Self.signatureTimeStampName, in: text),
        try Self.element(Self.certificateValuesName, in: text),
        try Self.element(Self.revocationValuesName, in: text),
      ]
      // Nothing else sits among the properties, and the archive
      // timestamp closes them.
      let expectedBody =
        precedingProperties.map(String.init).joined(separator: Self.elementSeparator)
        + Self.elementSeparator + archive + Self.elementSeparator
      #expect(
        properties
          == "<\(Self.unsignedSignaturePropertiesName)>" + Self.elementSeparator + expectedBody
          + "</\(Self.unsignedSignaturePropertiesName)>")

      let encapsulated = try Self.element(Self.encapsulatedTimeStampName, in: String(archive))
      let base64 = try #require(
        encapsulated.split(separator: ">", maxSplits: 1).last?
          .split(separator: "<", maxSplits: 1).first)
      let token = try #require(Data(base64Encoded: String(base64)))
      let expected = Data(SHA384.hash(data: try Self.recomputedInput(archived)))
      #expect(try Self.imprint(of: token) == expected)
    }

    @Test
    internal func theVerifierStillVerifiesTheArchivedSignature() throws {
      let archived = try Self.archived()
      let report = try AsicVerificationTests.report(archived.container)
      #expect(report.documentIntact)
      #expect(report.signatureValid)
      #expect(
        report.timestamps == [
          .claimed(try #require(SyntheticTimestampAuthority.instant(Self.signatureStampTime)))
        ])
      if let path = ProcessInfo.processInfo.environment[Self.sampleOutputVariable],
        !path.isEmpty
      {
        try archived.container.write(to: URL(fileURLWithPath: path))
      }
    }
  }

#endif
