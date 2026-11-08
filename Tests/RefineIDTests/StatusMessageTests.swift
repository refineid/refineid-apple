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

    /// The saved file is reported until acknowledged or the pile
    /// changes.
    @Test
    internal func theSavedFileIsReportedUntilAcknowledgedOrThePileChanges() {
      let signing = SignDocumentModel()
      signing.accept([Self.document])
      signing.complete(with: Self.signedFile)
      signing.clearQueue()
      #expect(StatusMessage(signing) == .signed(Self.signedFile))

      signing.acknowledgeOutcome()
      #expect(StatusMessage(signing) == nil)

      signing.accept([Self.document])
      signing.complete(with: Self.signedFile)
      signing.accept([Self.other])
      #expect(StatusMessage(signing) == nil)
    }
  }

#endif
