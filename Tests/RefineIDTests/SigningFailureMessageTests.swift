// Copyright 2026 Petri Koistinen. Licensed under the Apache License, Version 2.0.

#if os(macOS)

  import CardCore
  import Foundation
  import Testing

  @testable import RefineID

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
      RappRequesterClientError.terminal(.userDenied),
      RappRequesterClientError.terminal(.requestExpired),
      RappRequesterClientError.terminal(.cancelled),
      RappRequesterClientError.terminal(.requestInvalidOrUnsupported),
      RappRequesterClientError.terminal(.retryPolicyRefused),
      RappRequesterClientError.terminal(.credentialRejected),
      RappRequesterClientError.terminal(.cardRemovedBeforeTransmit),
      RappRequesterClientError.terminal(.cardCompletionAmbiguous),
      RappRequesterClientError.terminal(.invalidCredential),
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
    internal func phoneCredentialOutcomesMatchTheLocalOnes() {
      #expect(
        DocumentSigningMessage.message(
          for: RappRequesterClientError.terminal(.credentialRejected))
          == DocumentSigningMessage.message(for: DocumentSigner.Failure.card(.pinBlocked)))
      #expect(
        DocumentSigningMessage.message(
          for: RappRequesterClientError.terminal(.invalidCredential))
          == CredentialOutcomeMessage.incorrect(credentialName: "PIN 2"))
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
