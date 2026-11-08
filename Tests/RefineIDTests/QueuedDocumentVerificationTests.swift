// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if DEBUG && os(macOS)

  import Foundation
  import Testing

  @testable import CardCore
  @testable import RefineIDTestHost

  /// The Mac's Verify button: what it verifies, what each document
  /// shows, and that the pile stays ready to sign.
  @MainActor
  @Suite
  internal struct QueuedDocumentVerificationTests {
    private static let signedName = "signed.pdf"
    private static let unsignedName = "unsigned.pdf"
    private static let textName = "notes.txt"
    private static let officeName = "sheet.docx"
    private static let stampOnlyName = "stamped.pdf"
    private static let detachedSignatureName = "contract.pdf.p7s"
    private static let unnamedSignatureName = "signature.der"
    private static let officeEntryName = "content.xml"
    private static let textContent = Data("An unsigned note.".utf8)

    /// The real verifier under no anchors, without live answers.
    private static var dependencies: VerifyDocumentModel.Dependencies {
      VerifyDocumentModel.Dependencies(
        anchors: { .success(.empty) },
        verify: { document, anchors in
          try DocumentVerification.verify(document: document, anchors: anchors)
        },
        liveStatus: { _ in nil },
        now: Date.init
      )
    }

    /// A fresh directory holding the four documents, keyed by name.
    private static func documents() throws -> [String: URL] {
      let directory = FileManager.default.temporaryDirectory.appending(
        path: "QueuedDocumentVerificationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let fixture = try TimestampedPdfFixture.make()
      var office = AsicContainer.ZipWriter()
      office.add(name: Self.officeEntryName, content: Self.textContent)
      let contents: [String: Data] = [
        Self.signedName: try fixture.placeholder.filled(with: fixture.cms),
        Self.unsignedName: TimestampedPdfFixture.minimalPdf,
        Self.textName: Self.textContent,
        Self.officeName: try #require(office.finish()),
        Self.stampOnlyName: try Self.documentTimestampOnly(),
      ]
      var urls: [String: URL] = [:]
      for (name, data) in contents {
        let url = directory.appending(path: name)
        try data.write(to: url)
        urls[name] = url
      }
      return urls
    }

    /// A PDF whose one revision is a document timestamp, which signs
    /// nothing.
    private static func documentTimestampOnly() throws -> Data {
      let revision = try PdfIncrementalSigner.prepare(
        TimestampedPdfFixture.minimalPdf, revision: .documentTimestamp)
      return try revision.filled(
        with: DerEncoder.sequence([DerEncoder.integer(SignOids.cmsVersion)]))
    }

    /// Every verification of `verification` run to its end.
    private static func finished(_ verification: QueuedDocumentVerification) async {
      for item in verification.items {
        await item.model.verification?.value
      }
    }

    /// The button needs a waiting document and no signature in flight.
    @Test
    internal func verifyNeedsADocumentAndNoSignatureInFlight() throws {
      let document = try #require(Self.documents()[Self.unsignedName])
      #expect(!QueuedDocumentVerification.isAvailable(queued: [], signing: false))
      #expect(!QueuedDocumentVerification.isAvailable(queued: [document], signing: true))
      #expect(QueuedDocumentVerification.isAvailable(queued: [document], signing: false))
    }

    /// A signed document shows its signature's report; an unsigned PDF,
    /// a PDF with only a document timestamp, a text file and an office
    /// document each say plainly that they carry no signatures.
    @Test
    internal func signedAndUnsignedDocumentsEachShowTheirOutcome() async throws {
      let urls = try Self.documents()
      let order = [
        Self.signedName, Self.unsignedName, Self.stampOnlyName, Self.textName, Self.officeName,
      ]
      let verification = QueuedDocumentVerification(
        documents: try order.map { name in try #require(urls[name]) },
        dependencies: Self.dependencies)
      await Self.finished(verification)

      #expect(verification.items.map(\.document.lastPathComponent) == order)
      for item in verification.items {
        switch (item.document.lastPathComponent, item.model.phase) {
        case (Self.signedName, .report(let rows, _)):
          try #require(rows.count == 1)
          guard case .judged(let report) = rows[0].entry else {
            Issue.record("The signature was not judged")
            continue
          }
          #expect(report.documentIntact)
          #expect(report.signatureValid)
          #expect(!report.chainVerified, "nothing anchors without trusted lists")
          #expect(report.level == .basic, "an unanchored timestamp proves nothing")

        case (Self.signedName, _):
          Issue.record("The signed document was not reported")

        case (_, .failed(let message)):
          #expect(message == VerifyDocumentModel.noSignaturesMessage)

        default:
          Issue.record("\(item.document.lastPathComponent) did not say it is unsigned")
        }
      }
    }

    /// Verifying reads the pile and leaves it as it was, so the same
    /// documents can be signed next without being dropped again.
    @Test
    internal func verificationLeavesThePileReadyToSign() async throws {
      let urls = try Self.documents()
      let pile = try [Self.signedName, Self.unsignedName].map { name in try #require(urls[name]) }
      let signing = SignDocumentModel()
      signing.accept(pile)
      let pending = signing.pending

      let verification = QueuedDocumentVerification(
        documents: signing.queued, dependencies: Self.dependencies)
      await Self.finished(verification)

      #expect(signing.queued == pile)
      #expect(signing.pending == pending)
      #expect(pending != nil)
      #expect(
        QueuedDocumentVerification.isAvailable(queued: signing.queued, signing: signing.working))
    }

    /// A report without a signature row, whatever produced it, says
    /// that the document carries no signatures.
    @Test
    internal func anEmptyReportSaysNoSignatures() async {
      let model = VerifyDocumentModel(
        dependencies: VerifyDocumentModel.Dependencies(
          anchors: { .success(.empty) },
          verify: { _, _ in
            DocumentVerification.DocumentReport(signatures: [], documentTimestamps: [.invalid])
          },
          liveStatus: { _ in nil },
          now: Date.init))
      model.verify(document: Self.textContent, name: Self.unsignedName)
      await model.verification?.value
      guard case .failed(let message) = model.phase else {
        Issue.record("An empty report was shown as a report")
        return
      }
      #expect(message == VerifyDocumentModel.noSignaturesMessage)
    }

    /// A CMS SignedData file, named as one or recognised by its
    /// content, says its format cannot be verified here yet, never that
    /// it carries no signatures.
    @Test
    internal func cmsSignedDataSaysItCannotBeVerifiedYet() async throws {
      let directory = FileManager.default.temporaryDirectory.appending(
        path: "QueuedDocumentVerificationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let cms = try TimestampedPdfFixture.make().cms
      let named = directory.appending(path: Self.detachedSignatureName)
      let unnamed = directory.appending(path: Self.unnamedSignatureName)
      try Self.textContent.write(to: named)
      try cms.write(to: unnamed)

      let verification = QueuedDocumentVerification(
        documents: [named, unnamed], dependencies: Self.dependencies)
      await Self.finished(verification)

      for item in verification.items {
        guard case .failed(let message) = item.model.phase else {
          Issue.record("\(item.document.lastPathComponent) was not refused")
          continue
        }
        #expect(message == VerifyDocumentModel.cmsSignedDataMessage)
      }
    }
  }

#endif
