// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security
import Testing

@testable import CardCore

@Suite
internal struct AsicVerificationTests {
  /// A signature document our own writer produced.
  internal struct SignedDocument {
    /// `META-INF/signatures0.xml` as text.
    internal let document: String

    /// The raw signature value inside it.
    internal let xmlSignature: Data

    /// The signer.
    internal let identity: QualifiedDocumentCmsTests.Identity
  }

  internal static let signedAt = Date(timeIntervalSince1970: 1_785_849_296)

  internal static let signatureFileName = "META-INF/signatures0.xml"

  private static let emptyMaterial = PdfValidationStore.Material(
    certificates: [],
    ocspResponses: [],
    revocationLists: []
  )

  internal static func sampleObjects() -> [AsicContainer.DataObject] {
    [
      AsicContainer.DataObject(
        name: "test.txt",
        mimeType: "text/plain",
        content: Data("Sample text content to be signed.".utf8)
      ),
      AsicContainer.DataObject(
        name: "invoice.pdf",
        mimeType: "application/pdf",
        content: Data("Simulated PDF invoice data.".utf8)
      ),
    ]
  }

  private static func signedContainer(
    profile: CardKeyProfile
  ) throws -> (container: Data, identity: QualifiedDocumentCmsTests.Identity) {
    let signed = try Self.signedDocument(profile: profile)
    return (try Self.container(document: signed.document), signed.identity)
  }

  /// Our writer's signature over `sampleObjects()`, at baseline B.
  internal static func signedDocument(profile: CardKeyProfile) throws -> SignedDocument {
    try Self.signedDocument(profile: profile) { _ in [] }
  }

  /// Our writer's signature over `sampleObjects()`.
  ///
  /// `timestampTokens(xmlSignature)` supplies the tokens the writer
  /// embeds as `xades:SignatureTimeStamp`.
  internal static func signedDocument(
    profile: CardKeyProfile,
    timestampTokens: (Data) throws -> [Data]
  ) throws -> SignedDocument {
    let objects = Self.sampleObjects()
    let identity = try QualifiedDocumentCmsTests.identity(profile)
    let plan = try #require(
      XadesSignature.plan(
        objects: objects,
        certificate: identity.certificate,
        profile: profile,
        signedAt: Self.signedAt
      )
    )
    let signature = try Self.xmlSignature(
      over: plan.signedInfo, identity: identity, profile: profile)
    let document = plan.document(
      xmlSignature: signature,
      timestampTokens: try timestampTokens(signature),
      material: Self.emptyMaterial
    )
    return SignedDocument(
      document: try #require(String(data: document, encoding: .utf8)),
      xmlSignature: signature,
      identity: identity
    )
  }

  /// The XML-form signature over `signedInfo`: raw `r || s` for
  /// ECDSA, the PKCS #1 block for RSA.
  internal static func xmlSignature(
    over signedInfo: Data,
    identity: QualifiedDocumentCmsTests.Identity,
    profile: CardKeyProfile
  ) throws -> Data {
    let signedInfoDigest = Data(SHA384.hash(data: signedInfo))
    let algorithm: SecKeyAlgorithm =
      profile == .ecdsaP384
      ? .ecdsaSignatureDigestX962SHA384
      : .rsaSignatureDigestPKCS1v15SHA384

    var error: Unmanaged<CFError>?
    let derSignature = try #require(
      SecKeyCreateSignature(
        identity.privateKey,
        algorithm,
        signedInfoDigest as CFData,
        &error
      ) as Data?
    )

    switch profile {
    case .ecdsaP384:
      return try #require(
        EcdsaSignature.rawConcatenation(
          fromDer: derSignature,
          coordinateOctets: 48
        )
      )
    case .ecdsaP256:
      return try #require(
        EcdsaSignature.rawConcatenation(
          fromDer: derSignature,
          coordinateOctets: 32
        )
      )
    case .rsa2048, .rsa3072:
      return derSignature
    }
  }

  /// A container carrying `sampleObjects()` and the signature
  /// document as given, edited or not.
  internal static func container(document: String) throws -> Data {
    try #require(
      AsicContainer.container(objects: Self.sampleObjects(), signatureXml: Data(document.utf8)))
  }

  /// The single signature report for a container.
  internal static func report(
    _ container: Data
  ) throws -> DocumentVerification.SignatureReport {
    let report = try AsicVerification.verify(container: container)
    try #require(report.judged.count == 1)
    return report.judged[0]
  }

  /// A container holding `entries`, its `mimetype` entry first and
  /// stored as EN 319 162-1 clause A.1 requires.
  internal static func reassembled(_ entries: [String: Data]) throws -> Data {
    var writer = AsicContainer.ZipWriter()
    if let mimetype = entries[AsicContainer.mimetypeEntryName] {
      writer.add(name: AsicContainer.mimetypeEntryName, content: mimetype)
    }
    for name in entries.keys.sorted() where name != AsicContainer.mimetypeEntryName {
      writer.add(name: name, content: entries[name] ?? Data())
    }
    return try #require(writer.finish())
  }

  @Test
  internal func identifiesAsicContainerCorrectly() throws {
    let (container, _) = try Self.signedContainer(profile: .ecdsaP384)
    #expect(AsicVerification.isAsicContainer(container))

    let notAsic = Data("%PDF-1.7 simulated document".utf8)
    #expect(!AsicVerification.isAsicContainer(notAsic))

    let emptyData = Data()
    #expect(!AsicVerification.isAsicContainer(emptyData))
  }

  @Test
  internal func verifiesValidAsicContainerWithEcdsa() throws {
    let (container, _) = try Self.signedContainer(profile: .ecdsaP384)
    let report = try AsicVerification.verify(container: container)

    #expect(report.signatures.count == 1)
    let sig = report.judged[0]
    #expect(sig.documentIntact)
    #expect(sig.signatureValid)
    #expect(sig.coversWholeDocument)
    #expect(sig.signerCommonName == QualifiedDocumentCmsTests.identityCommonName)
  }

  @Test
  internal func verifiesValidAsicContainerWithRsa() throws {
    let (container, _) = try Self.signedContainer(profile: .rsa2048)
    let report = try AsicVerification.verify(container: container)

    #expect(report.signatures.count == 1)
    let sig = report.judged[0]
    #expect(sig.documentIntact)
    #expect(sig.signatureValid)
    #expect(sig.coversWholeDocument)
  }

  @Test
  internal func dispatchThroughDocumentVerificationVerify() throws {
    let (container, _) = try Self.signedContainer(profile: .ecdsaP384)
    let report = try DocumentVerification.verify(document: container)

    #expect(report.signatures.count == 1)
    let sig = report.judged[0]
    #expect(sig.documentIntact)
    #expect(sig.signatureValid)
  }

  @Test
  internal func refusesTamperedPayloadFile() throws {
    let (container, _) = try Self.signedContainer(profile: .ecdsaP384)
    var entries = ZipReader.read(archive: container)

    // Modify carried file bytes
    entries["test.txt"] = Data("Tampered content that does not match the digest!".utf8)

    let tamperedContainer = try Self.reassembled(entries)

    let report = try AsicVerification.verify(container: tamperedContainer)
    #expect(report.signatures.count == 1)
    #expect(!report.judged[0].documentIntact)
  }

  @Test
  internal func refusesTamperedSignatureXml() throws {
    let (container, _) = try Self.signedContainer(profile: .ecdsaP384)
    var entries = ZipReader.read(archive: container)

    guard let xmlData = entries[Self.signatureFileName],
      var xmlString = String(data: xmlData, encoding: .utf8)
    else {
      Issue.record("Failed to read signatures0.xml")
      return
    }

    // Corrupt the signature value
    if let sigValRange = xmlString.range(of: "<ds:SignatureValue") {
      let afterTag = xmlString.index(after: sigValRange.lowerBound)
      xmlString.insert("X", at: afterTag)
    }
    entries[Self.signatureFileName] = Data(xmlString.utf8)

    let tamperedContainer = try Self.reassembled(entries)

    let report = try AsicVerification.verify(container: tamperedContainer)
    #expect(report.judged.isEmpty)
    #expect(!report.signatures.isEmpty)
    #expect(!report.isValid)
  }

  @Test
  internal func throwsNoSignaturesWhenMissing() throws {
    var writer = AsicContainer.ZipWriter()
    writer.add(name: "mimetype", content: Data(AsicContainer.mimeType.utf8))
    writer.add(name: "file.txt", content: Data("hello".utf8))
    let archive = try #require(writer.finish())

    #expect(throws: DocumentVerification.Failure.noSignatures) {
      try AsicVerification.verify(container: archive)
    }
  }
}
