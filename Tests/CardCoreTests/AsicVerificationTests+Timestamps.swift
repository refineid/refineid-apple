// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CryptoKit
  import Foundation
  import Testing

  @testable import CardCore

  /// Only `xades:SignatureTimeStamp` tokens time the signature.
  extension AsicVerificationTests {
    /// Generation time of the signature time-stamp.
    private static let signatureStampTime = "20260805100000Z"

    /// An earlier generation time for the other time-stamp kinds.
    private static let otherStampTime = "20260805090000Z"

    /// XAdES 1.4.1 namespace, home of the archive time-stamp.
    private static let namespaceXades141 = "http://uri.etsi.org/01903/v1.4.1#"

    /// A SHA-384 imprint over input that is not the signature value.
    private static let unrelatedImprint = Data(
      SHA384.hash(data: Data("input that is not the signature value".utf8)))

    private static let unsignedSignaturePropertiesClose = "</xades:UnsignedSignatureProperties>"
    private static let qualifyingPropertiesClose = "</xades:QualifyingProperties>"
    private static let signedDataObjectPropertiesClose = "</xades:SignedDataObjectProperties>"

    /// The `XAdESTimeStampType` content around one token.
    private static func stampBody(_ token: Data) -> String {
      #"<ds:CanonicalizationMethod Algorithm="\#(XadesSignature.canonicalizationExclusive)">"#
        + "</ds:CanonicalizationMethod>\n"
        + "<xades:EncapsulatedTimeStamp>\(token.base64EncodedString())"
        + "</xades:EncapsulatedTimeStamp>\n"
    }

    private static func archiveTimeStamp(_ token: Data) -> String {
      #"<xades141:ArchiveTimeStamp xmlns:xades141="\#(namespaceXades141)">"# + "\n"
        + Self.stampBody(token)
        + "</xades141:ArchiveTimeStamp>\n"
    }

    private static func allDataObjectsTimeStamp(_ token: Data) -> String {
      "<xades:AllDataObjectsTimeStamp>\n"
        + Self.stampBody(token)
        + "</xades:AllDataObjectsTimeStamp>\n"
    }

    /// `text` with `insertion` placed before the first `marker`.
    private static func inserting(
      _ insertion: String, before marker: String, in text: String
    ) throws -> String {
      var out = text
      let range = try #require(out.range(of: marker))
      out.insert(contentsOf: insertion, at: range.lowerBound)
      return out
    }

    /// Our own document carrying one signature time-stamp over the
    /// canonical `ds:SignatureValue`, plus a minted token of the other
    /// kind over `otherImprint`.
    private static func stampedDocument(
      authority: SyntheticTimestampAuthority,
      otherImprint: (Data) -> Data
    ) throws -> (document: String, otherToken: Data) {
      var otherToken = Data()
      let signed = try Self.signedDocument(profile: .ecdsaP384) { signature in
        otherToken = try authority.token(
          imprint: otherImprint(signature), generalizedTime: Self.otherStampTime)
        return [
          try authority.token(
            imprint: XadesSignature.timestampDigest(signature),
            generalizedTime: Self.signatureStampTime)
        ]
      }
      return (signed.document, otherToken)
    }

    @Test
    internal func ownTimestampedContainerVerifies() throws {
      let authority = try SyntheticTimestampAuthority()
      let document = try Self.stampedDocument(authority: authority) { _ in Self.unrelatedImprint }
        .document

      let report = try Self.report(Self.container(document: document))
      #expect(report.documentIntact)
      #expect(report.signatureValid)
      #expect(
        report.timestamps == [
          .claimed(try #require(SyntheticTimestampAuthority.instant(Self.signatureStampTime)))
        ])
    }

    @Test
    internal func signatureTimestampOverOtherInputIsInvalid() throws {
      let authority = try SyntheticTimestampAuthority()
      let document = try Self.signedDocument(profile: .ecdsaP384) { _ in
        [
          try authority.token(
            imprint: Self.unrelatedImprint, generalizedTime: Self.signatureStampTime)
        ]
      }.document

      let report = try Self.report(Self.container(document: document))
      #expect(report.documentIntact)
      #expect(report.timestamps == [.invalid])
    }

    @Test
    internal func archiveTimestampAloneDoesNotTimeTheSignature() throws {
      let authority = try SyntheticTimestampAuthority()
      let signed = try Self.signedDocument(profile: .ecdsaP384)
      // Imprints the signature value, so only its enclosing element
      // keeps it out.
      let token = try authority.token(
        imprint: XadesSignature.timestampDigest(signed.xmlSignature),
        generalizedTime: Self.otherStampTime)
      let unsigned =
        "<xades:UnsignedProperties>\n<xades:UnsignedSignatureProperties>\n"
        + Self.archiveTimeStamp(token)
        + "</xades:UnsignedSignatureProperties>\n</xades:UnsignedProperties>\n"
      let document = try Self.inserting(
        unsigned, before: Self.qualifyingPropertiesClose, in: signed.document)

      let report = try Self.report(Self.container(document: document))
      #expect(report.documentIntact)
      #expect(report.signatureValid)
      #expect(report.timestamps.isEmpty)
    }

    @Test
    internal func allDataObjectsTimestampAloneDoesNotTimeTheSignature() throws {
      let authority = try SyntheticTimestampAuthority()
      let signed = try Self.signedDocument(profile: .ecdsaP384)
      let token = try authority.token(
        imprint: XadesSignature.timestampDigest(signed.xmlSignature),
        generalizedTime: Self.otherStampTime)
      // Inserted after signing, so the SignedProperties digest no
      // longer matches; only the time-stamp verdict is under test.
      let document = try Self.inserting(
        Self.allDataObjectsTimeStamp(token),
        before: Self.signedDataObjectPropertiesClose,
        in: signed.document)

      let report = try Self.report(Self.container(document: document))
      #expect(report.timestamps.isEmpty)
    }

    @Test
    internal func archiveTimestampBesideSignatureTimestampIsIgnored() throws {
      let authority = try SyntheticTimestampAuthority()
      let stamped = try Self.stampedDocument(authority: authority) { _ in Self.unrelatedImprint }
      let document = try Self.inserting(
        Self.archiveTimeStamp(stamped.otherToken),
        before: Self.unsignedSignaturePropertiesClose,
        in: stamped.document)

      let report = try Self.report(Self.container(document: document))
      #expect(report.documentIntact)
      #expect(report.signatureValid)
      #expect(
        report.timestamps == [
          .claimed(try #require(SyntheticTimestampAuthority.instant(Self.signatureStampTime)))
        ])
    }

    @Test
    internal func allDataObjectsTimestampBesideSignatureTimestampIsIgnored() throws {
      let authority = try SyntheticTimestampAuthority()
      let stamped = try Self.stampedDocument(authority: authority) { _ in Self.unrelatedImprint }
      let document = try Self.inserting(
        Self.allDataObjectsTimeStamp(stamped.otherToken),
        before: Self.signedDataObjectPropertiesClose,
        in: stamped.document)

      let report = try Self.report(Self.container(document: document))
      #expect(
        report.timestamps == [
          .claimed(try #require(SyntheticTimestampAuthority.instant(Self.signatureStampTime)))
        ])
    }
  }

#endif
