// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Testing

@testable import CardCore

/// Each `ds:Signature` in a signatures file is read from its own
/// subtree, nested signatures stay apart from the one enclosing them,
/// and base64 content decodes across line breaks.
@Suite
internal struct XadesXmlParserTests {
  private static let signedInfoOpen = "<ds:SignedInfo"
  private static let signingTimeOpen = "<xades:SigningTime>"
  private static let unsignedSignaturePropertiesClose = "</xades:UnsignedSignatureProperties>"

  /// An element whose name extends `ds:SignedInfo`.
  private static let extendedNameElement = "<ds:SignedInfoNote>note</ds:SignedInfoNote>\n"

  /// Opaque OCSP and CRL stand-ins for the parser, which only carries them.
  private static let ocspStandIn = Data("OCSP response stand-in".utf8)
  private static let crlStandIn = Data("CRL stand-in".utf8)

  /// The base64-carrying elements whose content the wrapping test folds.
  private static let base64Elements = [
    "ds:DigestValue", "ds:SignatureValue", "ds:X509Certificate",
    "xades:EncapsulatedTimeStamp", "xades:EncapsulatedX509Certificate",
    "xades:EncapsulatedOCSPValue", "xades:EncapsulatedCRLValue",
  ]

  /// Two independently valid signatures in one file both verify.
  @Test
  internal func twoSignaturesInOneFileBothVerify() throws {
    let first = try AsicVerificationTests.signedDocument(profile: .ecdsaP384)
    let second = try AsicVerificationTests.signedDocument(profile: .ecdsaP384)
    let document = Self.signaturesFile([
      try Self.signatureElement(of: first.document),
      try Self.signatureElement(of: second.document),
    ])

    let parsed = Self.parse(document)
    try #require(parsed.count == 2)
    #expect(parsed[0].signedPropertiesRawXml != parsed[1].signedPropertiesRawXml)
    #expect(parsed[0].signerCertificateDer == first.identity.certificate)
    #expect(parsed[1].signerCertificateDer == second.identity.certificate)

    let report = try AsicVerification.verify(
      container: try AsicVerificationTests.container(document: document))
    try #require(report.judged.count == 2)
    for signature in report.judged {
      #expect(signature.documentIntact)
      #expect(signature.signatureValid)
    }
  }

  /// A change inside the second signature's SignedProperties makes
  /// only the second not intact.
  @Test
  internal func tamperedSecondSignedPropertiesFailsOnlyTheSecond() throws {
    let first = try AsicVerificationTests.signedDocument(profile: .ecdsaP384)
    let second = try AsicVerificationTests.signedDocument(profile: .ecdsaP384)
    let secondElement = try Self.signatureElement(of: second.document)
    let opening = try #require(secondElement.range(of: Self.signingTimeOpen))
    var tampered = secondElement
    tampered.insert(" ", at: opening.upperBound)
    let document = Self.signaturesFile([
      try Self.signatureElement(of: first.document), tampered,
    ])

    let report = try AsicVerification.verify(
      container: try AsicVerificationTests.container(document: document))
    try #require(report.judged.count == 2)
    #expect(report.judged[0].documentIntact)
    #expect(!report.judged[1].documentIntact)
  }

  /// An element whose name starts with `ds:SignedInfo` is not taken
  /// for `ds:SignedInfo`.
  @Test
  internal func elementExtendingTheTagNameIsNotPicked() throws {
    let signed = try AsicVerificationTests.signedDocument(profile: .ecdsaP384)
    let plain = try #require(Self.parse(signed.document).first)
    let decorated = try Self.inserting(
      Self.extendedNameElement, before: Self.signedInfoOpen, in: signed.document)

    let parsed = try #require(Self.parse(decorated).first)

    let signedInfo = try #require(parsed.signedInfoRawXml)
    #expect(signedInfo == plain.signedInfoRawXml)
    #expect(!signedInfo.contains(Self.extendedNameElement))
    let report = try AsicVerificationTests.report(
      try AsicVerificationTests.container(document: decorated))
    #expect(report.signatureValid)
    #expect(report.documentIntact)
  }

  /// A counter-signature leaves the outer signature's fields as they
  /// are and is read as its own, marked, signature.
  @Test
  internal func counterSignatureLeavesTheOuterSignatureIntact() throws {
    let authority = try TimestampAuthorityFixture.make()
    let outer = try Self.stampedDocument(authority: authority)
    let inner = try Self.stampedDocument(authority: authority)
    let counterSignature =
      "<xades:CounterSignature>\n"
      + (try Self.signatureElement(of: inner.document))
      + "\n</xades:CounterSignature>\n"
    let countersigned = try Self.inserting(
      counterSignature, before: Self.unsignedSignaturePropertiesClose, in: outer.document)

    let plain = try #require(Self.parse(outer.document).first)
    let innerAlone = try #require(Self.parse(inner.document).first)
    let parsed = Self.parse(countersigned)

    try #require(parsed.count == 2)
    Self.expectSameFields(parsed[0], plain)
    #expect(!parsed[0].isCounterSignature)
    #expect(parsed[1].isCounterSignature)
    #expect(parsed[1].signerCertificateDer == inner.identity.certificate)
    #expect(parsed[1].signedInfoRawXml == innerAlone.signedInfoRawXml)
    #expect(parsed[1].signatureTimestampTokens == innerAlone.signatureTimestampTokens)
  }

  /// Base64 content wrapped across lines decodes to the same values.
  @Test
  internal func wrappedBase64Decodes() throws {
    let authority = try TimestampAuthorityFixture.make()
    let identity = try QualifiedDocumentCmsTests.identity(.ecdsaP384)
    let plan = try #require(
      XadesSignature.plan(
        objects: AsicVerificationTests.sampleObjects(),
        certificate: identity.certificate,
        profile: .ecdsaP384,
        signedAt: AsicVerificationTests.signedAt
      )
    )
    let signature = try AsicVerificationTests.xmlSignature(
      over: plan.signedInfo, identity: identity, profile: .ecdsaP384)
    let token = try authority.token(
      imprint: XadesSignature.timestampDigest(signature),
      algorithm: DocumentDigestAlgorithm.sha384.algorithmIdentifier
    )
    let document = try #require(
      String(
        data: plan.document(
          xmlSignature: signature,
          timestampTokens: [token],
          material: PdfValidationStore.Material(
            certificates: [authority.certificate],
            ocspResponses: [Self.ocspStandIn],
            revocationLists: [Self.crlStandIn]
          )
        ),
        encoding: .utf8
      )
    )
    let folded = Self.base64Elements.reduce(document) { text, tag in
      Self.wrappingContent(of: tag, in: text)
    }
    try #require(folded != document)

    let plain = try #require(Self.parse(document).first)
    let parsed = try #require(Self.parse(folded).first)

    #expect(parsed.signatureValueBytes == signature)
    #expect(parsed.signerCertificateDer == identity.certificate)
    #expect(parsed.signatureTimestampTokens == [token])
    #expect(parsed.certificateValues == [authority.certificate])
    #expect(parsed.ocspValues == [Self.ocspStandIn])
    #expect(parsed.crlValues == [Self.crlStandIn])
    #expect(
      Self.references(of: parsed).map(\.digestValue)
        == Self.references(of: plain).map(\.digestValue))
  }

  /// A signature time-stamp whose TSTInfo names SHA-256 verifies under
  /// SHA-256.
  @Test
  internal func sha256SignatureTimestampVerifies() throws {
    let authority = try TimestampAuthorityFixture.make()
    let signed = try AsicVerificationTests.signedDocument(profile: .ecdsaP384) { signature in
      [
        try authority.token(
          imprint: Data(
            SHA256.hash(data: Data(XadesSignature.signatureValueElement(signature).utf8))),
          algorithm: DocumentDigestAlgorithm.sha256.algorithmIdentifier
        )
      ]
    }

    let report = try AsicVerificationTests.report(
      try AsicVerificationTests.container(document: signed.document))

    #expect(report.claimedTime != nil)
    #expect(!report.hasInvalidTimestamp)
  }

  /// An imprint whose length is not that of the algorithm the TSTInfo
  /// names is refused.
  @Test
  internal func imprintOfAnotherLengthIsRefused() throws {
    let authority = try TimestampAuthorityFixture.make()
    let signed = try AsicVerificationTests.signedDocument(profile: .ecdsaP384) { signature in
      [
        try authority.token(
          imprint: XadesSignature.timestampDigest(signature),
          algorithm: DocumentDigestAlgorithm.sha256.algorithmIdentifier
        )
      ]
    }

    let report = try AsicVerificationTests.report(
      try AsicVerificationTests.container(document: signed.document))

    #expect(report.timestamps == [.invalid])
  }
}
