// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import Foundation
  import Testing

  @testable import RefineIDTestHost

  /// What the status row says about document signing, and when it
  /// returns to the identity.
  @MainActor
  @Suite
  internal struct StatusMessageTests {
    private static let document = URL(filePath: "/documents/contract.pdf")
    private static let signedFile = URL(filePath: "/documents/contract - signed.pdf")
    private static let failure = "The card did not complete the signature."
    private static let other = URL(filePath: "/documents/other.pdf")
    private static let otherSigned = URL(filePath: "/documents/other - signed.pdf")
    private static let notice = "The signature stays below the long-term archival level."
    private static let pileSize = 2
    private static let refusal = "The signed file cannot replace the document."
    private static let signedBytes = Data("signed".utf8)
    private static let waitRounds = 10_000

    /// A signature in flight speaks its step in the row, as the step
    /// moves on.
    @Test
    internal func aSigningStepRendersInTheStatusRow() {
      let signing = SignDocumentModel()
      signing.accept([Self.document])
      #expect(StatusMessage(signing) == nil, "a waiting pile leaves the row to the identity")

      _ = signing.beginSigning()
      #expect(StatusMessage(signing) == .progress(StatusView.progressNote(signing) ?? ""))
      signing.show(.timestamp)
      #expect(StatusMessage(signing) == .progress(DocumentSigningPhase.timestamp.note))

      signing.endSigning()
      #expect(StatusMessage(signing) == nil)
    }

    @Test
    internal func batchTimestampingNamesTheCurrentDocument() {
      let signing = SignDocumentModel()
      let documents = [Self.document, Self.other]
      signing.accept(documents)
      _ = signing.beginSigning()
      signing.beginPile()
      signing.show(.timestamp)
      for source in documents {
        signing.focus(on: source)
        let label = DocumentSigningPhase.timestamp.note.trimmingCharacters(
          in: CharacterSet(charactersIn: ".\u{2026}"))
        let expected = "\(label): \(source.lastPathComponent)..."
        #expect(StatusMessage(signing) == .progress(expected))
      }
    }

    /// A failure stays in the row until acknowledged.
    @Test
    internal func aFailureStaysUntilAcknowledged() {
      let signing = SignDocumentModel()
      signing.accept([Self.document])
      signing.fail(message: Self.failure)
      #expect(StatusMessage(signing) == .failure(Self.failure))

      signing.acknowledgeOutcome()
      #expect(StatusMessage(signing) == nil)
    }

    /// A new action clears the previous failure before its first step,
    /// keeping the waiting documents for that action.
    @Test
    internal func aNewActionClearsThePreviousFailureBeforeItsFirstStep() {
      let signing = SignDocumentModel()
      signing.accept([Self.document])
      signing.fail(message: Self.failure)
      #expect(StatusMessage(signing) == .failure(Self.failure))

      signing.beginAction()
      #expect(StatusMessage(signing) == nil)
      #expect(signing.queued == [Self.document])
      #expect(signing.pending == Self.document)
    }

    /// Clearing an old failure resumes the signature waiting for its
    /// acknowledgement, even before the new action starts a document.
    @Test(.timeLimit(.minutes(1)))
    internal func aNewActionResumesThePreviousFailureAcknowledgement() async throws {
      let signing = SignDocumentModel()
      async let waiting: Void = signing.failAndWait(Self.failure)
      try await untilFailureIsWaiting(signing)
      #expect(StatusMessage(signing) == .failure(Self.failure))

      signing.beginAction()
      await waiting
      #expect(StatusMessage(signing) == nil)
    }

    /// A retry after the acknowledgement signs the pending document and
    /// lands the file where the panel said.
    @Test(.timeLimit(.minutes(1)))
    internal func aRetryAfterAcknowledgementSignsThePendingDocument() async throws {
      let signing = SignDocumentModel()
      signing.accept([Self.document])
      let folder = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: folder) }
      let destination = folder.appending(path: Self.signedFile.lastPathComponent)
      let finished = SignedDocument(untimestamped: Self.signedBytes, clock: Date())
      var answers = [
        SignDocumentModel.PlaceAnswer(destination: Self.document, typedName: nil),
        SignDocumentModel.PlaceAnswer(destination: destination, typedName: nil),
      ]
      async let saving: Bool = signing.save(
        finished,
        originals: [Self.document],
        refusal: Self.refusal,
        choose: { _, _ in answers.removeFirst() })

      try await untilFailureIsWaiting(signing)
      #expect(StatusMessage(signing) == .failure(Self.refusal))

      signing.acknowledgeFailure()
      #expect(await saving)
      #expect(signing.signedFiles == [destination])
      #expect(try Data(contentsOf: destination) == finished.bytes)
    }

    /// The previous notice and saved files belong to their completed
    /// action, not the next one.
    @Test
    internal func aNewActionClearsThePreviousNoticeAndSavedFiles() {
      let signing = SignDocumentModel()
      signing.accept([Self.document])
      signing.complete(with: Self.signedFile)
      signing.setNotice(Self.notice)
      #expect(StatusMessage(signing) == .outcome(notice: Self.notice, signed: [Self.signedFile]))
      #expect(signing.lastActionSignedSomething)

      signing.beginAction()
      #expect(StatusMessage(signing) == nil)
      #expect(signing.queued == [Self.document])
      #expect(!signing.lastActionSignedSomething)
    }

    /// The saved file is reported until acknowledged or the pile
    /// changes.
    @Test
    internal func theSavedFileIsReportedUntilAcknowledgedOrThePileChanges() {
      let signing = SignDocumentModel()
      signing.accept([Self.document])
      signing.complete(with: Self.signedFile)
      signing.clearQueue()
      #expect(StatusMessage(signing) == .outcome(notice: nil, signed: [Self.signedFile]))

      signing.acknowledgeOutcome()
      #expect(StatusMessage(signing) == nil)

      signing.accept([Self.document])
      signing.complete(with: Self.signedFile)
      signing.accept([Self.other])
      #expect(StatusMessage(signing) == nil)
    }

    /// A failure in the middle of a step shows at once, not behind the
    /// step's spinner.
    @Test
    internal func aFailureMidStepShowsBeforeTheStep() {
      let signing = SignDocumentModel()
      signing.accept([Self.document])
      _ = signing.beginSigning()
      signing.show(.timestamp)
      signing.fail(message: Self.failure)
      #expect(StatusMessage(signing) == .failure(Self.failure))
    }

    /// A notice and the saved file show together, and one OK puts both
    /// away.
    @Test
    internal func aNoticeAndTheSavedFileShowTogether() {
      let signing = SignDocumentModel()
      signing.accept([Self.document])
      signing.beginAction()
      signing.complete(with: Self.signedFile)
      signing.setNotice(Self.notice)
      #expect(StatusMessage(signing) == .outcome(notice: Self.notice, signed: [Self.signedFile]))

      signing.acknowledgeOutcome()
      #expect(StatusMessage(signing) == nil)
    }

    /// A pile reports every file it wrote, a failure first and then the
    /// files, one acknowledgement at a time.
    @Test
    internal func aPileReportsEveryFileItWrote() {
      let signing = SignDocumentModel()
      signing.accept([Self.document, Self.other])
      signing.beginAction()
      _ = signing.beginSigning()
      signing.complete(with: Self.signedFile)
      _ = signing.beginDocument()
      signing.complete(with: Self.otherSigned)
      signing.endSigning()
      signing.fail(message: Self.failure)
      #expect(StatusMessage(signing) == .failure(Self.failure))

      signing.acknowledgeOutcome()
      #expect(
        StatusMessage(signing)
          == .outcome(notice: nil, signed: [Self.signedFile, Self.otherSigned]))
      #expect(
        StatusMessage.savedSentence(count: Self.pileSize)
          != StatusMessage.savedSentence(count: 1))

      signing.beginAction()
      #expect(StatusMessage(signing) == nil, "a new action starts with nothing saved")
    }

    /// Yields until the model holds a signature waiting on its failure
    /// alert, so the test acts on a waiter rather than on its absence.
    private func untilFailureIsWaiting(_ signing: SignDocumentModel) async throws {
      var rounds = 0
      while signing.acknowledgement == nil, rounds < Self.waitRounds {
        await Task.yield()
        rounds += 1
      }
      try #require(
        signing.acknowledgement != nil,
        "the model never held a signature waiting on its failure alert")
    }
  }

#endif
