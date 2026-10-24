// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation
  import RappEngine
  import Testing

  @testable import RefineIDTestHost

  /// Every signing failure names its own cause and waits to be acknowledged.
  @Suite
  internal struct SigningFailureMessageTests {
    private static let remoteFailures: [Error] = [
      DocumentSigner.Failure.remote(.noSignature),
      DocumentSigner.Failure.remote(.unverifiedSignature),
      DocumentSigner.Failure.remote(.unusableCertificate),
      RappRequesterClientError.noSelectedPair,
      RappRequesterClientError.timedOut,
      RappRequesterClientError.transport,
      RappRequesterClientError.terminal(.userCancelled),
      RappRequesterClientError.terminal(.operationExpired),
      RappRequesterClientError.terminal(.busy),
      RappRequesterClientError.terminal(.unsupportedParameter),
      RappRequesterClientError.terminal(.retryFloor),
      RappRequesterClientError.terminal(.cardError),
    ]

    @Test
    internal func eachRemoteCauseHasItsOwnMessage() {
      let messages = Self.remoteFailures.map(DocumentSigningMessage.message(for:))
      #expect(Set(messages).count == messages.count)
    }

    @Test
    internal func noRemoteCauseReadsAsAGenericCardFailure() {
      let cardFailure = DocumentSigningMessage.message(
        for: DocumentSigner.Failure.card(.failed))
      for failure in Self.remoteFailures {
        #expect(DocumentSigningMessage.message(for: failure) != cardFailure)
      }
    }

    @Test
    internal func everyRegisteredErrorHasAMessage() {
      for reason in RappTerminalReason.allCases {
        #expect(
          !DocumentSigningMessage.message(for: RappRequesterClientError.terminal(reason))
            .isEmpty)
      }
    }

    @Test
    internal func thePhoneRetryFloorMatchesTheLocalOne() {
      #expect(
        DocumentSigningMessage.message(for: RappRequesterClientError.terminal(.retryFloor))
          == DocumentSigningMessage.message(
            for: DocumentSigner.Failure.card(.floorRefused(.refuseLowAttempts))))
    }

    @Test
    internal func aFloorRefusalNamesPin2AndPointsToThePuk() {
      for verdict in [RetryFloorVerdict.refuseLowAttempts, .refuseBlocked] {
        let message = DocumentSigningMessage.message(
          for: DocumentSigner.Failure.card(.floorRefused(verdict)))
        #expect(message.contains("PIN 2"))
        #expect(message.contains("PUK"))
      }
    }

    @Test
    internal func aPhoneThatCouldNotSignReadsAsNoSignature() {
      #expect(
        DocumentSigningMessage.message(for: RappRequesterClientError.terminal(.operationFailed))
          == DocumentSigningMessage.message(for: DocumentSigner.Failure.remote(.noSignature)))
    }

    @Test
    internal func aCauseSharedByThePileIsSaidOnce() throws {
      let message = try #require(
        SignDocumentModel.pileFailure([
          (name: "first.pdf", message: "Cause."),
          (name: "second.pdf", message: "Cause."),
        ]))
      #expect(message == "first.pdf\nsecond.pdf\n\nCause.")
    }

    @Test
    internal func distinctCausesAreListedPerDocument() throws {
      let message = try #require(
        SignDocumentModel.pileFailure([
          (name: "first.pdf", message: "One."),
          (name: "second.pdf", message: "Other."),
        ]))
      #expect(message == "first.pdf: One.\nsecond.pdf: Other.")
      #expect(SignDocumentModel.pileFailure([]) == nil)
    }

    @Test
    @MainActor
    internal func aFailureWaitsUntilAcknowledged() {
      let model = SignDocumentModel()
      model.report("Cause.")
      #expect(model.unacknowledgedFailure == "Cause.")
      model.acknowledgeFailure()
      #expect(model.unacknowledgedFailure == nil)
    }

    @Test
    @MainActor
    internal func aPileReportsOnceWhenFinished() {
      let model = SignDocumentModel()
      model.beginPile()
      model.report("First cause.")
      #expect(model.unacknowledgedFailure == nil)
      model.endPile(failing: "Pile cause.")
      #expect(model.unacknowledgedFailure == "Pile cause.")
    }
  }

#endif
