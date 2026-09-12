// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

import CryptoKit
import Foundation
import Security
import Testing

@testable import CardCore

@Suite
internal struct AsicVerificationTests {
  private static let signedAt = Date(timeIntervalSince1970: 1_785_849_296)

  private static let emptyMaterial = PdfValidationStore.Material(
    certificates: [],
    ocspResponses: [],
    revocationLists: []
  )

  private static func sampleObjects() -> [AsicContainer.DataObject] {
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
    profile: CardKeyProfile,
    objects: [AsicContainer.DataObject] = sampleObjects()
  ) throws -> (container: Data, identity: QualifiedDocumentCmsTests.Identity) {
    let identity = try QualifiedDocumentCmsTests.identity(profile)
    let plan = try #require(
      XadesSignature.plan(
        objects: objects,
        certificate: identity.certificate,
        profile: profile,
        signedAt: Self.signedAt
      )
    )

    let signatureXml = try signXml(plan: plan, identity: identity, profile: profile)
    let container = try #require(
      AsicContainer.container(objects: objects, signatureXml: signatureXml)
    )
    return (container, identity)
  }

  private static func signXml(
    plan: XadesSignature.Plan,
    identity: QualifiedDocumentCmsTests.Identity,
    profile: CardKeyProfile
  ) throws -> Data {
    let signedInfoDigest = Data(SHA384.hash(data: plan.signedInfo))
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

    let xmlSignature: Data
    switch profile {
    case .ecdsaP384:
      xmlSignature = try #require(
        EcdsaSignature.rawConcatenation(
          fromDer: derSignature,
          coordinateOctets: 48
        )
      )
    case .ecdsaP256:
      xmlSignature = try #require(
        EcdsaSignature.rawConcatenation(
          fromDer: derSignature,
          coordinateOctets: 32
        )
      )
    case .rsa2048, .rsa3072:
      xmlSignature = derSignature
    }

    return plan.document(
      xmlSignature: xmlSignature,
      timestampTokens: [],
      material: Self.emptyMaterial
    )
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
    let sig = report.signatures[0]
    #expect(sig.documentIntact)
    #expect(sig.signatureValid)
    #expect(sig.coversWholeDocument)
    #expect(sig.signerName.contains("RefineID Document CMS Test"))
  }

  @Test
  internal func verifiesValidAsicContainerWithRsa() throws {
    let (container, _) = try Self.signedContainer(profile: .rsa2048)
    let report = try AsicVerification.verify(container: container)

    #expect(report.signatures.count == 1)
    let sig = report.signatures[0]
    #expect(sig.documentIntact)
    #expect(sig.signatureValid)
    #expect(sig.coversWholeDocument)
  }

  @Test
  internal func dispatchThroughDocumentVerificationVerify() throws {
    let (container, _) = try Self.signedContainer(profile: .ecdsaP384)
    let report = try DocumentVerification.verify(document: container)

    #expect(report.signatures.count == 1)
    let sig = report.signatures[0]
    #expect(sig.documentIntact)
    #expect(sig.signatureValid)
  }

  @Test
  internal func refusesTamperedPayloadFile() throws {
    let (container, _) = try Self.signedContainer(profile: .ecdsaP384)
    var entries = ZipReader.read(archive: container)

    // Modify carried file bytes
    entries["test.txt"] = Data("Tampered content that does not match the digest!".utf8)

    // Reassemble ZIP archive with tampered file
    var writer = AsicContainer.ZipWriter()
    for (name, data) in entries {
      writer.add(name: name, content: data)
    }
    let tamperedContainer = try #require(writer.finish())

    let report = try AsicVerification.verify(container: tamperedContainer)
    #expect(report.signatures.count == 1)
    #expect(!report.signatures[0].documentIntact)
  }

  @Test
  internal func refusesTamperedSignatureXml() throws {
    let (container, _) = try Self.signedContainer(profile: .ecdsaP384)
    var entries = ZipReader.read(archive: container)

    guard let xmlData = entries["META-INF/signatures0.xml"],
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
    entries["META-INF/signatures0.xml"] = Data(xmlString.utf8)

    var writer = AsicContainer.ZipWriter()
    for (name, data) in entries {
      writer.add(name: name, content: data)
    }
    let tamperedContainer = try #require(writer.finish())

    #expect(throws: Error.self) {
      try AsicVerification.verify(container: tamperedContainer)
    }
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
